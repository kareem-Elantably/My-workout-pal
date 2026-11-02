import 'package:flutter/widgets.dart';

import 'models.dart';

String isoDate(DateTime day) => day.toIso8601String().substring(0, 10);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 72.0 -> "72", 72.5 -> "72.5".
String formatNum(num? n, {int decimals = 1}) {
  if (n == null) return '';
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toStringAsFixed(decimals).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// How an exercise is logged (see tracking_t in the database).
enum Tracking {
  weightReps,
  reps,
  duration,
  distanceDuration;

  static Tracking fromKey(String? key) => switch (key) {
        'reps' => Tracking.reps,
        'duration' => Tracking.duration,
        'distance_duration' => Tracking.distanceDuration,
        _ => Tracking.weightReps,
      };

  String get key => switch (this) {
        Tracking.weightReps => 'weight_reps',
        Tracking.reps => 'reps',
        Tracking.duration => 'duration',
        Tracking.distanceDuration => 'distance_duration',
      };

  bool get usesReps => this == Tracking.weightReps || this == Tracking.reps;
  bool get usesWeight => this == Tracking.weightReps;
  bool get usesDuration => this == Tracking.duration || this == Tracking.distanceDuration;
  bool get usesDistance => this == Tracking.distanceDuration;
}

class Exercise {
  const Exercise({required this.id, required this.nameEn, this.nameAr, required this.tracking, this.category, this.equipment});

  final String id;
  final String nameEn;
  final String? nameAr;
  final Tracking tracking;
  final String? category;
  final String? equipment;

  String name(BuildContext context) => nameAr == null ? nameEn : localized(context, nameEn, nameAr!);

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
        id: json['id'] as String,
        nameEn: json['name_en'] as String,
        nameAr: json['name_ar'] as String?,
        tracking: Tracking.fromKey(json['tracking'] as String?),
        category: json['category'] as String?,
        equipment: json['equipment'] as String?,
      );
}

class DayExercise {
  const DayExercise({
    required this.id,
    required this.exercise,
    required this.sortOrder,
    required this.sets,
    this.repsMin,
    this.repsMax,
    this.durationSeconds,
    this.distanceM,
    this.restSeconds,
    this.tempo,
    this.supersetGroup,
    this.videoUrl1,
    this.videoUrl2,
    this.coachNotes,
  });

  final String id;
  final Exercise exercise;
  final int sortOrder;
  final int sets;
  final int? repsMin;
  final int? repsMax;
  final int? durationSeconds;
  final num? distanceM;
  final int? restSeconds;
  final String? tempo;
  final String? supersetGroup;
  final String? videoUrl1;
  final String? videoUrl2;
  final String? coachNotes;

  /// "4 × 8-10", "3 × 45 s", "1 × 2 km · 15 min".
  String target() {
    final parts = <String>[];
    if (repsMin != null) parts.add(repsMax == null ? '$repsMin' : '$repsMin-$repsMax');
    if (distanceM != null) parts.add(distanceM! >= 1000 ? '${formatNum(distanceM! / 1000)} km' : '${formatNum(distanceM)} m');
    if (durationSeconds != null) {
      parts.add(durationSeconds! >= 60 && durationSeconds! % 60 == 0 ? '${durationSeconds! ~/ 60} min' : '$durationSeconds s');
    }
    return '$sets × ${parts.join(' · ')}';
  }

  factory DayExercise.fromJson(Map<String, dynamic> json) => DayExercise(
        id: json['id'] as String,
        exercise: Exercise.fromJson(json['exercise'] as Map<String, dynamic>),
        sortOrder: json['sort_order'] as int,
        sets: json['sets'] as int,
        repsMin: json['reps_min'] as int?,
        repsMax: json['reps_max'] as int?,
        durationSeconds: json['duration_seconds'] as int?,
        distanceM: json['distance_m'] as num?,
        restSeconds: json['rest_seconds'] as int?,
        tempo: json['tempo'] as String?,
        supersetGroup: json['superset_group'] as String?,
        videoUrl1: json['video_url_1'] as String?,
        videoUrl2: json['video_url_2'] as String?,
        coachNotes: json['coach_notes'] as String?,
      );

