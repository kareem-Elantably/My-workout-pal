import 'package:supabase_flutter/supabase_flutter.dart';

class TodaySummary {
  const TodaySummary({required this.hasPlan, required this.streak, this.workout});

  final bool hasPlan;
  final int streak;
  final NextWorkout? workout;
}

class NextWorkout {
  const NextWorkout({required this.dayNumber, required this.isPlannedRest, required this.loggedToday, this.dayName});

  final int dayNumber;
  final String? dayName;
  final bool isPlannedRest;
  final bool loggedToday;

  factory NextWorkout.fromJson(Map<String, dynamic> json) => NextWorkout(
        dayNumber: json['day_number'] as int,
        dayName: json['day_name'] as String?,
        isPlannedRest: json['is_planned_rest'] as bool,
        loggedToday: json['logged_today'] as bool,
      );
}

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

  Future<TodaySummary> today(String traineeId) async {
    final results = await Future.wait<dynamic>([
      _client.from('workout_plans').select('id').eq('trainee_id', traineeId).isFilter('archived_on', null).limit(1),
      _client.from('nutrition_plans').select('id').eq('trainee_id', traineeId).isFilter('archived_on', null).limit(1),
      _client.rpc('next_workout_day'),
      _client.rpc('current_streak'),
    ]);
    final next = (results[2] as List).cast<Map<String, dynamic>>();
    return TodaySummary(
      hasPlan: (results[0] as List).isNotEmpty || (results[1] as List).isNotEmpty,
      streak: results[3] as int? ?? 0,
      workout: next.isEmpty ? null : NextWorkout.fromJson(next.first),
    );
  }

  /// Active trainees, the ones who need attention first.
  Future<List<CoachTrainee>> coachDashboard() async {
    final rows = await _client.rpc('coach_dashboard') as List;
    return rows.cast<Map<String, dynamic>>().map(CoachTrainee.fromJson).toList();
  }
}
