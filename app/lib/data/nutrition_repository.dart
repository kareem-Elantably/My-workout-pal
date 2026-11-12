import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/plan_models.dart';

class NutritionRepository {
  NutritionRepository(this._client);

  final SupabaseClient _client;

  Future<NutritionPlan?> activePlan(String traineeId) async {
    final row = await _client
        .from('nutrition_plans')
        .select(NutritionPlan.select)
        .eq('trainee_id', traineeId)
        .isFilter('archived_on', null)
        .maybeSingle();
    return row == null ? null : NutritionPlan.fromJson(row);
  }

  Future<NutritionPlan> plan(String planId) async =>
      NutritionPlan.fromJson(await _client.from('nutrition_plans').select(NutritionPlan.select).eq('id', planId).single());

  Future<List<MealLog>> logsOn(String traineeId, DateTime day) async {
    final rows = await _client
        .from('meal_logs')
        .select('id, meal_id, option_id, change_note')
        .eq('trainee_id', traineeId)
        .eq('log_date', isoDate(day));
    return rows.map(MealLog.fromJson).toList();
  }

  /// Millilitres of water drunk on a day (0 if nothing logged).
  Future<int> waterOn(String traineeId, DateTime day) async {
    final row = await _client
        .from('water_logs')
        .select('ml')
        .eq('trainee_id', traineeId)
        .eq('log_date', isoDate(day))
        .maybeSingle();
    return row?['ml'] as int? ?? 0;
  }

  /// The day's total (the app adds a glass at a time and saves the sum).
  Future<void> setWater(String traineeId, DateTime day, int ml) => _client
      .from('water_logs')
      .upsert({'trainee_id': traineeId, 'log_date': isoDate(day), 'ml': ml}, onConflict: 'trainee_id,log_date');

  /// Water per day from [from] on, for the coach.
  Future<Map<DateTime, int>> waterSince(String traineeId, DateTime from) async {
    final rows = await _client
        .from('water_logs')
        .select('log_date, ml')
        .eq('trainee_id', traineeId)
        .gte('log_date', isoDate(from));
    return {for (final r in rows) DateTime.parse(r['log_date'] as String): r['ml'] as int};
  }

  /// Marks a meal eaten (or changes which option / the note).
  Future<void> logMeal({
    required String traineeId,
    required String mealId,
    required DateTime day,
    String? optionId,
    String? changeNote,
  }) =>
      _client.from('meal_logs').upsert({
        'trainee_id': traineeId,
        'meal_id': mealId,
        'option_id': optionId,
        'log_date': isoDate(day),
        'change_note': changeNote == null || changeNote.trim().isEmpty ? null : changeNote.trim(),
      }, onConflict: 'trainee_id,meal_id,log_date');

  Future<void> unlogMeal(String logId) => _client.from('meal_logs').delete().eq('id', logId);

  /// All of the day's meals at once ("all meals done"); keeps existing choices.
  Future<void> logAll({required String traineeId, required List<Meal> meals, required List<MealLog> existing, required DateTime day}) async {
    final done = {for (final log in existing) log.mealId};
    final rows = [
      for (final meal in meals)
        if (!done.contains(meal.id))
          {
            'trainee_id': traineeId,
            'meal_id': meal.id,
            'option_id': meal.options.length == 1 ? meal.options.first.id : null,
            'log_date': isoDate(day),
          },
    ];
    if (rows.isNotEmpty) await _client.from('meal_logs').insert(rows);
  }
}
