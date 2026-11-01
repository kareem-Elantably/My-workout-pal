import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models.dart';
import 'onboarding_repository.dart';

class PendingApplication {
  const PendingApplication({required this.application, required this.applicant});

  final Application application;
  final Profile applicant;
}

class CoachOption {
  const CoachOption({required this.id, required this.fullName});

  final String id;
  final String fullName;
}

class Assignment {
  const Assignment({required this.id, required this.scopeKey, required this.coachName});

  final String id;
  final String scopeKey;
  final String coachName;
}

class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  Future<List<PendingApplication>> pendingApplications() async {
    final rows = await _client
        .from('applications')
        .select('id, status, submitted_at, role:roles(key), applicant:profiles!applications_user_id_fkey(*)')
        .eq('status', 'pending')
        .order('submitted_at');
    return [
      for (final row in rows)
        PendingApplication(
          application: Application.fromJson(row),
          applicant: Profile.fromJson(row['applicant'] as Map<String, dynamic>),
        ),
    ];
  }

  Future<List<CoachOption>> coaches() async {
    final rows = await _client
        .from('user_roles')
        .select('role:roles!inner(key), coach:profiles!user_roles_user_id_fkey(id, full_name)')
        .eq('role.key', 'coach');
    final coaches = [
      for (final row in rows)
        CoachOption(
          id: (row['coach'] as Map<String, dynamic>)['id'] as String,
          fullName: (row['coach'] as Map<String, dynamic>)['full_name'] as String,
        ),
    ]..sort((a, b) => a.fullName.compareTo(b.fullName));
    return coaches;
  }

  Future<List<Assignment>> activeAssignments(String traineeId) async {
    final rows = await _client
        .from('coach_assignments')
        .select('id, scope:coaching_scopes(key), coach:profiles!coach_assignments_coach_id_fkey(full_name)')
        .eq('trainee_id', traineeId)
        .isFilter('ends_on', null);
    return [
      for (final row in rows)
        Assignment(
          id: row['id'] as String,
          scopeKey: (row['scope'] as Map<String, dynamic>)['key'] as String,
          coachName: (row['coach'] as Map<String, dynamic>)['full_name'] as String,
        ),
    ];
  }

  Future<void> assignCoach({required String traineeId, required String coachId, required String scopeKey}) async {
    final scope = await _client.from('coaching_scopes').select('id').eq('key', scopeKey).single();
    await _client.from('coach_assignments').insert({
      'trainee_id': traineeId,
      'coach_id': coachId,
      'scope_id': scope['id'],
    });
  }

  /// Approving grants the role and notifies the applicant (database trigger).
  Future<void> review(String applicationId, ApplicationStatus status) =>
      _client.from('applications').update({'status': status.name}).eq('id', applicationId);

  /// Short-lived link to view a private certificate file.
  Future<String> certificateUrl(Certificate certificate) =>
      _client.storage.from('certificates').createSignedUrl(certificate.filePath, 600);
}
