import 'package:flutter/material.dart';

import '../../core/plan_models.dart';
import '../../core/ui.dart';
import '../auth/validators.dart';
import 'food_picker.dart';

enum _Mode { calories, macro, swap }

enum _Macro { protein, carbs, fat }

/// grams = target / value per 100 g × 100. Standalone: saves nothing.
class MealConverterScreen extends StatefulWidget {
  const MealConverterScreen({super.key});

  @override
  State<MealConverterScreen> createState() => _MealConverterScreenState();
}

class _MealConverterScreenState extends State<MealConverterScreen> {
  _Mode _mode = _Mode.calories;
  _Macro _macro = _Macro.protein;
  Food? _food;
  Food? _swapTo;
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Grams of the result food, or null while inputs are missing.
  num? get _grams {
    final amount = parseNumber(_amount.text);
    final food = _mode == _Mode.swap ? _swapTo : _food;
    if (amount == null || amount <= 0 || food == null) return null;
    final per100 = switch (_mode) {
      _Mode.calories => food.kcal,
      _Mode.macro => switch (_macro) { _Macro.protein => food.protein, _Macro.carbs => food.carbs, _Macro.fat => food.fat },
      _Mode.swap => food.kcal,
    };
    if (per100 <= 0) return null;
    final target = _mode == _Mode.swap ? (_food == null ? null : _food!.kcal * amount / 100) : amount;
    return target == null ? null : target / per100 * 100;
  }

  Widget _foodButton(Food? food, ValueChanged<Food> onPicked, String label) => OutlinedButton.icon(
        icon: const Icon(Icons.restaurant),
        label: Text(food?.name(context) ?? label, overflow: TextOverflow.ellipsis),
        onPressed: () async {
          final picked = await pickFood(context);
          if (picked != null) setState(() => onPicked(picked));
        },
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final grams = _grams;
    final result = _mode == _Mode.swap ? _swapTo : _food;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mealConverter)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<_Mode>(
            segments: [
              ButtonSegment(value: _Mode.calories, label: Text(l10n.byCalories)),
              ButtonSegment(value: _Mode.macro, label: Text(l10n.byMacro)),
              ButtonSegment(value: _Mode.swap, label: Text(l10n.swapFood)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 24),
          _foodButton(_food, (f) => _food = f, _mode == _Mode.swap ? l10n.foodA : l10n.chooseFood),
          const SizedBox(height: 16),
          if (_mode == _Mode.macro) ...[
            SegmentedButton<_Macro>(
              segments: [
                ButtonSegment(value: _Macro.protein, label: Text(l10n.protein)),
                ButtonSegment(value: _Macro.carbs, label: Text(l10n.carbs)),
                ButtonSegment(value: _Macro.fat, label: Text(l10n.fat)),
              ],
              selected: {_macro},
              onSelectionChanged: (s) => setState(() => _macro = s.first),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: switch (_mode) {
                _Mode.calories => l10n.targetCalories,
                _Mode.macro => l10n.targetGrams,
                _Mode.swap => l10n.gramsOfFoodA,
              },
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_mode == _Mode.swap) ...[
            const SizedBox(height: 16),
            _foodButton(_swapTo, (f) => _swapTo = f, l10n.foodB),
          ],
          const SizedBox(height: 32),
          if (grams != null && result != null)
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text('${formatNum(grams.round())} ${l10n.grams}', style: theme.textTheme.displaySmall),
                    Text(result.name(context), style: theme.textTheme.titleMedium),
                    if (result.cookedYield != null && result.state == 'raw')
                      Text(l10n.cookedWeight(formatNum((grams * result.cookedYield!).round())), style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 8),
                    Text(
                      '${formatNum(result.forGrams(grams).kcal.round())} ${l10n.kcal} · '
                      '${l10n.proteinShort} ${formatNum(result.forGrams(grams).protein.round())} · '
                      '${l10n.carbsShort} ${formatNum(result.forGrams(grams).carbs.round())} · '
                      '${l10n.fatShort} ${formatNum(result.forGrams(grams).fat.round())}',
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
