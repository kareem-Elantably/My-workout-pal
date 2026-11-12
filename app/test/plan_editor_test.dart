import 'package:fitness_app/core/plan_models.dart';
import 'package:fitness_app/core/providers.dart';
import 'package:fitness_app/features/coach/workout_editor_screen.dart';
import 'package:fitness_app/features/shared/food_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  late Mocks mocks;

  setUpAll(() {
    registerFallbacks();
    registerFallbackValue(sampleWorkoutPlan().versions.first);
    registerFallbackValue(sampleWorkoutPlan().versions.first.days.first);
  });

  setUp(() => mocks = Mocks());

  Future<void> pump(WidgetTester tester, Widget child) async {
    SharedPreferences.setMockInitialValues({'locale': 'en'});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        sessionProvider.overrideWith(() => FakeSessionNotifier(SignedIn(sessionData()))),
        ...mocks.overrides,
      ],
      child: localizedApp(child),
    ));
    await tester.pumpAndSettle();
  }

  /// The same plan after "new version": same days, new ids.
  WorkoutPlan copiedPlan() => WorkoutPlan(id: 'plan-1', name: 'PPL', traineeId: 'user-1', versions: [
        WorkoutVersion(id: 'v2', versionNo: 2, cycleLength: 3, effectiveFrom: DateTime(2026, 2, 1), days: [
          WorkoutDay(
            id: 'day-push-2',
            dayNumber: 1,
            name: 'Push',
            exercises: [sampleWorkoutPlan().versions.first.days.first.exercises.first],
          ),
          const WorkoutDay(id: 'day-pull-2', dayNumber: 2, name: 'Pull', exercises: []),
        ]),
        ...sampleWorkoutPlan().versions,
      ]);

  testWidgets('a plan the trainee has logged against is still edited directly', (tester) async {
    var copied = false;
    when(() => mocks.workout.plan('plan-1')).thenAnswer((_) async => copied ? copiedPlan() : sampleWorkoutPlan());
    when(() => mocks.planEditor.workoutVersionFrozen(any()))
        .thenAnswer((i) async => (i.positionalArguments.first as WorkoutVersion).id == 'v1');
    when(() => mocks.planEditor.copyWorkoutVersion('v1', 'plan-1')).thenAnswer((_) async {
      copied = true;
      return 'v2';
    });
    when(() => mocks.planEditor.duplicateDayExercise(any(), any())).thenAnswer((_) async {});

    await pump(tester, const WorkoutEditorScreen(planId: 'plan-1'));

    // No lock, no "new version" step: the menu is right there.
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    await tester.tap(find.byTooltip('Exercise options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    verify(() => mocks.planEditor.copyWorkoutVersion('v1', 'plan-1')).called(1);
    final day = verify(() => mocks.planEditor.duplicateDayExercise(captureAny(), 0)).captured.single as WorkoutDay;
    expect(day.id, 'day-push-2', reason: 'the change lands in the new version');
    expect(find.textContaining('this applies from today'), findsOneWidget);
  });

  testWidgets('a coach adds a food that is not in the library from the search', (tester) async {
    const molokhia = Food(id: 'food-new', nameEn: 'Molokhia', source: 'custom', kcal: 30, protein: 3, carbs: 4, fat: 1);
    when(() => mocks.library.searchFoods(any())).thenAnswer((_) async => []);
    when(() => mocks.library.createFood(
          nameEn: any(named: 'nameEn'),
          nameAr: any(named: 'nameAr'),
          kcal: any(named: 'kcal'),
          protein: any(named: 'protein'),
          carbs: any(named: 'carbs'),
          fat: any(named: 'fat'),
          barcode: any(named: 'barcode'),
          units: any(named: 'units'),
        )).thenAnswer((_) async => molokhia);
    Food? picked;

    await pump(
      tester,
      Builder(builder: (context) => TextButton(onPressed: () async => picked = await pickFood(context, canAdd: true), child: const Text('pick'))),
    );
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Molokhia');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add "Molokhia" as a new food'));
    await tester.pumpAndSettle();
    // What they searched for is already filled in.
    expect(find.widgetWithText(TextFormField, 'Molokhia'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'kcal'), '30');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(picked?.id, 'food-new', reason: 'the new food goes straight into the meal');
  });

  testWidgets('a trainee is told to ask the coach for a missing food', (tester) async {
    when(() => mocks.library.searchFoods(any())).thenAnswer((_) async => []);
    await pump(tester, Builder(builder: (context) => TextButton(onPressed: () => pickFood(context), child: const Text('pick'))));
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ask your coach'), findsOneWidget);
    expect(find.textContaining('as a new food'), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
  });
}
