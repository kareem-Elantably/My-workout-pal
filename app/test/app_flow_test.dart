import 'package:fitness_app/app.dart';
import 'package:fitness_app/core/models.dart';
import 'package:fitness_app/core/providers.dart';
import 'package:fitness_app/data/home_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  late MockOnboardingRepository onboarding;
  late MockHomeRepository home;
  late FakeSessionNotifier session;

  setUpAll(() => registerFallbackValue(sessionData()));

  setUp(() {
    onboarding = MockOnboardingRepository();
    home = MockHomeRepository();
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
        onboardingRepositoryProvider.overrideWithValue(onboarding),
        homeRepositoryProvider.overrideWithValue(home),
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
    when(() => home.today('user-1')).thenAnswer((_) async => const TodaySummary(hasPlan: false, streak: 0));
    await pumpApp(tester, SignedIn(sessionData(roles: {AppRole.trainee})));
    expect(find.text('Your plans are being prepared'), findsOneWidget);
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
