import '../core/models.dart';
import '../core/providers.dart';

/// Screens are nested so that back always returns to the parent: e.g.
/// /welcome/login/forgot -> /welcome/login -> /welcome.
abstract final class Routes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const login = '/welcome/login';
  static const forgotPassword = '/welcome/login/forgot';
  static String signup(AppRole role) => '/welcome/signup/${role.name}';
  static const checkEmail = '/welcome/check-email';
  static const resetPassword = '/reset-password';
  static const onboarding = '/onboarding';
  static const certificates = '/onboarding/certificates';
  static const waiting = '/waiting';
  static const profile = '/profile';
  static String home(AppRole role) => '/${role.name}';
  static String application(String id) => '/admin/applications/$id';
}

/// Default role when the user hasn't picked one: day-to-day work first.
const _rolePriority = [AppRole.coach, AppRole.admin, AppRole.trainee];

AppRole resolveActiveRole(Set<AppRole> roles, AppRole? selected) =>
    selected != null && roles.contains(selected) ? selected : _rolePriority.firstWhere(roles.contains);

/// Where the user must be for their state; null means stay on [location].
///
/// [session] is null while it loads (or failed to load). [passwordRecovery]
/// is true after opening a password-reset link, until a new password is set.
String? resolveRedirect({
  required AuthSession? session,
  required AppRole? selectedRole,
  required String location,
  bool passwordRecovery = false,
}) {
  String? goTo(String target) => location == target ? null : target;

  if (session == null) return goTo(Routes.splash);

  if (session is SignedOut) {
    return location == Routes.welcome || location.startsWith('${Routes.welcome}/') ? null : Routes.welcome;
  }

  if (passwordRecovery) return goTo(Routes.resetPassword);

  final data = (session as SignedIn).data;

  // Not approved for any role yet: finish sign-up, then wait for the admin.
  if (data.roles.isEmpty) {
    final application = data.latestApplicationFor(data.signupRole);
    final inOnboarding = location == Routes.onboarding || location == Routes.certificates;
    if (application == null) return inOnboarding ? null : Routes.onboarding;
    if (application.status == ApplicationStatus.rejected && inOnboarding) return null; // updating answers to reapply
    return goTo(Routes.waiting);
  }

  final role = resolveActiveRole(data.roles, selectedRole);
  final home = Routes.home(role);
  if (location == home || location.startsWith('$home/') || location == Routes.profile) return null;
  return home;
}
