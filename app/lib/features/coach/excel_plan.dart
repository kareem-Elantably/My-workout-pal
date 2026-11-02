import 'package:excel/excel.dart';

import '../../core/plan_models.dart';

/// Columns of the workout upload template, in order.
const templateColumns = [
  'Day #', 'Day name', 'Order', 'Exercise', 'Sets', 'Reps', 'Rest (sec)', 'Tempo', //
  'Superset group', 'Video link 1', 'Video link 2', 'Coach notes',
];

/// Problems with a spreadsheet row (shown in the user's language by the UI).
enum RowError { missingDay, missingDayName, missingOrder, missingExercise, badSets, badReps }

class PlanRow {
  PlanRow({required this.rowNumber});

  final int rowNumber;
  int? dayNumber;
  String? dayName;
  int? order;
  String? exercise;
  int? sets;
  int? repsMin;
  int? repsMax;
  int? durationSeconds;
  num? distanceM;
  int? restSeconds;
  String? tempo;
  String? superset;
  String? video1;
  String? video2;
  String? notes;
  final errors = <RowError>{};

  /// How the exercise is logged, inferred from the Reps column.
  Tracking get tracking => distanceM != null
      ? Tracking.distanceDuration
      : durationSeconds != null
          ? Tracking.duration
          : Tracking.weightReps;
}

/// An example sheet coaches fill in (three days and a rest day).
List<int> buildTemplate() {
  final excel = Excel.createExcel();
  final sheet = excel.tables.keys.first;
  excel.rename(sheet, 'Plan');
  TextCellValue t(String s) => TextCellValue(s);
  excel.appendRow('Plan', [for (final c in templateColumns) t(c)]);
  for (final row in const [
    [1, 'Push Day', 1, 'Bench Press', 4, '8-10', 90, '3-1-1', '', '', '', 'Pause at bottom'],
    [1, 'Push Day', 2, 'Shoulder Press', 3, '10-12', 75, '', '', '', '', ''],
    [1, 'Push Day', 3, 'Lateral Raise', 3, '12-15', 60, '', 'A', '', '', ''],
    [1, 'Push Day', 4, 'Tricep Pushdown', 3, '12', 60, '', 'A', '', '', ''],
    [2, 'Pull Day', 1, 'Pull Up', 4, '6-10', 120, '', '', '', '', ''],
    [2, 'Pull Day', 2, 'Barbell Row', 4, '8-10', 90, '', '', '', '', ''],
    [3, 'Legs', 1, 'Squat', 4, '6-8', 150, '', '', '', '', ''],
    [3, 'Legs', 2, 'Plank', 3, '45s', 60, '', '', '', '', ''],
    [3, 'Legs', 3, 'Treadmill', 1, '2 km', '', '', '', '', '', '15 min easy pace'],
  ]) {
    excel.appendRow('Plan', [
      for (final v in row) v is int ? IntCellValue(v) : (v as String).isEmpty ? null : t(v),
    ]);
  }
  return excel.encode()!;
}

String? _text(Data? cell) {
  final value = cell?.value;
  if (value == null) return null;
  final s = switch (value) {
    TextCellValue() => value.toString(),
    IntCellValue() => '${value.value}',
    DoubleCellValue() => formatNum(value.value),
    _ => value.toString(),
  };
  return s.trim().isEmpty ? null : s.trim();
}

int? _int(Data? cell) {
  final s = _text(cell);
  return s == null ? null : (num.tryParse(s)?.round());
}

/// Fills reps / duration / distance from the Reps column:
/// "8-10", "12", "45s", "30 sec", "20 min", "2 km", "400 m".
bool parseReps(String? text, PlanRow row) {
  if (text == null) return false;
  final s = text.toLowerCase().replaceAll(' ', '').replaceAll('–', '-');
  final range = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(s);
  if (range != null) {
    row.repsMin = int.parse(range[1]!);
    row.repsMax = range[2] == null ? null : int.parse(range[2]!);
    return row.repsMax == null || row.repsMax! >= row.repsMin!;
  }
  final time = RegExp(r'^(\d+(?:\.\d+)?)(s|sec|secs|seconds|min|mins|minutes)$').firstMatch(s);
  if (time != null) {
    final n = double.parse(time[1]!);
    row.durationSeconds = (time[2]!.startsWith('m') ? n * 60 : n).round();
    return true;
  }
  final distance = RegExp(r'^(\d+(?:\.\d+)?)(km|m)$').firstMatch(s);
  if (distance != null) {
    final n = double.parse(distance[1]!);
    row.distanceM = distance[2] == 'km' ? n * 1000 : n;
    return true;
  }
  return false;
}

/// Reads the first sheet. Blank rows are skipped; every other row is
/// returned with its problems (if any).
List<PlanRow> parseWorkbook(List<int> bytes) {
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables.values.first;
  final rows = <PlanRow>[];
  for (var i = 1; i < sheet.rows.length; i++) {
    final cells = sheet.rows[i];
    Data? cell(int c) => c < cells.length ? cells[c] : null;
    if (List.generate(templateColumns.length, cell).every((c) => _text(c) == null)) continue;
    final row = PlanRow(rowNumber: i + 1)
      ..dayNumber = _int(cell(0))
      ..dayName = _text(cell(1))
      ..order = _int(cell(2))
      ..exercise = _text(cell(3))
      ..sets = _int(cell(4))
      ..restSeconds = _int(cell(6))
      ..tempo = _text(cell(7))
      ..superset = _text(cell(8))
      ..video1 = _text(cell(9))
      ..video2 = _text(cell(10))
      ..notes = _text(cell(11));
    if (row.dayNumber == null || row.dayNumber! < 1) row.errors.add(RowError.missingDay);
    if (row.dayName == null) row.errors.add(RowError.missingDayName);
    if (row.order == null) row.errors.add(RowError.missingOrder);
    if (row.exercise == null) row.errors.add(RowError.missingExercise);
    if (row.sets == null || row.sets! < 1) row.errors.add(RowError.badSets);
    if (!parseReps(_text(cell(5)), row)) row.errors.add(RowError.badReps);
    rows.add(row);
  }
  return rows;
}
