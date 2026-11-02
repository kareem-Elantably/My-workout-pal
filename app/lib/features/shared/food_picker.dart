import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';

/// Search the shared food library (Arabic or English). Returns the food.
Future<Food?> pickFood(BuildContext context, {Widget? extraAction}) => showModalBottomSheet<Food>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.9, child: _FoodSearch(extraAction: extraAction)),
    );

class _FoodSearch extends ConsumerStatefulWidget {
  const _FoodSearch({this.extraAction});

  final Widget? extraAction;

  @override
  ConsumerState<_FoodSearch> createState() => _FoodSearchState();
}

class _FoodSearchState extends ConsumerState<_FoodSearch> {
  Timer? _debounce;
  late Future<List<Food>> _results = _search('');

  Future<List<Food>> _search(String q) => ref.read(libraryRepositoryProvider).searchFoods(q);

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: true,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l10n.searchFoods),
            onChanged: (q) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _results = _search(q)));
            },
          ),
        ),
        ?widget.extraAction,
        Expanded(
          child: FutureBuilder(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.hasError) return ErrorRetry(error: snapshot.error!, onRetry: () => setState(() => _results = _search('')));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final foods = snapshot.data!;
              if (foods.isEmpty) return Center(child: Text(l10n.noResults));
              return ListView.builder(
                itemCount: foods.length,
                itemBuilder: (context, i) {
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
