import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../features/admin/admin_home.dart';
import '../features/admin/application_screen.dart';
import '../features/auth/check_email_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/home/coach_home.dart';
import '../features/home/profile_screen.dart';
import '../features/home/splash_screen.dart';
import '../features/home/trainee_home.dart';
import '../features/onboarding/certificates_screen.dart';
import '../features/onboarding/questions_screen.dart';
import '../features/onboarding/waiting_screen.dart';
import 'redirect.dart';

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
      GoRoute(path: Routes.home(AppRole.trainee), builder: (_, _) => const TraineeHome()),
      GoRoute(path: Routes.home(AppRole.coach), builder: (_, _) => const CoachHome()),
      GoRoute(
        path: Routes.home(AppRole.admin),
        builder: (_, _) => const AdminHome(),
        routes: [
          GoRoute(
            path: 'applications/:id',
            builder: (_, state) => ApplicationScreen(applicationId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
