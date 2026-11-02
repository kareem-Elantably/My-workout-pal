import 'package:excel/excel.dart';
import 'package:fitness_app/core/plan_models.dart';
import 'package:fitness_app/features/coach/excel_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseReps', () {
    PlanRow parse(String text) => PlanRow(rowNumber: 2)..errors.addAll(parseReps(text, PlanRow(rowNumber: 2)) ? {} : {RowError.badReps});

    test('ranges and fixed reps', () {
      final row = PlanRow(rowNumber: 2);
      expect(parseReps('8-10', row), isTrue);
      expect((row.repsMin, row.repsMax), (8, 10));
      final fixed = PlanRow(rowNumber: 2);
      expect(parseReps('12', fixed), isTrue);
      expect((fixed.repsMin, fixed.repsMax), (12, null));
    });

    test('times and distances set how the exercise is logged', () {
      final plank = PlanRow(rowNumber: 2);
      expect(parseReps('45s', plank), isTrue);
      expect((plank.durationSeconds, plank.tracking), (45, Tracking.duration));
      final bike = PlanRow(rowNumber: 2);
      expect(parseReps('20 min', bike), isTrue);
      expect(bike.durationSeconds, 1200);
      final run = PlanRow(rowNumber: 2);
      expect(parseReps('2 km', run), isTrue);
      expect((run.distanceM, run.tracking), (2000, Tracking.distanceDuration));
    });

    test('rejects what it cannot read', () {
      expect(parse('lots').errors, {RowError.badReps});
      expect(parse('10-8').errors, {RowError.badReps}, reason: 'a range must go up');
    });
  });

  test('the template parses back without errors', () {
    final rows = parseWorkbook(buildTemplate());
    expect(rows, hasLength(9));
    expect(rows.every((r) => r.errors.isEmpty), isTrue, reason: rows.map((r) => r.errors).toString());
    expect(rows.first.exercise, 'Bench Press');
    expect((rows.first.dayNumber, rows.first.dayName, rows.first.sets, rows.first.repsMin, rows.first.repsMax), (1, 'Push Day', 4, 8, 10));
    expect(rows.first.notes, 'Pause at bottom');
    expect(rows.firstWhere((r) => r.exercise == 'Plank').tracking, Tracking.duration);
    expect(rows.firstWhere((r) => r.exercise == 'Treadmill').tracking, Tracking.distanceDuration);
    expect(rows.where((r) => r.superset == 'A'), hasLength(2));
  });

  test('every problem is reported with its row number; blank rows are skipped', () {
    final excel = Excel.createExcel();
    final sheet = excel.tables.keys.first;
    excel.appendRow(sheet, [for (final c in templateColumns) TextCellValue(c)]);
    excel.appendRow(sheet, [IntCellValue(1), TextCellValue('Push'), IntCellValue(1), TextCellValue('Bench'), IntCellValue(3), TextCellValue('10')]);
    excel.appendRow(sheet, [null, null, null, null, null, null]);
    excel.appendRow(sheet, [null, TextCellValue('Pull'), IntCellValue(1), null, TextCellValue('x'), TextCellValue('heavy')]);
    final rows = parseWorkbook(excel.encode()!);
    expect(rows, hasLength(2));
    expect(rows.first.errors, isEmpty);
    expect(rows.last.rowNumber, 4);
    expect(rows.last.errors, {RowError.missingDay, RowError.missingExercise, RowError.badSets, RowError.badReps});
  });
}
