import 'package:fitness_app/core/models.dart';
import 'package:fitness_app/core/providers.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:fitness_app/core/plan_models.dart';
import 'package:fitness_app/data/admin_repository.dart';
import 'package:fitness_app/data/home_repository.dart';
import 'package:fitness_app/data/library_repository.dart';
import 'package:fitness_app/data/milestone_repository.dart';
import 'package:fitness_app/data/nutrition_repository.dart';
import 'package:fitness_app/data/onboarding_repository.dart';
import 'package:fitness_app/data/plan_editor_repository.dart';
import 'package:fitness_app/data/social_repository.dart';
import 'package:fitness_app/data/workout_repository.dart';
import 'package:fitness_app/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mocktail/mocktail.dart';

class MockOnboardingRepository extends Mock implements OnboardingRepository {}

class MockHomeRepository extends Mock implements HomeRepository {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockNutritionRepository extends Mock implements NutritionRepository {}

class MockMilestoneRepository extends Mock implements MilestoneRepository {}

class MockSocialRepository extends Mock implements SocialRepository {}

class MockAdminRepository extends Mock implements AdminRepository {}

class MockPlanEditorRepository extends Mock implements PlanEditorRepository {}

class MockLibraryRepository extends Mock implements LibraryRepository {}

/// All data mocks with "nothing yet" answers; tests stub what they need.
class Mocks {
  Mocks() {
    when(() => social.conversations()).thenAnswer((_) async => []);
    when(() => social.unreadNotifications()).thenAnswer((_) async => 0);
    when(() => social.reminders()).thenAnswer((_) async => []);
    when(() => social.inbox()).thenAnswer((_) async => []);
    when(() => workout.activePlan(any())).thenAnswer((_) async => null);
    when(() => workout.sessionOn(any(), any())).thenAnswer((_) async => null);
    when(() => workout.nextWorkout(any())).thenAnswer((_) async => null);
    when(() => workout.streak(any())).thenAnswer((_) async => 0);
    when(() => workout.loggedExercises(any())).thenAnswer((_) async => []);
    when(() => workout.lastValues(any(), any())).thenAnswer((_) async => {});
    when(() => nutrition.activePlan(any())).thenAnswer((_) async => null);
    when(() => nutrition.logsOn(any(), any())).thenAnswer((_) async => []);
    when(() => nutrition.waterOn(any(), any())).thenAnswer((_) async => 0);
    when(() => nutrition.setWater(any(), any(), any())).thenAnswer((_) async {});
    when(() => milestone.forTrainee(any())).thenAnswer((_) async => []);
    when(() => planEditor.workoutTemplates()).thenAnswer((_) async => []);
    when(() => planEditor.nutritionTemplates()).thenAnswer((_) async => []);
    when(() => admin.earnings(any(), any(), byTrainee: any(named: 'byTrainee'), coachId: any(named: 'coachId')))
        .thenAnswer((_) async => []);
    when(() => admin.pendingApplications()).thenAnswer((_) async => []);
  }

  final onboarding = MockOnboardingRepository();
  final home = MockHomeRepository();
  final workout = MockWorkoutRepository();
  final nutrition = MockNutritionRepository();
  final milestone = MockMilestoneRepository();
  final social = MockSocialRepository();
  final admin = MockAdminRepository();
  final planEditor = MockPlanEditorRepository();
  final library = MockLibraryRepository();

  List<Override> get overrides => [
        onboardingRepositoryProvider.overrideWithValue(onboarding),
        homeRepositoryProvider.overrideWithValue(home),
        workoutRepositoryProvider.overrideWithValue(workout),
        nutritionRepositoryProvider.overrideWithValue(nutrition),
        milestoneRepositoryProvider.overrideWithValue(milestone),
        socialRepositoryProvider.overrideWithValue(social),
        adminRepositoryProvider.overrideWithValue(admin),
        planEditorRepositoryProvider.overrideWithValue(planEditor),
        libraryRepositoryProvider.overrideWithValue(library),
      ];
}

void registerFallbacks() {
  registerFallbackValue(sessionData());
  registerFallbackValue(DateTime(2000));
  registerFallbackValue(<Meal>[]);
  registerFallbackValue(<MealLog>[]);
  registerFallbackValue(sampleWorkoutPlan().versions.first.days.first.exercises.first);
}

const _bench = Exercise(id: 'ex-bench', nameEn: 'Bench Press', tracking: Tracking.weightReps);

/// Push (Day 1), Pull (Day 2), planned rest (Day 3) in a 3-day cycle.
WorkoutPlan sampleWorkoutPlan() => WorkoutPlan(id: 'plan-1', name: 'PPL', traineeId: 'user-1', versions: [
      WorkoutVersion(id: 'v1', versionNo: 1, cycleLength: 3, effectiveFrom: DateTime(2026, 1, 1), days: [
        const WorkoutDay(id: 'day-push', dayNumber: 1, name: 'Push', exercises: [
          DayExercise(id: 'de-bench', exercise: _bench, sortOrder: 1, sets: 2, repsMin: 8, repsMax: 10, restSeconds: 90),
        ]),
        const WorkoutDay(id: 'day-pull', dayNumber: 2, name: 'Pull', exercises: []),
      ]),
    ]);

NutritionPlan sampleNutritionPlan() => NutritionPlan(id: 'np-1', name: 'Cut', showMacros: true, traineeId: 'user-1', versions: [
      NutritionVersion(id: 'nv1', versionNo: 1, effectiveFrom: DateTime(2026, 1, 1), meals: const [
        Meal(id: 'meal-1', name: 'Breakfast', sortOrder: 1, countsForStreak: true, timeHint: '08:00', options: [
          MealOption(id: 'opt-a', label: 'A', sortOrder: 1, items: []),
          MealOption(id: 'opt-b', label: 'B', sortOrder: 2, items: []),
        ]),
        Meal(id: 'meal-2', name: 'Lunch', sortOrder: 2, countsForStreak: true, options: []),
      ]),
    ]);

/// Session fixed to a given value, instead of Supabase auth.
class FakeSessionNotifier extends SessionNotifier {
  FakeSessionNotifier(this.initial);

  final AuthSession initial;
  int refreshes = 0;

  @override
  Future<AuthSession> build() async => initial;

  @override
  Future<void> refresh() async => refreshes++;
}

SessionData sessionData({
  AppRole signupRole = AppRole.trainee,
  Set<AppRole> roles = const {},
  List<Application> applications = const [],
}) =>
    SessionData(
      userId: 'user-1',
      email: 'sara@example.com',
      profile: const Profile(id: 'user-1', fullName: 'Sara', gender: 'female', locale: 'en'),
      roles: roles,
      applications: applications,
      signupRole: signupRole,
    );

Application application(AppRole role, ApplicationStatus status) =>
    Application(id: 'app-1', role: role, status: status, submittedAt: DateTime(2026, 11, 1));

/// A screen inside MaterialApp with the app's translations.
Widget localizedApp(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );
