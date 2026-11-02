import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/plan_models.dart';

/// Coach-side plan building. Permissions (scope, ownership) and frozen
/// versions are enforced by the database; this just shapes the calls.
class PlanEditorRepository {
  PlanEditorRepository(this._client);

  final SupabaseClient _client;

  String get _me => _client.auth.currentUser!.id;

  // --- workout ------------------------------------------------------------

  /// A new plan (for a trainee, replacing their active one, or a template)
  /// with an empty first version.
  Future<String> createWorkoutPlan({String? traineeId, required String name, required int cycleLength, String? copiedFrom}) async {
    if (traineeId != null) await _archiveActive('workout_plans', traineeId);
    final plan = await _client
        .from('workout_plans')
        .insert({'trainee_id': traineeId, 'owner_coach_id': _me, 'name': name.trim(), 'copied_from_id': copiedFrom})
        .select('id')
        .single();
    await _client.from('workout_plan_versions').insert({
      'plan_id': plan['id'],
      'version_no': 0,
      'cycle_length': cycleLength,
      'effective_from': isoDate(DateTime.now()),
    });
    return plan['id'] as String;
  }

  Future<void> _archiveActive(String table, String traineeId) => _client
      .from(table)
      .update({'archived_on': isoDate(DateTime.now())})
      .eq('trainee_id', traineeId)
      .isFilter('archived_on', null);

  Future<void> renameWorkoutPlan(String planId, String name) =>
      _client.from('workout_plans').update({'name': name.trim()}).eq('id', planId);

  Future<void> deleteWorkoutPlan(String planId) => _client.from('workout_plans').delete().eq('id', planId);

  /// True when the trainee has logged against this version: edits then go
  /// into a new version.
  Future<bool> workoutVersionFrozen(WorkoutVersion version) async {
    if (version.days.isEmpty) return false;
    final rows = await _client
        .from('workout_sessions')
        .select('id')
        .inFilter('workout_day_id', [for (final d in version.days) d.id])
        .limit(1);
    return rows.isNotEmpty;
  }

  /// Copies a version into a plan (new version, apply/save a template).
  Future<String> copyWorkoutVersion(String fromVersionId, String toPlanId, {DateTime? effectiveFrom}) async =>
      await _client.rpc('copy_workout_version', params: {
        'p_from': fromVersionId,
        'p_to_plan': toPlanId,
        'p_effective_from': isoDate(effectiveFrom ?? DateTime.now()),
      }) as String;

  /// An empty new version (e.g. for an Excel upload into an existing plan).
  Future<String> addEmptyWorkoutVersion(String planId, int cycleLength, {String? sourceFile}) async => (await _client
      .from('workout_plan_versions')
      .insert({
        'plan_id': planId,
        'version_no': 0,
        'cycle_length': cycleLength,
        'effective_from': isoDate(DateTime.now()),
        'source_file': sourceFile,
      })
      .select('id')
      .single())['id'] as String;

  Future<void> setCycleLength(String versionId, int length) =>
      _client.from('workout_plan_versions').update({'cycle_length': length}).eq('id', versionId);

  Future<String> addDay(String versionId, int dayNumber, String name) async => (await _client
      .from('workout_days')
      .insert({'version_id': versionId, 'day_number': dayNumber, 'name': name.trim()})
      .select('id')
      .single())['id'] as String;

  Future<void> renameDay(String dayId, String name) => _client.from('workout_days').update({'name': name.trim()}).eq('id', dayId);

  Future<void> deleteDay(String dayId) => _client.from('workout_days').delete().eq('id', dayId);

  Future<void> saveDayExercise(String dayId, DayExercise exercise, {String? id}) => id == null
      ? _client.from('workout_day_exercises').insert({...exercise.toRow(), 'day_id': dayId})
      : _client.from('workout_day_exercises').update(exercise.toRow()).eq('id', id);

  Future<void> deleteDayExercise(String id) => _client.from('workout_day_exercises').delete().eq('id', id);

  Future<void> reorderDayExercises(List<DayExercise> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].sortOrder != i + 1) {
        await _client.from('workout_day_exercises').update({'sort_order': i + 1}).eq('id', ordered[i].id);
      }
    }
  }

  Future<List<WorkoutPlan>> workoutTemplates() async {
    final rows = await _client
        .from('workout_plans')
        .select(WorkoutPlan.select)
        .isFilter('trainee_id', null)
        .eq('owner_coach_id', _me)
        .isFilter('archived_on', null)
        .order('name');
    return rows.map(WorkoutPlan.fromJson).toList();
  }

  /// "Apply to trainee": a copy the coach then edits; the template stays as is.
  Future<String> applyWorkoutTemplate(WorkoutPlan template, String traineeId) async {
    await _archiveActive('workout_plans', traineeId);
    final plan = await _client
        .from('workout_plans')
        .insert({'trainee_id': traineeId, 'owner_coach_id': _me, 'name': template.name, 'copied_from_id': template.id})
        .select('id')
        .single();
    await copyWorkoutVersion(template.latest!.id, plan['id'] as String);
    return plan['id'] as String;
  }

  Future<String> saveWorkoutAsTemplate(WorkoutPlan plan, WorkoutVersion version, String name) async {
    final template = await _client
        .from('workout_plans')
        .insert({'trainee_id': null, 'owner_coach_id': _me, 'name': name.trim(), 'copied_from_id': plan.id})
        .select('id')
        .single();
    await copyWorkoutVersion(version.id, template['id'] as String);
    return template['id'] as String;
  }

  // --- nutrition ----------------------------------------------------------

  Future<String> createNutritionPlan({String? traineeId, required String name}) async {
    if (traineeId != null) await _archiveActive('nutrition_plans', traineeId);
    final plan = await _client
        .from('nutrition_plans')
        .insert({'trainee_id': traineeId, 'owner_coach_id': _me, 'name': name.trim()})
        .select('id')
        .single();
    await _client.from('nutrition_plan_versions').insert({
      'plan_id': plan['id'],
      'version_no': 0,
      'effective_from': isoDate(DateTime.now()),
    });
    return plan['id'] as String;
  }

  Future<void> updateNutritionPlan(String planId, {String? name, bool? showMacros}) => _client.from('nutrition_plans').update({
        'name': ?name?.trim(),
        'show_macros': ?showMacros,
      }).eq('id', planId);

  Future<void> deleteNutritionPlan(String planId) => _client.from('nutrition_plans').delete().eq('id', planId);

  Future<bool> nutritionVersionFrozen(NutritionVersion version) async {
    if (version.meals.isEmpty) return false;
    final rows = await _client.from('meal_logs').select('id').inFilter('meal_id', [for (final m in version.meals) m.id]).limit(1);
    return rows.isNotEmpty;
  }

  Future<String> copyNutritionVersion(String fromVersionId, String toPlanId, {DateTime? effectiveFrom}) async =>
      await _client.rpc('copy_nutrition_version', params: {
        'p_from': fromVersionId,
        'p_to_plan': toPlanId,
        'p_effective_from': isoDate(effectiveFrom ?? DateTime.now()),
      }) as String;

  Future<void> saveMeal(String versionId, {String? id, required String name, String? time, required int sortOrder, required bool countsForStreak}) {
    final row = {'name': name.trim(), 'time_hint': time, 'sort_order': sortOrder, 'counts_for_streak': countsForStreak};
    return id == null
        ? _client.from('meals').insert({...row, 'version_id': versionId})
        : _client.from('meals').update(row).eq('id', id);
  }

  Future<void> deleteMeal(String id) => _client.from('meals').delete().eq('id', id);

  Future<void> saveOption(String mealId, {String? id, required String label, required int sortOrder}) => id == null
      ? _client.from('meal_options').insert({'meal_id': mealId, 'label': label.trim(), 'sort_order': sortOrder})
      : _client.from('meal_options').update({'label': label.trim()}).eq('id', id);

  Future<void> deleteOption(String id) => _client.from('meal_options').delete().eq('id', id);

  /// Quantity in grams (no unit) or in one of the food's units.
  Future<void> saveItem(String optionId, {String? id, required String foodId, required num quantity, String? unitId, String? note}) {
    final row = {
      'food_id': foodId,
      'quantity': quantity,
      'unit_id': unitId,
      'note': note == null || note.trim().isEmpty ? null : note.trim(),
    };
    return id == null
        ? _client.from('meal_option_items').insert({...row, 'option_id': optionId})
        : _client.from('meal_option_items').update(row).eq('id', id);
  }

  Future<void> deleteItem(String id) => _client.from('meal_option_items').delete().eq('id', id);

  Future<List<NutritionPlan>> nutritionTemplates() async {
    final rows = await _client
        .from('nutrition_plans')
        .select(NutritionPlan.select)
        .isFilter('trainee_id', null)
        .eq('owner_coach_id', _me)
        .isFilter('archived_on', null)
        .order('name');
    return rows.map(NutritionPlan.fromJson).toList();
  }

  Future<String> applyNutritionTemplate(NutritionPlan template, String traineeId) async {
    await _archiveActive('nutrition_plans', traineeId);
    final plan = await _client
        .from('nutrition_plans')
        .insert({
          'trainee_id': traineeId,
          'owner_coach_id': _me,
          'name': template.name,
          'show_macros': template.showMacros,
          'copied_from_id': template.id,
        })
        .select('id')
        .single();
    await copyNutritionVersion(template.latest!.id, plan['id'] as String);
    return plan['id'] as String;
  }

  Future<String> saveNutritionAsTemplate(NutritionPlan plan, NutritionVersion version, String name) async {
    final template = await _client
        .from('nutrition_plans')
        .insert({'trainee_id': null, 'owner_coach_id': _me, 'name': name.trim(), 'show_macros': plan.showMacros, 'copied_from_id': plan.id})
        .select('id')
        .single();
    await copyNutritionVersion(version.id, template['id'] as String);
    return template['id'] as String;
  }
}
