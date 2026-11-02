import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../core/ui.dart';
import '../features/admin/admin_shell.dart';
import '../features/admin/application_screen.dart';
import '../features/admin/people_screens.dart';
import '../features/auth/check_email_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/coach/coach_shell.dart';
import '../features/coach/import_screen.dart';
import '../features/coach/nutrition_editor_screen.dart';
import '../features/coach/trainee_detail_screen.dart';
import '../features/coach/workout_editor_screen.dart';
import '../features/home/profile_screen.dart';
import '../features/home/splash_screen.dart';
import '../features/onboarding/certificates_screen.dart';
import '../features/onboarding/questions_screen.dart';
import '../features/onboarding/waiting_screen.dart';
import '../features/shared/chat_screens.dart';
import '../features/shared/earnings_view.dart';
import '../features/shared/meal_converter_screen.dart';
import '../features/shared/more_tab.dart';
import '../features/shared/notes_screen.dart';
import '../features/shared/notifications_screen.dart';
import '../features/shared/progress_views.dart';
import '../features/trainee/reminders_screen.dart';
import '../features/trainee/trainee_shell.dart';
import '../features/trainee/workout_log_screen.dart';
import 'redirect.dart';

/// Lets push notifications navigate (they arrive outside the widget tree).
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Screens every role has, under its own home so back stays in the role.
List<RouteBase> _sharedRoutes() => [
      GoRoute(path: 'notifications', builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: 'notes', builder: (_, _) => const NotesScreen()),
      GoRoute(path: 'tools', builder: (_, _) => const MealConverterScreen()),
      GoRoute(
        path: 'chat/:id',
        builder: (_, state) => ChatScreen(conversationId: state.pathParameters['id']!, title: state.uri.queryParameters['name']),
      ),
      GoRoute(
        path: 'milestone/:id',
        builder: (_, state) => Consumer(
          builder: (context, ref, _) => MilestoneScreen(
            milestoneId: state.pathParameters['id']!,
            traineeId: state.uri.queryParameters['trainee'] ?? ref.read(myIdProvider),
          ),
        ),
      ),
    ];

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run the redirect whenever the session, the chosen role or password
  // recovery changes.
  final refresh = ValueNotifier(0);
  ref
    ..listen(sessionProvider, (_, _) => refresh.value++)
    ..listen(activeRoleProvider, (_, _) => refresh.value++)
    ..listen(passwordRecoveryProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      return resolveRedirect(
        session: session.hasError ? null : session.value,
        selectedRole: ref.read(activeRoleProvider),
        location: state.matchedLocation,
        passwordRecovery: ref.read(passwordRecoveryProvider),
      );
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: Routes.welcome,
        builder: (_, _) => const WelcomeScreen(),
        routes: [
          GoRoute(
            path: 'login',
            builder: (_, state) => LoginScreen(email: state.uri.queryParameters['email']),
            routes: [
              GoRoute(
                path: 'forgot',
                builder: (_, state) => ForgotPasswordScreen(email: state.uri.queryParameters['email']),
              ),
            ],
          ),
          GoRoute(
            path: 'signup/:role',
            builder: (_, state) =>
                SignupScreen(role: AppRole.fromKey(state.pathParameters['role']) ?? AppRole.trainee),
          ),
          GoRoute(
            path: 'check-email',
            builder: (_, state) => CheckEmailScreen(email: state.uri.queryParameters['email'] ?? ''),
          ),
        ],
      ),
      GoRoute(path: Routes.resetPassword, builder: (_, _) => const ResetPasswordScreen()),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const QuestionsScreen(),
        routes: [GoRoute(path: 'certificates', builder: (_, _) => const CertificatesScreen())],
      ),
      GoRoute(path: Routes.waiting, builder: (_, _) => const WaitingScreen()),
      GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
      GoRoute(
        path: Routes.home(AppRole.trainee),
        builder: (_, _) => const TraineeShell(),
        routes: [
          ..._sharedRoutes(),
          GoRoute(
            path: 'workout',
            builder: (_, state) => WorkoutLogScreen(
              workoutDayId: state.uri.queryParameters['day']!,
              date: DateTime.parse(state.uri.queryParameters['date']!),
            ),
          ),
          GoRoute(path: 'reminders', builder: (_, _) => const RemindersScreen()),
          GoRoute(
            path: 'subscription',
            builder: (_, _) => const SubscriptionScreen(),
          ),
        ],
      ),
      GoRoute(
        path: Routes.home(AppRole.coach),
        builder: (_, _) => const CoachShell(),
        routes: [
          ..._sharedRoutes(),
          GoRoute(
            path: 'trainees/:id',
            builder: (_, state) => TraineeDetailScreen(traineeId: state.pathParameters['id']!),
            routes: [
              GoRoute(path: 'compare', builder: (_, state) => CompareScreen(traineeId: state.pathParameters['id']!)),
            ],
          ),
          GoRoute(path: 'workout-plans/:id', builder: (_, state) => WorkoutEditorScreen(planId: state.pathParameters['id']!)),
          GoRoute(path: 'nutrition-plans/:id', builder: (_, state) => NutritionEditorScreen(planId: state.pathParameters['id']!)),
          GoRoute(path: 'import', builder: (_, state) => ImportScreen(traineeId: state.uri.queryParameters['trainee'])),
        ],
      ),
      GoRoute(
        path: Routes.home(AppRole.admin),
        builder: (_, state) => AdminShell(initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0),
        routes: [
          ..._sharedRoutes(),
          GoRoute(
            path: 'applications/:id',
            builder: (_, state) => ApplicationScreen(applicationId: state.pathParameters['id']!),
          ),
          GoRoute(path: 'people/:id', builder: (_, state) => PersonScreen(userId: state.pathParameters['id']!)),
          GoRoute(
            path: 'subscriptions/new',
            builder: (_, state) => SubscriptionEditorScreen(traineeId: state.uri.queryParameters['trainee']),
          ),
          GoRoute(
            path: 'subscriptions/:id',
            builder: (_, state) => SubscriptionEditorScreen(subscriptionId: state.pathParameters['id']),
          ),
          GoRoute(
            path: 'earnings',
            builder: (context, _) => Scaffold(
              appBar: AppBar(title: Text(context.l10n.earningsByCoach)),
              body: const EarningsView(byTrainee: false),
            ),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
