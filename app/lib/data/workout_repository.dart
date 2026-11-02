import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/plan_models.dart';

/// One point of an exercise's progress: the best set of a session.
class ProgressPoint {
  const ProgressPoint(this.date, this.value);

  final DateTime date;
  final double value;
}

class NextWorkout {
  const NextWorkout({required this.dayNumber, required this.isPlannedRest, required this.loggedToday, this.workoutDayId});

  final int dayNumber;
  final String? workoutDayId;
  final bool isPlannedRest;
  final bool loggedToday;

  factory NextWorkout.fromJson(Map<String, dynamic> json) => NextWorkout(
        dayNumber: json['day_number'] as int,
        workoutDayId: json['workout_day_id'] as String?,
        isPlannedRest: json['is_planned_rest'] as bool,
        loggedToday: json['logged_today'] as bool,
      );
}

class WorkoutRepository {
  WorkoutRepository(this._client);

  final SupabaseClient _client;

  /// The trainee's active workout plan with all versions (null if none).
  Future<WorkoutPlan?> activePlan(String traineeId) async {
    final row = await _client
        .from('workout_plans')
        .select(WorkoutPlan.select)
        .eq('trainee_id', traineeId)
        .isFilter('archived_on', null)
        .maybeSingle();
    return row == null ? null : WorkoutPlan.fromJson(row);
  }

  Future<WorkoutPlan> plan(String planId) async =>
      WorkoutPlan.fromJson(await _client.from('workout_plans').select(WorkoutPlan.select).eq('id', planId).single());

  /// The day the app suggests today (only for the signed-in trainee or their coach).
  Future<NextWorkout?> nextWorkout(String traineeId) async {
    final rows = await _client.rpc('next_workout_day', params: {'p_trainee': traineeId}) as List;
    return rows.isEmpty ? null : NextWorkout.fromJson(rows.first as Map<String, dynamic>);
  }

  Future<int> streak(String traineeId) async => await _client.rpc('current_streak', params: {'p_trainee': traineeId}) as int;

  Future<WorkoutSession?> sessionOn(String traineeId, DateTime day) async {
    final row = await _client
        .from('workout_sessions')
        .select('*, set_logs(*)')
        .eq('trainee_id', traineeId)
        .eq('session_date', isoDate(day))
        .maybeSingle();
    return row == null ? null : WorkoutSession.fromJson(row);
  }

  Future<List<WorkoutSession>> recentSessions(String traineeId, {int limit = 30}) async {
    final rows = await _client
        .from('workout_sessions')
        .select('*, set_logs(*)')
        .eq('trainee_id', traineeId)
        .order('session_date', ascending: false)
        .limit(limit);
    return rows.map(WorkoutSession.fromJson).toList();
  }

  Future<WorkoutSession> startSession(String traineeId, String workoutDayId, DateTime day) async {
    final row = await _client
        .from('workout_sessions')
        .insert({'trainee_id': traineeId, 'workout_day_id': workoutDayId, 'session_date': isoDate(day)})
        .select('*, set_logs(*)')
        .single();
    return WorkoutSession.fromJson(row);
  }

  /// Removes a session and its sets (e.g. to log a different day that date).
  Future<void> deleteSession(String sessionId) => _client.from('workout_sessions').delete().eq('id', sessionId);

  Future<SetLog> saveSet({
    required String sessionId,
    required DayExercise dayExercise,
    required int setNumber,
    int? reps,
    num? weightKg,
    int? durationSeconds,
    num? distanceM,
  }) async {
    final row = await _client
        .from('set_logs')
        .upsert({
          'session_id': sessionId,
          'day_exercise_id': dayExercise.id,
          'exercise_id': dayExercise.exercise.id,
          'set_number': setNumber,
          'reps': reps,
          'weight_kg': weightKg,
          'duration_seconds': durationSeconds,
          'distance_m': distanceM,
          // filled from the session by a database trigger
          'trainee_id': _client.auth.currentUser!.id,
          'session_date': isoDate(DateTime.now()),
        }, onConflict: 'session_id,day_exercise_id,set_number')
        .select()
        .single();
    return SetLog.fromJson(row);
  }

  Future<void> deleteSet(String setId) => _client.from('set_logs').delete().eq('id', setId);

  Future<void> finishSession(String sessionId, {String? note}) => _client
      .from('workout_sessions')
      .update({'completed_at': DateTime.now().toUtc().toIso8601String(), 'note': note}).eq('id', sessionId);

  /// Values from the last time this exercise was done, per set number.
  Future<Map<int, SetLog>> lastValues(String traineeId, String exerciseId) async {
    final rows = await _client.rpc('last_weights', params: {'p_trainee': traineeId, 'p_exercise': exerciseId}) as List;
    return {
      for (final row in rows.cast<Map<String, dynamic>>())
        row['set_number'] as int: SetLog.fromJson({...row, 'id': '', 'day_exercise_id': ''}),
    };
  }

  /// Best set per session: heaviest weight, or most reps / longest time.
  Future<List<ProgressPoint>> exerciseProgress(String traineeId, Exercise exercise) async {
    final rows = await _client
        .from('set_logs')
        .select('session_date, reps, weight_kg, duration_seconds, distance_m')
        .eq('trainee_id', traineeId)
        .eq('exercise_id', exercise.id)
        .order('session_date');
    final best = <String, double>{};
    for (final row in rows) {
      final value = switch (exercise.tracking) {
        Tracking.weightReps => (row['weight_kg'] as num?)?.toDouble(),
        Tracking.reps => (row['reps'] as num?)?.toDouble(),
        Tracking.duration => (row['duration_seconds'] as num?)?.toDouble(),
        Tracking.distanceDuration => (row['distance_m'] as num?)?.toDouble(),
      };
      if (value == null) continue;
      final date = row['session_date'] as String;
      if (value > (best[date] ?? double.negativeInfinity)) best[date] = value;
    }
    return [for (final e in best.entries) ProgressPoint(DateTime.parse(e.key), e.value)];
  }

  /// Exercises the trainee has logged, for the progress picker.
  Future<List<Exercise>> loggedExercises(String traineeId) async {
    final rows = await _client
        .from('set_logs')
        .select('exercise:exercises(id, name_en, name_ar, tracking, category, equipment)')
        .eq('trainee_id', traineeId)
        .limit(1000);
    final byId = <String, Exercise>{};
    for (final row in rows) {
      final exercise = Exercise.fromJson(row['exercise'] as Map<String, dynamic>);
      byId[exercise.id] = exercise;
    }
    return byId.values.toList()..sort((a, b) => a.nameEn.compareTo(b.nameEn));
  }
}
