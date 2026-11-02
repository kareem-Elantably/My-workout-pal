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

class Person {
  const Person({required this.profile, required this.roles});

  final Profile profile;
  final Set<AppRole> roles;
}

class SubscriptionRow {
  const SubscriptionRow({
    required this.id,
    required this.amount,
    required this.startsOn,
    required this.endsOn,
    required this.daysLeft,
    required this.status,
    this.traineeId,
    this.coachId,
    this.traineeName,
    this.coachName,
    this.note,
  });

  final String id;
  final String? traineeId;
  final String? coachId;
  final String? traineeName;
  final String? coachName;
  final num amount;
  final DateTime startsOn;
  final DateTime endsOn;
  final int daysLeft;

  /// upcoming, active, ending_soon or ended
  final String status;
  final String? note;
}

/// Earnings of one coach (or one trainee for a coach) in a date range.
class EarningsLine {
  const EarningsLine({required this.id, required this.name, required this.amount});

  final String? id;
  final String name;
  final num amount;
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

  // --- people ---------------------------------------------------------------

  Future<List<Person>> people() async {
    final rows = await _client.from('profiles').select('*, user_roles!user_roles_user_id_fkey(role:roles(key))').order('full_name');
    return [
      for (final row in rows)
        Person(
          profile: Profile.fromJson(row),
          roles: {
            for (final r in (row['user_roles'] as List? ?? const []))
              ?AppRole.fromKey(((r as Map<String, dynamic>)['role'] as Map<String, dynamic>?)?['key'] as String?),
          },
        ),
    ];
  }

  /// Ends an assignment today; the history stays.
  Future<void> endAssignment(String assignmentId) => _client
      .from('coach_assignments')
      .update({'ends_on': DateTime.now().toIso8601String().substring(0, 10)})
      .eq('id', assignmentId);

  // --- subscriptions --------------------------------------------------------

  Future<List<SubscriptionRow>> subscriptions({String? traineeId}) async {
    var query = _client.from('subscription_status').select();
    if (traineeId != null) query = query.eq('trainee_id', traineeId);
    final rows = await query.order('ends_on');
    final ids = {for (final r in rows) ...[r['trainee_id'], r['coach_id']]}.whereType<String>().toList();
    final names = ids.isEmpty
        ? const <String, String>{}
        : {
            for (final p in await _client.from('profiles').select('id, full_name').inFilter('id', ids))
              p['id'] as String: p['full_name'] as String,
          };
    final notes = rows.isEmpty
        ? const <String, String?>{}
        : {
            for (final s in await _client.from('subscriptions').select('id, note').inFilter('id', [for (final r in rows) r['id']]))
              s['id'] as String: s['note'] as String?,
          };
    return [
      for (final r in rows)
        SubscriptionRow(
          id: r['id'] as String,
          traineeId: r['trainee_id'] as String?,
          coachId: r['coach_id'] as String?,
          traineeName: names[r['trainee_id']],
          coachName: names[r['coach_id']],
          amount: r['amount_egp'] as num,
          startsOn: DateTime.parse(r['starts_on'] as String),
          endsOn: DateTime.parse(r['ends_on'] as String),
          daysLeft: r['days_left'] as int,
          status: r['status'] as String,
          note: notes[r['id']],
        ),
    ];
  }

  Future<void> saveSubscription({
    String? id,
    required String traineeId,
    required String coachId,
    required num amount,
    required DateTime startsOn,
    required DateTime endsOn,
    String? note,
  }) {
    final row = {
      'trainee_id': traineeId,
      'coach_id': coachId,
      'amount_egp': amount,
      'starts_on': startsOn.toIso8601String().substring(0, 10),
      'ends_on': endsOn.toIso8601String().substring(0, 10),
      'note': note == null || note.trim().isEmpty ? null : note.trim(),
    };
    return id == null ? _client.from('subscriptions').insert(row) : _client.from('subscriptions').update(row).eq('id', id);
  }

  Future<void> deleteSubscription(String id) => _client.from('subscriptions').delete().eq('id', id);

  /// Earnings in [from, to], by coach (admin) or by trainee (a coach's own).
  Future<List<EarningsLine>> earnings(DateTime from, DateTime to, {required bool byTrainee, String? coachId}) async {
    final rows = await _client.rpc('coach_earnings', params: {
      'p_from': from.toIso8601String().substring(0, 10),
      'p_to': to.toIso8601String().substring(0, 10),
      'p_coach': coachId,
    }) as List;
    final key = byTrainee ? 'trainee_id' : 'coach_id';
    final totals = <String?, num>{};
    for (final r in rows.cast<Map<String, dynamic>>()) {
      totals.update(r[key] as String?, (sum) => sum + (r['amount_egp'] as num), ifAbsent: () => r['amount_egp'] as num);
    }
    final ids = totals.keys.whereType<String>().toList();
    final names = ids.isEmpty
        ? const <String, String>{}
        : {
            for (final p in await _client.from('profiles').select('id, full_name').inFilter('id', ids))
              p['id'] as String: p['full_name'] as String,
          };
    return [
      for (final e in totals.entries) EarningsLine(id: e.key, name: names[e.key] ?? '—', amount: e.value),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
  }

  /// Active trainees per coach.
  Future<Map<String, int>> coachLoad() async {
    final rows = await _client.from('coach_load').select('coach_id, active_trainees');
    return {for (final r in rows) r['coach_id'] as String: r['active_trainees'] as int};
  }

  /// Short-lived link to view a private certificate file.
  Future<String> certificateUrl(Certificate certificate) =>
      _client.storage.from('certificates').createSignedUrl(certificate.filePath, 600);
}
