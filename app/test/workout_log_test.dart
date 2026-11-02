import 'package:fitness_app/core/plan_models.dart';
import 'package:fitness_app/core/providers.dart';
import 'package:fitness_app/features/trainee/workout_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  late Mocks mocks;

  setUpAll(registerFallbacks);

  setUp(() => mocks = Mocks());

  Future<void> pumpLog(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'locale': 'en'});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        sessionProvider.overrideWith(() => FakeSessionNotifier(SignedIn(sessionData(roles: const {})))),
        ...mocks.overrides,
      ],
      // Like the app: screens below the router only appear once the session has loaded.
      child: localizedApp(Consumer(
        builder: (context, ref, _) => ref.watch(sessionProvider).hasValue
            ? WorkoutLogScreen(workoutDayId: 'day-push', date: today())
            : const SizedBox.shrink(),
      )),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sets are pre-filled from last time, and one tap logs a set', (tester) async {
    when(() => mocks.workout.activePlan('user-1')).thenAnswer((_) async => sampleWorkoutPlan());
    when(() => mocks.workout.lastValues('user-1', 'ex-bench')).thenAnswer((_) async => {
          1: const SetLog(id: '', dayExerciseId: '', setNumber: 1, reps: 9, weightKg: 60),
        });
    when(() => mocks.workout.startSession('user-1', 'day-push', any()))
        .thenAnswer((_) async => WorkoutSession(id: 'session-1', workoutDayId: 'day-push', date: today()));
    when(() => mocks.workout.saveSet(
          sessionId: any(named: 'sessionId'),
          dayExercise: any(named: 'dayExercise'),
          setNumber: any(named: 'setNumber'),
          reps: any(named: 'reps'),
          weightKg: any(named: 'weightKg'),
          durationSeconds: any(named: 'durationSeconds'),
          distanceM: any(named: 'distanceM'),
        )).thenAnswer((_) async => const SetLog(id: 'set-1', dayExerciseId: 'de-bench', setNumber: 1));

    await pumpLog(tester);

    expect(find.text('Day 1 · Push'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    // Two planned sets, both pre-filled with last time's 60 kg x 9.
    expect(find.text('60 kg'), findsNWidgets(2));
    expect(find.text('9 ×'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Log set').first);
    await tester.pumpAndSettle();

    verify(() => mocks.workout.startSession('user-1', 'day-push', any())).called(1);
    verify(() => mocks.workout.saveSet(
          sessionId: 'session-1',
          dayExercise: any(named: 'dayExercise'),
          setNumber: 1,
          reps: 9,
          weightKg: 60,
          durationSeconds: null,
          distanceM: null,
        )).called(1);
    expect(find.byTooltip('Undo set'), findsOneWidget);
    expect(find.textContaining('Rest 1:'), findsOneWidget, reason: 'the rest timer starts after a set');
  });

  testWidgets('the steppers change the weight in 2.5 kg steps', (tester) async {
    when(() => mocks.workout.activePlan('user-1')).thenAnswer((_) async => sampleWorkoutPlan());
    await pumpLog(tester);
    expect(find.text('0 kg'), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump();
    expect(find.text('2.5 kg'), findsOneWidget);
  });
}
