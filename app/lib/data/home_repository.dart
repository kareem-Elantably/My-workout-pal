import 'package:supabase_flutter/supabase_flutter.dart';

class CoachTrainee {
  const CoachTrainee({
    required this.traineeId,
    required this.fullName,
    required this.scopes,
    required this.trainedToday,
    required this.mealsDoneToday,
    required this.mealsTotalToday,
    required this.missedDays7,
    required this.milestonesDue,
    required this.unreadMessages,
    required this.streak,
  });

  final String traineeId;
  final String fullName;
  final List<String> scopes;
  final bool trainedToday;
  final int mealsDoneToday;
  final int mealsTotalToday;
  final int missedDays7;
  final int milestonesDue;
  final int unreadMessages;
  final int streak;

  factory CoachTrainee.fromJson(Map<String, dynamic> json) => CoachTrainee(
        traineeId: json['trainee_id'] as String,
        fullName: json['full_name'] as String,
        scopes: (json['scopes'] as List).cast<String>(),
        trainedToday: json['trained_today'] as bool? ?? false,
        mealsDoneToday: json['meals_done_today'] as int? ?? 0,
        mealsTotalToday: json['meals_total_today'] as int? ?? 0,
        missedDays7: json['missed_days_7'] as int? ?? 0,
        milestonesDue: json['milestones_due'] as int? ?? 0,
        unreadMessages: json['unread_messages'] as int? ?? 0,
        streak: json['streak'] as int? ?? 0,
      );
}

class HomeRepository {
  HomeRepository(this._client);

  final SupabaseClient _client;

  /// Active trainees, the ones who need attention first.
  Future<List<CoachTrainee>> coachDashboard() async {
    final rows = await _client.rpc('coach_dashboard') as List;
    return rows.cast<Map<String, dynamic>>().map(CoachTrainee.fromJson).toList();
  }
}
