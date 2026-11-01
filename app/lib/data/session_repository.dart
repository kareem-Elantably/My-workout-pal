import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models.dart';

class SessionRepository {
  SessionRepository(this._client);

  final SupabaseClient _client;

  Future<SessionData> load(User user) async {
    final results = await Future.wait<dynamic>([
      _client.from('profiles').select().eq('id', user.id).maybeSingle(),
      _client.from('user_roles').select('role:roles(key)').eq('user_id', user.id),
      _client
          .from('applications')
          .select('id, status, submitted_at, role:roles(key)')
          .eq('user_id', user.id)
          .order('submitted_at', ascending: false),
    ]);
    final profile = results[0] as Map<String, dynamic>?;
    final roles = (results[1] as List)
        .map((row) => AppRole.fromKey((row['role'] as Map<String, dynamic>?)?['key'] as String?))
        .whereType<AppRole>()
        .toSet();
    final applications = (results[2] as List).cast<Map<String, dynamic>>().map(Application.fromJson).toList();
    final metadata = user.userMetadata ?? const <String, dynamic>{};

    return SessionData(
      userId: user.id,
      email: user.email,
      profile: profile == null ? null : Profile.fromJson(profile),
      roles: roles,
      applications: applications,
      signupRole: AppRole.fromKey(metadata['signup_role'] as String?) ?? AppRole.trainee,
      signupMetadata: metadata,
    );
  }

  Future<void> updateLocale(String userId, String locale) =>
      _client.from('profiles').update({'locale': locale}).eq('id', userId);
}
