import 'package:fitness_app/core/models.dart';
import 'package:fitness_app/core/providers.dart';
import 'package:fitness_app/router/redirect.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  String? go(AuthSession? session, String location, {AppRole? selected}) =>
      resolveRedirect(session: session, selectedRole: selected, location: location);

  group('loading', () {
    test('shows the splash screen while the session loads', () {
      expect(go(null, '/welcome'), Routes.splash);
      expect(go(null, Routes.splash), isNull);
    });
  });

  group('signed out', () {
    const signedOut = SignedOut();

    test('can use the public screens', () {
      for (final location in [Routes.welcome, Routes.login, Routes.checkEmail, '/signup/trainee', '/signup/coach']) {
        expect(go(signedOut, location), isNull, reason: location);
      }
    });

    test('is sent to welcome from anywhere else', () {
      expect(go(signedOut, Routes.splash), Routes.welcome);
      expect(go(signedOut, '/trainee'), Routes.welcome);
      expect(go(signedOut, Routes.onboarding), Routes.welcome);
    });
  });

  group('signed in, not approved yet', () {
    test('without an application finishes sign-up', () {
      final session = SignedIn(sessionData());
      expect(go(session, Routes.splash), Routes.onboarding);
      expect(go(session, Routes.onboarding), isNull);
      expect(go(session, '/trainee'), Routes.onboarding);
    });

    test('a coach can move on to certificates', () {
      final session = SignedIn(sessionData(signupRole: AppRole.coach));
      expect(go(session, Routes.certificates), isNull);
    });

    test('with a pending application waits', () {
      final session = SignedIn(sessionData(applications: [application(AppRole.trainee, ApplicationStatus.pending)]));
      expect(go(session, Routes.onboarding), Routes.waiting);
      expect(go(session, '/trainee'), Routes.waiting);
      expect(go(session, Routes.waiting), isNull);
    });

    test('after a rejection waits, but may reopen the questions to apply again', () {
      final session = SignedIn(sessionData(applications: [application(AppRole.trainee, ApplicationStatus.rejected)]));
      expect(go(session, Routes.splash), Routes.waiting);
      expect(go(session, Routes.onboarding), isNull);
    });

    test('only the application for the sign-up role counts', () {
      final session = SignedIn(sessionData(
        signupRole: AppRole.coach,
        applications: [application(AppRole.trainee, ApplicationStatus.pending)],
      ));
      expect(go(session, Routes.waiting), Routes.onboarding);
    });
  });

  group('approved', () {
    test('goes to the home of their role', () {
      expect(go(SignedIn(sessionData(roles: {AppRole.trainee})), Routes.waiting), '/trainee');
      expect(go(SignedIn(sessionData(roles: {AppRole.coach})), Routes.splash), '/coach');
      expect(go(SignedIn(sessionData(roles: {AppRole.admin})), Routes.login), '/admin');
    });

    test('can open the profile and their own sub-pages', () {
      final admin = SignedIn(sessionData(roles: {AppRole.admin}));
      expect(go(admin, Routes.profile), isNull);
      expect(go(admin, Routes.application('app-1')), isNull);
    });

    test('cannot open another role\'s home', () {
      expect(go(SignedIn(sessionData(roles: {AppRole.trainee})), '/admin'), '/trainee');
    });

    test('with several roles: the chosen one, else coach before admin', () {
      final both = SignedIn(sessionData(roles: {AppRole.admin, AppRole.coach}));
      expect(go(both, Routes.splash), '/coach');
      expect(go(both, Routes.splash, selected: AppRole.admin), '/admin');
      expect(go(both, Routes.splash, selected: AppRole.trainee), '/coach', reason: 'a role they do not have');
    });
  });
}
