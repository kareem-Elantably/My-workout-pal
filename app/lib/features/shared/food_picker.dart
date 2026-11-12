import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import 'new_food.dart';

/// Search the shared food library (Arabic or English). Returns the food.
///
/// With [canAdd] (coaches), a food that isn't there can be added on the
/// spot, by typing its values or scanning its barcode, and is returned
/// straight away. Otherwise (trainees) the empty result says to ask the coach.
Future<Food?> pickFood(BuildContext context, {bool canAdd = false}) => showModalBottomSheet<Food>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.9, child: _FoodSearch(canAdd: canAdd)),
    );

class _FoodSearch extends ConsumerStatefulWidget {
  const _FoodSearch({required this.canAdd});

  final bool canAdd;

  @override
  ConsumerState<_FoodSearch> createState() => _FoodSearchState();
}

class _FoodSearchState extends ConsumerState<_FoodSearch> {
  Timer? _debounce;
  String _query = '';
  late Future<List<Food>> _results = _search('');

  Future<List<Food>> _search(String q) => ref.read(libraryRepositoryProvider).searchFoods(q);

  void _reload() => setState(() {
        _results = _search(_query);
      });

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _add() async {
    final food = await addNewFood(context, name: _query);
    if (food != null && mounted) Navigator.pop(context, food);
  }

  Future<void> _scan() async {
    final food = await scanFood(context, ref);
    if (food != null && mounted) Navigator.pop(context, food);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final typed = _query.trim();
    final addTile = ListTile(
      leading: const Icon(Icons.add_circle_outline),
      title: Text(typed.isEmpty ? l10n.addNewFood : l10n.addFoodNamed(typed)),
      subtitle: Text(l10n.addNewFoodHint),
      onTap: _add,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.searchFoods,
              suffixIcon: widget.canAdd
                  ? IconButton(tooltip: l10n.scanBarcode, icon: const Icon(Icons.qr_code_scanner), onPressed: _scan)
                  : null,
            ),
            onChanged: (q) {
              _query = q;
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), _reload);
            },
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.hasError) return ErrorRetry(error: snapshot.error!, onRetry: _reload);
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final foods = snapshot.data!;
              if (foods.isEmpty) {
                return ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(widget.canAdd ? l10n.foodNotFoundCoach : l10n.foodNotFoundTrainee, textAlign: TextAlign.center),
                  ),
                  if (widget.canAdd) addTile,
                ]);
              }
              return ListView.builder(
                itemCount: foods.length + (widget.canAdd ? 1 : 0),
                itemBuilder: (context, i) {
                  // The add row sits after the results: still one tap away
                  // when the list doesn't have the exact food.
                  if (i == foods.length) return addTile;
                  final food = foods[i];
                  return ListTile(
                    title: Text(food.name(context)),
                    subtitle: Text('${formatNum(food.kcal)} ${l10n.kcal} / 100 ${l10n.grams}'
                        '${food.source == 'open_food_facts' ? ' · Open Food Facts' : ''}'),
                    onTap: () => Navigator.pop(context, food),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
