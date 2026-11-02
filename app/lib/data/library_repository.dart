import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/plan_models.dart';

/// A spreadsheet name matched against the library (pg_trgm).
class ExerciseMatch {
  const ExerciseMatch({required this.exerciseId, required this.nameEn, required this.score, required this.exact});

  final String exerciseId;
  final String nameEn;
  final double score;
  final bool exact;

  factory ExerciseMatch.fromJson(Map<String, dynamic> json) => ExerciseMatch(
        exerciseId: json['exercise_id'] as String,
        nameEn: json['name_en'] as String,
        score: (json['score'] as num).toDouble(),
        exact: json['exact'] as bool,
      );
}

/// Food values from Open Food Facts, before saving.
class FoodDraft {
  const FoodDraft({required this.name, required this.kcal, required this.protein, required this.carbs, required this.fat, this.barcode});

  final String name;
  final num kcal;
  final num protein;
  final num carbs;
  final num fat;
  final String? barcode;
}

class LibraryRepository {
  LibraryRepository(this._client);

  final SupabaseClient _client;

  String get _me => _client.auth.currentUser!.id;

  // --- exercises ----------------------------------------------------------

  Future<List<Exercise>> searchExercises(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      final rows = await _client.from('exercises').select().order('name_en').limit(50);
      return rows.map(Exercise.fromJson).toList();
    }
    final matches = await matchExercise(q, limit: 30);
    final byName = await _client.from('exercises').select().ilike('name_en', '%$q%').order('name_en').limit(30);
    final result = <String, Exercise>{for (final row in byName) row['id'] as String: Exercise.fromJson(row)};
    if (matches.isNotEmpty) {
      final missing = matches.map((m) => m.exerciseId).where((id) => !result.containsKey(id)).toList();
      if (missing.isNotEmpty) {
        final rows = await _client.from('exercises').select().inFilter('id', missing);
        for (final row in rows) {
          result[row['id'] as String] = Exercise.fromJson(row);
        }
      }
      // closest matches first
      final order = {for (var i = 0; i < matches.length; i++) matches[i].exerciseId: i};
      return result.values.toList()..sort((a, b) => (order[a.id] ?? 999).compareTo(order[b.id] ?? 999));
    }
    return result.values.toList();
  }

  Future<List<ExerciseMatch>> matchExercise(String name, {int limit = 3}) async {
    final rows = await _client.rpc('match_exercise', params: {'p_name': name, 'p_limit': limit}) as List;
    return rows.cast<Map<String, dynamic>>().map(ExerciseMatch.fromJson).toList();
  }

  Future<Exercise> createExercise({required String nameEn, String? nameAr, required Tracking tracking, String? category}) async {
    final row = await _client
        .from('exercises')
        .insert({
          'name_en': nameEn.trim(),
          'name_ar': nameAr == null || nameAr.trim().isEmpty ? null : nameAr.trim(),
          'tracking': tracking.key,
          'category': category,
          'created_by': _me,
        })
        .select()
        .single();
    return Exercise.fromJson(row);
  }

  /// Remembers a coach's spelling so future uploads link straight away.
  Future<void> saveAlias(String exerciseId, String alias) async {
    final exists = await _client.from('exercise_aliases').select('id').ilike('alias', alias.trim()).maybeSingle();
    if (exists == null) {
      await _client.from('exercise_aliases').insert({'exercise_id': exerciseId, 'alias': alias.trim(), 'created_by': _me});
    }
  }

  // --- foods --------------------------------------------------------------

  Future<List<Food>> searchFoods(String query) async {
    final q = query.trim();
    final rows = q.isEmpty
        ? await _client.from('foods').select('*, food_units(*)').order('name_en').limit(50)
        : await _withUnits((await _client.rpc('search_foods', params: {'p_query': q, 'p_limit': 40}) as List)
            .cast<Map<String, dynamic>>());
    return rows.map(Food.fromJson).toList();
  }

  Future<List<Map<String, dynamic>>> _withUnits(List<Map<String, dynamic>> foods) async {
    if (foods.isEmpty) return foods;
    final units = await _client.from('food_units').select().inFilter('food_id', [for (final f in foods) f['id']]);
    return [
      for (final f in foods) {...f, 'food_units': units.where((u) => u['food_id'] == f['id']).toList()},
    ];
  }

  Future<Food?> foodByBarcode(String barcode) async {
    final row = await _client.from('foods').select('*, food_units(*)').eq('barcode', barcode).limit(1).maybeSingle();
    return row == null ? null : Food.fromJson(row);
  }

  /// Looks a packaged product up on Open Food Facts (ODbL, attribution shown in the app).
  Future<FoodDraft?> lookupOpenFoodFacts(String barcode) async {
    final res = await http.get(Uri.parse(
        'https://world.openfoodfacts.org/api/v2/product/$barcode.json?fields=product_name,product_name_ar,brands,nutriments'));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final product = body['product'] as Map<String, dynamic>?;
    final n = product?['nutriments'] as Map<String, dynamic>?;
    if (product == null || n == null || n['energy-kcal_100g'] == null) return null;
    final brand = (product['brands'] as String?)?.split(',').first.trim();
    final name = (product['product_name'] as String?)?.trim();
    return FoodDraft(
      name: [if (brand != null && brand.isNotEmpty) brand, if (name != null && name.isNotEmpty) name].join(' ').trim(),
      kcal: n['energy-kcal_100g'] as num,
      protein: (n['proteins_100g'] as num?) ?? 0,
      carbs: (n['carbohydrates_100g'] as num?) ?? 0,
      fat: (n['fat_100g'] as num?) ?? 0,
      barcode: barcode,
    );
  }

  Future<Food> createFood({
    required String nameEn,
    String? nameAr,
    required num kcal,
    required num protein,
    required num carbs,
    required num fat,
    String? barcode,
    num? cookedYield,
    String? state,
    List<(String, String, num)> units = const [],
  }) async {
    final row = await _client
        .from('foods')
        .insert({
          'name_en': nameEn.trim(),
          'name_ar': nameAr == null || nameAr.trim().isEmpty ? null : nameAr.trim(),
          'source': barcode == null ? 'custom' : 'open_food_facts',
          'source_ref': barcode,
          'barcode': barcode,
          'kcal': kcal,
          'protein_g': protein,
          'carbs_g': carbs,
          'fat_g': fat,
          'cooked_yield': cookedYield,
          'state': state,
          'created_by': _me,
        })
        .select('id')
        .single();
    if (units.isNotEmpty) {
      await _client.from('food_units').insert([
        for (final (en, ar, grams) in units) {'food_id': row['id'], 'name_en': en, 'name_ar': ar, 'grams': grams, 'created_by': _me},
      ]);
    }
    return Food.fromJson(await _client.from('foods').select('*, food_units(*)').eq('id', row['id']).single());
  }

  Future<void> addUnit(String foodId, String nameEn, String nameAr, num grams) => _client
      .from('food_units')
      .insert({'food_id': foodId, 'name_en': nameEn.trim(), 'name_ar': nameAr.trim(), 'grams': grams, 'created_by': _me});
}