  Map<String, dynamic> toRow() => {
        'exercise_id': exercise.id,
        'sort_order': sortOrder,
        'sets': sets,
        'reps_min': repsMin,
        'reps_max': repsMax,
        'duration_seconds': durationSeconds,
        'distance_m': distanceM,
        'rest_seconds': restSeconds,
        'tempo': _blankToNull(tempo),
        'superset_group': _blankToNull(supersetGroup),
        'video_url_1': _blankToNull(videoUrl1),
        'video_url_2': _blankToNull(videoUrl2),
        'coach_notes': _blankToNull(coachNotes),
      };
}

String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

class WorkoutDay {
  const WorkoutDay({required this.id, required this.dayNumber, required this.name, required this.exercises});

  final String id;
  final int dayNumber;
  final String name;
  final List<DayExercise> exercises;

  factory WorkoutDay.fromJson(Map<String, dynamic> json) => WorkoutDay(
        id: json['id'] as String,
        dayNumber: json['day_number'] as int,
        name: json['name'] as String,
        exercises: ((json['workout_day_exercises'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(DayExercise.fromJson)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
      );
}

class WorkoutVersion {
  const WorkoutVersion({
    required this.id,
    required this.versionNo,
    required this.cycleLength,
    required this.effectiveFrom,
    required this.days,
  });

  final String id;
  final int versionNo;
  final int cycleLength;
  final DateTime effectiveFrom;
  final List<WorkoutDay> days;

  WorkoutDay? dayByNumber(int n) => days.where((d) => d.dayNumber == n).firstOrNull;

  factory WorkoutVersion.fromJson(Map<String, dynamic> json) => WorkoutVersion(
        id: json['id'] as String,
        versionNo: json['version_no'] as int,
        cycleLength: json['cycle_length'] as int,
        effectiveFrom: DateTime.parse(json['effective_from'] as String),
        days: ((json['workout_days'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(WorkoutDay.fromJson)
            .toList()
          ..sort((a, b) => a.dayNumber.compareTo(b.dayNumber)),
      );
}

/// Versions newest first; picks the one in force on a day.
mixin _Versioned<V> {
  List<V> get versions;
  DateTime effectiveFromOf(V version);

  V? versionOn(DateTime day) => versions.where((v) => !effectiveFromOf(v).isAfter(dateOnly(day))).firstOrNull;

  V? get latest => versions.firstOrNull;
}

class WorkoutPlan with _Versioned<WorkoutVersion> {
  WorkoutPlan({required this.id, required this.name, this.traineeId, required this.versions});

  final String id;
  final String name;
  final String? traineeId;
  @override
  final List<WorkoutVersion> versions;

  @override
  DateTime effectiveFromOf(WorkoutVersion version) => version.effectiveFrom;

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) => WorkoutPlan(
        id: json['id'] as String,
        name: json['name'] as String,
        traineeId: json['trainee_id'] as String?,
        versions: ((json['workout_plan_versions'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(WorkoutVersion.fromJson)
            .toList()
          ..sort((a, b) {
            final byDate = b.effectiveFrom.compareTo(a.effectiveFrom);
            return byDate != 0 ? byDate : b.versionNo.compareTo(a.versionNo);
          }),
      );

  static const select = 'id, name, trainee_id, workout_plan_versions(id, version_no, cycle_length, effective_from, '
      'workout_days(id, day_number, name, workout_day_exercises(*, exercise:exercises(id, name_en, name_ar, tracking, category, equipment))))';
}

class SetLog {
  const SetLog({
    required this.id,
    required this.dayExerciseId,
    required this.setNumber,
    this.reps,
    this.weightKg,
    this.durationSeconds,
    this.distanceM,
  });

  final String id;
  final String dayExerciseId;
  final int setNumber;
  final int? reps;
  final num? weightKg;
  final int? durationSeconds;
  final num? distanceM;

  factory SetLog.fromJson(Map<String, dynamic> json) => SetLog(
        id: json['id'] as String,
        dayExerciseId: json['day_exercise_id'] as String,
        setNumber: json['set_number'] as int,
        reps: json['reps'] as int?,
        weightKg: json['weight_kg'] as num?,
        durationSeconds: json['duration_seconds'] as int?,
        distanceM: json['distance_m'] as num?,
      );
}

class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.workoutDayId,
    required this.date,
    this.completedAt,
    this.note,
    this.sets = const [],
  });

  final String id;
  final String workoutDayId;
  final DateTime date;
  final DateTime? completedAt;
  final String? note;
  final List<SetLog> sets;

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
        id: json['id'] as String,
        workoutDayId: json['workout_day_id'] as String,
        date: DateTime.parse(json['session_date'] as String),
        completedAt: json['completed_at'] == null ? null : DateTime.parse(json['completed_at'] as String),
        note: json['note'] as String?,
        sets: ((json['set_logs'] as List?) ?? const []).cast<Map<String, dynamic>>().map(SetLog.fromJson).toList(),
      );
}

// ---------------------------------------------------------------------------
// Nutrition
// ---------------------------------------------------------------------------

class Macros {
  const Macros({this.kcal = 0, this.protein = 0, this.carbs = 0, this.fat = 0});

  final double kcal;
  final double protein;
  final double carbs;
  final double fat;

  Macros operator +(Macros o) =>
      Macros(kcal: kcal + o.kcal, protein: protein + o.protein, carbs: carbs + o.carbs, fat: fat + o.fat);
}

class FoodUnit {
  const FoodUnit({required this.id, required this.nameEn, required this.nameAr, required this.grams});

  final String id;
  final String nameEn;
  final String nameAr;
  final num grams;

  String name(BuildContext context) => localized(context, nameEn, nameAr);

  factory FoodUnit.fromJson(Map<String, dynamic> json) => FoodUnit(
        id: json['id'] as String,
        nameEn: json['name_en'] as String,
        nameAr: json['name_ar'] as String,
        grams: json['grams'] as num,
      );
}

class Food {
  const Food({
    required this.id,
    required this.nameEn,
    this.nameAr,
    required this.source,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.state,
    this.cookedYield,
    this.barcode,
    this.createdBy,
    this.units = const [],
  });

  final String id;
  final String nameEn;
  final String? nameAr;
  final String source;
  final num kcal;
  final num protein;
  final num carbs;
  final num fat;
  final String? state;

  /// Cooked weight / raw weight; null when there's no raw/cooked toggle.
  final num? cookedYield;
  final String? barcode;
  final String? createdBy;
  final List<FoodUnit> units;

  String name(BuildContext context) => nameAr == null ? nameEn : localized(context, nameEn, nameAr!);

  Macros forGrams(num grams) => Macros(
        kcal: kcal * grams / 100,
        protein: protein * grams / 100,
        carbs: carbs * grams / 100,
        fat: fat * grams / 100,
      );

  factory Food.fromJson(Map<String, dynamic> json) => Food(
        id: json['id'] as String,
        nameEn: json['name_en'] as String,
        nameAr: json['name_ar'] as String?,
        source: json['source'] as String,
        kcal: json['kcal'] as num,
        protein: json['protein_g'] as num,
        carbs: json['carbs_g'] as num,
        fat: json['fat_g'] as num,
        state: json['state'] as String?,
        cookedYield: json['cooked_yield'] as num?,
        barcode: json['barcode'] as String?,
        createdBy: json['created_by'] as String?,
        units: ((json['food_units'] as List?) ?? const []).cast<Map<String, dynamic>>().map(FoodUnit.fromJson).toList(),
      );
}

class MealItem {
  const MealItem({required this.id, required this.food, required this.quantity, required this.grams, this.unit, this.note});

  final String id;
  final Food food;
  final num quantity;
  final num grams;
  final FoodUnit? unit;
  final String? note;

  Macros get macros => food.forGrams(grams);

  /// "150 g" or "2 loaves (180 g)".
  String amount(BuildContext context) =>
      unit == null ? '${formatNum(grams)} g' : '${formatNum(quantity)} ${unit!.name(context)} (${formatNum(grams)} g)';

  factory MealItem.fromJson(Map<String, dynamic> json) => MealItem(
        id: json['id'] as String,
        food: Food.fromJson(json['food'] as Map<String, dynamic>),
        quantity: json['quantity'] as num,
        grams: json['grams'] as num,
        unit: json['unit'] == null ? null : FoodUnit.fromJson(json['unit'] as Map<String, dynamic>),
        note: json['note'] as String?,
      );
}

class MealOption {
  const MealOption({required this.id, required this.label, required this.sortOrder, required this.items});

  final String id;
  final String label;
  final int sortOrder;
  final List<MealItem> items;

  Macros get macros => items.fold(const Macros(), (sum, item) => sum + item.macros);

  factory MealOption.fromJson(Map<String, dynamic> json) => MealOption(
        id: json['id'] as String,
        label: json['label'] as String,
        sortOrder: json['sort_order'] as int,
        items: ((json['meal_option_items'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .toList()
            .map(MealItem.fromJson)
            .toList(),
      );
}

class Meal {
  const Meal({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.countsForStreak,
    required this.options,
    this.timeHint,
  });

  final String id;
  final String name;
  final int sortOrder;
  final bool countsForStreak;
  final String? timeHint;
  final List<MealOption> options;

  factory Meal.fromJson(Map<String, dynamic> json) => Meal(
        id: json['id'] as String,
        name: json['name'] as String,
        sortOrder: json['sort_order'] as int,
        countsForStreak: json['counts_for_streak'] as bool? ?? true,
        timeHint: (json['time_hint'] as String?)?.substring(0, 5),
        options: ((json['meal_options'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(MealOption.fromJson)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
      );
}

class NutritionVersion {
  const NutritionVersion({required this.id, required this.versionNo, required this.effectiveFrom, required this.meals});

  final String id;
  final int versionNo;
  final DateTime effectiveFrom;
  final List<Meal> meals;

  factory NutritionVersion.fromJson(Map<String, dynamic> json) => NutritionVersion(
        id: json['id'] as String,
        versionNo: json['version_no'] as int,
        effectiveFrom: DateTime.parse(json['effective_from'] as String),
        meals: ((json['meals'] as List?) ?? const []).cast<Map<String, dynamic>>().map(Meal.fromJson).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
      );
}

class NutritionPlan with _Versioned<NutritionVersion> {
  NutritionPlan({required this.id, required this.name, required this.showMacros, this.traineeId, required this.versions});

  final String id;
  final String name;
  final bool showMacros;
  final String? traineeId;
  @override
  final List<NutritionVersion> versions;

  @override
  DateTime effectiveFromOf(NutritionVersion version) => version.effectiveFrom;

  factory NutritionPlan.fromJson(Map<String, dynamic> json) => NutritionPlan(
        id: json['id'] as String,
        name: json['name'] as String,
        showMacros: json['show_macros'] as bool? ?? true,
        traineeId: json['trainee_id'] as String?,
        versions: ((json['nutrition_plan_versions'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(NutritionVersion.fromJson)
            .toList()
          ..sort((a, b) {
            final byDate = b.effectiveFrom.compareTo(a.effectiveFrom);
            return byDate != 0 ? byDate : b.versionNo.compareTo(a.versionNo);
          }),
      );

  static const select = 'id, name, show_macros, trainee_id, nutrition_plan_versions(id, version_no, effective_from, '
      'meals(id, name, time_hint, sort_order, counts_for_streak, meal_options(id, label, sort_order, '
      'meal_option_items(id, quantity, grams, note, sort_order, food:foods(*), unit:food_units(*)))))';
}

class MealLog {
  const MealLog({required this.id, required this.mealId, this.optionId, this.changeNote});

  final String id;
  final String mealId;
  final String? optionId;
  final String? changeNote;

  factory MealLog.fromJson(Map<String, dynamic> json) => MealLog(
        id: json['id'] as String,
        mealId: json['meal_id'] as String,
        optionId: json['option_id'] as String?,
        changeNote: json['change_note'] as String?,
      );
}
