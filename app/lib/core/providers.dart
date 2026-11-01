import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/admin_repository.dart';
import '../data/auth_repository.dart';
import '../data/home_repository.dart';
import '../data/onboarding_repository.dart';
import '../data/session_repository.dart';
import 'models.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Overridden in main() with the loaded instance.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

final authRepositoryProvider = Provider((ref) => AuthRepository(ref.watch(supabaseClientProvider)));
final sessionRepositoryProvider = Provider((ref) => SessionRepository(ref.watch(supabaseClientProvider)));
final onboardingRepositoryProvider = Provider((ref) => OnboardingRepository(ref.watch(supabaseClientProvider)));
final adminRepositoryProvider = Provider((ref) => AdminRepository(ref.watch(supabaseClientProvider)));
final homeRepositoryProvider = Provider((ref) => HomeRepository(ref.watch(supabaseClientProvider)));

sealed class AuthSession {
  const AuthSession();
}

class SignedOut extends AuthSession {
  const SignedOut();
}

class SignedIn extends AuthSession {
  const SignedIn(this.data);

  final SessionData data;
}

/// The signed-in user with their profile, roles and applications. Reloads
/// on sign-in/out; screens call [refresh] after changing any of them.
class SessionNotifier extends AsyncNotifier<AuthSession> {
  @override
  Future<AuthSession> build() async {
    final subscription = ref.watch(authRepositoryProvider).authChanges().listen((change) {
      switch (change.event) {
        case AuthChangeEvent.signedIn || AuthChangeEvent.signedOut || AuthChangeEvent.userUpdated:
          unawaited(refresh());
        default:
          break;
      }
    });
    ref.onDispose(subscription.cancel);
    return _load();
  }

  Future<AuthSession> _load() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return const SignedOut();
    return SignedIn(await ref.read(sessionRepositoryProvider).load(user));
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }
}

final sessionProvider = AsyncNotifierProvider<SessionNotifier, AuthSession>(SessionNotifier.new);

/// The role the app is used as, for people with several (admin + coach).
class ActiveRoleNotifier extends Notifier<AppRole?> {
  static const _key = 'active_role';

  @override
  AppRole? build() => AppRole.fromKey(ref.watch(sharedPreferencesProvider).getString(_key));

  void select(AppRole role) {
    ref.read(sharedPreferencesProvider).setString(_key, role.name);
    state = role;
  }
}

final activeRoleProvider = NotifierProvider<ActiveRoleNotifier, AppRole?>(ActiveRoleNotifier.new);

class LocaleNotifier extends Notifier<Locale> {
  static const _key = 'locale';

  @override
  Locale build() => Locale(ref.watch(sharedPreferencesProvider).getString(_key) ?? 'ar');

  Future<void> select(Locale locale) async {
    state = locale;
    await ref.read(sharedPreferencesProvider).setString(_key, locale.languageCode);
    final session = ref.read(sessionProvider).value;
    if (session is SignedIn) {
      await ref.read(sessionRepositoryProvider).updateLocale(session.data.userId, locale.languageCode);
    }
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
