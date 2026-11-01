import '../core/models.dart';
import '../core/providers.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const login = '/login';
  static const checkEmail = '/check-email';
  static String signup(AppRole role) => '/signup/${role.name}';
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
/// [session] is null while it loads (or failed to load).
String? resolveRedirect({required AuthSession? session, required AppRole? selectedRole, required String location}) {
  String? goTo(String target) => location == target ? null : target;

  if (session == null) return goTo(Routes.splash);

  if (session is SignedOut) {
    final public = location == Routes.welcome ||
        location == Routes.login ||
        location == Routes.checkEmail ||
        location.startsWith('/signup/');
    return public ? null : Routes.welcome;
  }

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
