import 'package:fitness_app/app.dart';
import 'package:fitness_app/core/models.dart';
import 'package:fitness_app/core/providers.dart';
import 'package:fitness_app/data/home_repository.dart';
import 'package:fitness_app/data/workout_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  late Mocks mocks;
  late MockOnboardingRepository onboarding;
  late MockHomeRepository home;
  late FakeSessionNotifier session;

  setUpAll(registerFallbacks);

  setUp(() {
    mocks = Mocks();
    onboarding = mocks.onboarding;
    home = mocks.home;
  });

  /// The whole app with a fixed session and mocked data.
  Future<void> pumpApp(WidgetTester tester, AuthSession initial, {String locale = 'en'}) async {
    SharedPreferences.setMockInitialValues({'locale': locale});
    final preferences = await SharedPreferences.getInstance();
    session = FakeSessionNotifier(initial);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        sessionProvider.overrideWith(() => session),
        ...mocks.overrides,
      ],
      child: const FitnessApp(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('signed out: the welcome screen, in Arabic and right-to-left by default', (tester) async {
    await pumpApp(tester, const SignedOut(), locale: 'ar');

    expect(find.text('عايز مدرب'), findsOneWidget);
    expect(find.text('أنا مدرب'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('عايز مدرب'))), TextDirection.rtl);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('I want a coach'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('I want a coach'))), TextDirection.ltr);
  });

  testWidgets('a new trainee answers the questions step by step, then submits', (tester) async {
    const section = QuestionSection(id: 1, key: 'training', titleEn: 'Training background', titleAr: 'خلفيتك');
    const sessions = Question(
      id: 'q-sessions',
      key: 'sessions_per_week',
      sectionId: 1,
      textEn: 'How many times would you exercise per week?',
      textAr: '...',
      type: AnswerType.number,
      isRequired: true,
      min: 1,
      max: 7,
    );
    const injuries = Question(
      id: 'q-injuries',
      key: 'injuries',
      sectionId: 2,
      textEn: 'Do you have any injuries?',
      textAr: '...',
      type: AnswerType.text,
      isRequired: false,
    );
    when(() => onboarding.loadSteps(AppRole.trainee)).thenAnswer((_) async => const [
          QuestionStep(section: section, questions: [sessions]),
          QuestionStep(section: null, questions: [injuries]),
        ]);
    when(() => onboarding.loadAnswers('user-1')).thenAnswer((_) async => {});
    when(() => onboarding.saveAnswers(any(), any())).thenAnswer((_) async {});
    when(() => onboarding.submitApplication(any(), AppRole.trainee)).thenAnswer((_) async {});

    await pumpApp(tester, SignedIn(sessionData()));

    expect(find.text('Training background'), findsOneWidget);
    expect(find.text('Step 1 of 2'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);
    verifyNever(() => onboarding.saveAnswers(any(), any()));

    await tester.enterText(find.byType(TextFormField), '4');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    verify(() => onboarding.saveAnswers('user-1', {'q-sessions': 4})).called(1);
    expect(find.text('Step 2 of 2'), findsOneWidget);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    verify(() => onboarding.saveAnswers('user-1', {'q-injuries': null})).called(1);
    verify(() => onboarding.submitApplication(any(), AppRole.trainee)).called(1);
    expect(session.refreshes, 1, reason: 'the session reloads so the router moves to the waiting screen');
  });

  testWidgets('a pending application shows the waiting screen', (tester) async {
    await pumpApp(tester, SignedIn(sessionData(applications: [application(AppRole.trainee, ApplicationStatus.pending)])));
    expect(find.text("You're on the list"), findsOneWidget);
  });

  testWidgets('an approved trainee without plans sees that plans are being prepared', (tester) async {
    await pumpApp(tester, SignedIn(sessionData(roles: {AppRole.trainee})));
    expect(find.text('Your plans are being prepared'), findsOneWidget);
  });

  testWidgets('today: the suggested workout, the meals, and "all done"', (tester) async {
    when(() => mocks.workout.activePlan('user-1')).thenAnswer((_) async => sampleWorkoutPlan());
    when(() => mocks.workout.nextWorkout('user-1')).thenAnswer(
        (_) async => const NextWorkout(dayNumber: 1, workoutDayId: 'day-push', isPlannedRest: false, loggedToday: false));
    when(() => mocks.workout.streak('user-1')).thenAnswer((_) async => 5);
    when(() => mocks.nutrition.activePlan('user-1')).thenAnswer((_) async => sampleNutritionPlan());
    when(() => mocks.nutrition.logAll(
          traineeId: any(named: 'traineeId'),
          meals: any(named: 'meals'),
          existing: any(named: 'existing'),
          day: any(named: 'day'),
        )).thenAnswer((_) async {});

    await pumpApp(tester, SignedIn(sessionData(roles: {AppRole.trainee})));

    expect(find.text('5 day streak'), findsOneWidget);
    expect(find.text('Day 1 · Push'), findsOneWidget);
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('Choose another day'), findsOneWidget);
    expect(find.text('Breakfast · 08:00'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);

    await tester.tap(find.text('All done'));
    await tester.pumpAndSettle();
    verify(() => mocks.nutrition.logAll(
          traineeId: 'user-1',
          meals: any(named: 'meals'),
          existing: any(named: 'existing'),
          day: any(named: 'day'),
        )).called(1);
  });

  testWidgets('water: each tap adds a glass and saves the day\'s total', (tester) async {
    when(() => mocks.workout.activePlan('user-1')).thenAnswer((_) async => sampleWorkoutPlan());
    when(() => mocks.nutrition.waterOn('user-1', any())).thenAnswer((_) async => 1000);
    await pumpApp(tester, SignedIn(sessionData(roles: {AppRole.trainee})));

    final glass = find.text('Glass (250 ml)');
    await tester.ensureVisible(glass);
    await tester.pumpAndSettle();
    expect(find.text('1 L'), findsOneWidget);
    expect(find.text('Goal 2.5 L'), findsOneWidget);

    await tester.tap(glass);
    await tester.tap(glass);
    await tester.pumpAndSettle();
    expect(find.text('1.5 L'), findsOneWidget);
    verifyInOrder([
      () => mocks.nutrition.setWater('user-1', any(), 1250),
      () => mocks.nutrition.setWater('user-1', any(), 1500),
    ]);

    await tester.tap(find.byTooltip('Remove a glass'));
    await tester.pumpAndSettle();
    // The earlier 1250 was already counted by verifyInOrder.
    verify(() => mocks.nutrition.setWater('user-1', any(), 1250)).called(1);
    expect(find.text('1.25 L'), findsOneWidget);
  });

  testWidgets('a planned rest day offers "Train anyway"', (tester) async {
    when(() => mocks.workout.activePlan('user-1')).thenAnswer((_) async => sampleWorkoutPlan());
    when(() => mocks.workout.nextWorkout('user-1'))
        .thenAnswer((_) async => const NextWorkout(dayNumber: 3, isPlannedRest: true, loggedToday: false));
    await pumpApp(tester, SignedIn(sessionData(roles: {AppRole.trainee})));
    expect(find.text('Planned rest day'), findsOneWidget);
    await tester.tap(find.text('Train anyway'));
    await tester.pumpAndSettle();
    expect(find.text('Which day do you want to train?'), findsOneWidget);
    expect(find.text('Pull'), findsOneWidget);
  });

  testWidgets('a coach sees trainees with what needs attention', (tester) async {
    when(() => home.coachDashboard()).thenAnswer((_) async => const [
          CoachTrainee(
            traineeId: 't1',
            fullName: 'Omar',
            scopes: ['workout'],
            trainedToday: false,
            mealsDoneToday: 2,
            mealsTotalToday: 4,
            missedDays7: 2,
            milestonesDue: 1,
            unreadMessages: 0,
            streak: 5,
          ),
        ]);
    await pumpApp(tester, SignedIn(sessionData(roles: {AppRole.coach})));
    expect(find.text('Omar'), findsOneWidget);
    expect(find.text('No workout today · Meals 2/4 · 2 missed days · 1 check-in due'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });
}
