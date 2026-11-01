import 'package:fitness_app/core/models.dart';
import 'package:fitness_app/core/providers.dart';
import 'package:fitness_app/data/home_repository.dart';
import 'package:fitness_app/data/onboarding_repository.dart';
import 'package:fitness_app/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mocktail/mocktail.dart';

class MockOnboardingRepository extends Mock implements OnboardingRepository {}

class MockHomeRepository extends Mock implements HomeRepository {}

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
