import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../auth/validators.dart';
import '../shared/food_picker.dart';

final nutritionPlanProvider = FutureProvider.autoDispose.family<(NutritionPlan, bool), String>((ref, planId) async {
  final plan = await ref.watch(nutritionRepositoryProvider).plan(planId);
  final frozen = plan.latest == null ? false : await ref.watch(planEditorRepositoryProvider).nutritionVersionFrozen(plan.latest!);
  return (plan, frozen);
});

/// Builds a nutrition plan: meals → options (A, B, ...) → foods with
/// amounts in grams or units. Macros add up as you go.
class NutritionEditorScreen extends ConsumerWidget {
  const NutritionEditorScreen({super.key, required this.planId});

  final String planId;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(nutritionPlanProvider(planId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _editMeal(BuildContext context, WidgetRef ref, String versionId, {Meal? meal, required int sortOrder}) async {
    final result = await showDialog<(String, String?, bool)>(
      context: context,
      builder: (_) => _MealDialog(meal: meal),
    );
    if (result == null || !context.mounted) return;
    final (name, time, counts) = result;
    await _run(context, ref, () => ref.read(planEditorRepositoryProvider).saveMeal(
          versionId,
          id: meal?.id,
          name: name,
          time: time,
          sortOrder: meal?.sortOrder ?? sortOrder,
          countsForStreak: counts,
        ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final data = ref.watch(nutritionPlanProvider(planId));
    final repo = ref.read(planEditorRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(data.value?.$1.name ?? ''),
        actions: [
          if (data.value != null)
            PopupMenuButton<String>(
              onSelected: (action) async {
                final plan = data.value!.$1;
                if (action == 'rename') {
                  final name = await promptText(context, title: l10n.renamePlan, initial: plan.name);
                  if (name != null && name.trim().isNotEmpty && context.mounted) {
                    await _run(context, ref, () => repo.updateNutritionPlan(planId, name: name));
                  }
                } else if (action == 'template' && plan.latest != null) {
                  final name = await promptText(context, title: l10n.saveAsTemplate, initial: plan.name);
                  if (name != null && name.trim().isNotEmpty && context.mounted) {
                    await _run(context, ref, () => repo.saveNutritionAsTemplate(plan, plan.latest!, name));
                    if (context.mounted) showMessage(context, l10n.templateSaved);
                  }
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'rename', child: Text(l10n.renamePlan)),
                if (data.value!.$1.traineeId != null) PopupMenuItem(value: 'template', child: Text(l10n.saveAsTemplate)),
              ],
            ),
        ],
      ),
      floatingActionButton: data.value == null || data.value!.$2
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: Text(l10n.addMeal),
              onPressed: () => _editMeal(context, ref, data.value!.$1.latest!.id, sortOrder: data.value!.$1.latest!.meals.length + 1),
            ),
      body: AsyncBody(
        value: data,
        onRetry: () => ref.invalidate(nutritionPlanProvider(planId)),
        builder: (d) {
          final (plan, frozen) = d;
          final version = plan.latest;
          if (version == null) return const SizedBox.shrink();
          final dayTotal = version.meals
              .where((m) => m.options.isNotEmpty)
              .fold(const Macros(), (sum, m) => sum + m.options.first.macros);
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (frozen)
                MaterialBanner(
                  content: Text(l10n.versionHasLogs),
                  leading: const Icon(Icons.lock_outline),
                  actions: [
                    TextButton(
                      onPressed: () => _run(context, ref, () => repo.copyNutritionVersion(version.id, plan.id)),
                      child: Text(l10n.newVersion),
                    ),
                  ],
                ),
              SwitchListTile(
                title: Text(l10n.showMacrosToTrainee),
                value: plan.showMacros,
                onChanged: (on) => _run(context, ref, () => repo.updateNutritionPlan(planId, showMacros: on)),
              ),
              ListTile(title: Text(l10n.dayTotalFirstOptions), subtitle: MacrosLine(dayTotal)),
              for (final meal in version.meals)
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          title: Text([meal.name, ?meal.timeHint].join(' · '), style: Theme.of(context).textTheme.titleMedium),
                          subtitle: meal.countsForStreak ? null : Text(l10n.optionalNotInStreak),
                          trailing: frozen
                              ? null
                              : PopupMenuButton<String>(
                                  onSelected: (action) async {
                                    if (action == 'edit') {
                                      await _editMeal(context, ref, version.id, meal: meal, sortOrder: meal.sortOrder);
                                    } else if (action == 'option') {
                                      if (!context.mounted) return;
                                      final label = await promptText(context, title: l10n.optionName, initial: String.fromCharCode(65 + meal.options.length));
                                      if (label != null && label.trim().isNotEmpty && context.mounted) {
                                        await _run(context, ref, () => repo.saveOption(meal.id, label: label, sortOrder: meal.options.length + 1));
                                      }
                                    } else {
                                      if (!await confirm(context, l10n.deleteMealConfirm, action: l10n.delete)) return;
                                      if (context.mounted) await _run(context, ref, () => repo.deleteMeal(meal.id));
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(value: 'edit', child: Text(l10n.edit)),
                                    PopupMenuItem(value: 'option', child: Text(l10n.addOption)),
                                    PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                                  ],
                                ),
                        ),
                        if (meal.options.isEmpty && !frozen)
                          TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: Text(l10n.addOption),
                            onPressed: () => _run(context, ref, () => repo.saveOption(meal.id, label: 'A', sortOrder: 1)),
                          ),
                        for (final option in meal.options)
                          _OptionTile(option: option, frozen: frozen, run: (a) => _run(context, ref, a)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _OptionTile extends ConsumerWidget {
  const _OptionTile({required this.option, required this.frozen, required this.run});

  final MealOption option;
  final bool frozen;
  final Future<void> Function(Future<void> Function() action) run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final repo = ref.read(planEditorRepositoryProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(l10n.optionLabel(option.label), style: Theme.of(context).textTheme.labelLarge)),
            if (!frozen)
              IconButton(
                tooltip: l10n.delete,
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () async {
                  if (await confirm(context, l10n.deleteOptionConfirm, action: l10n.delete)) await run(() => repo.deleteOption(option.id));
                },
              ),
          ]),
          for (final item in option.items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item.food.name(context)),
              subtitle: Text(item.amount(context)),
              onTap: frozen
                  ? null
                  : () async {
                      final amount = await _askAmount(context, item.food, item: item);
                      if (amount != null) {
                        await run(() => repo.saveItem(option.id, id: item.id, foodId: item.food.id, quantity: amount.$1, unitId: amount.$2));
                      }
                    },
              trailing: frozen
                  ? null
                  : IconButton(
                      tooltip: l10n.delete,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => run(() => repo.deleteItem(item.id)),
                    ),
            ),
          MacrosLine(option.macros),
          if (!frozen)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(l10n.addFood),
                onPressed: () async {
                  final food = await pickFood(context);
                  if (food == null || !context.mounted) return;
                  final amount = await _askAmount(context, food);
                  if (amount != null) await run(() => repo.saveItem(option.id, foodId: food.id, quantity: amount.$1, unitId: amount.$2));
                },
              ),
            ),
          const Divider(),
        ],
      ),
    );
  }
}

/// Quantity in grams or in one of the food's units. Returns (quantity, unitId).
Future<(num, String?)?> _askAmount(BuildContext context, Food food, {MealItem? item}) => showDialog<(num, String?)>(
      context: context,
      builder: (_) => _AmountDialog(food: food, item: item),
    );

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.food, this.item});

  final Food food;
  final MealItem? item;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _quantity = TextEditingController(text: formatNum(widget.item?.quantity ?? (widget.food.units.isEmpty ? 100 : 1)));
  late String? _unitId = widget.item?.unit?.id ?? (widget.food.units.isEmpty ? null : widget.food.units.first.id);

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final quantity = parseNumber(_quantity.text);
    final unit = widget.food.units.where((u) => u.id == _unitId).firstOrNull;
    final grams = quantity == null ? null : (unit == null ? quantity : quantity * unit.grams);
    return AlertDialog(
      title: Text(widget.food.name(context)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _quantity,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: l10n.quantity),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String?>(
              value: _unitId,
              items: [
                DropdownMenuItem(value: null, child: Text(l10n.grams)),
                for (final u in widget.food.units) DropdownMenuItem(value: u.id, child: Text(u.name(context))),
              ],
              onChanged: (id) => setState(() => _unitId = id),
            ),
          ]),
          if (grams != null) ...[
            const SizedBox(height: 12),
            Text('= ${formatNum(grams)} ${l10n.grams}'),
            MacrosLine(widget.food.forGrams(grams)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: quantity == null || quantity <= 0 ? null : () => Navigator.pop(context, (quantity, _unitId)),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _MealDialog extends StatefulWidget {
  const _MealDialog({this.meal});

  final Meal? meal;

  @override
  State<_MealDialog> createState() => _MealDialogState();
}

class _MealDialogState extends State<_MealDialog> {
  late final _name = TextEditingController(text: widget.meal?.name);
  late String? _time = widget.meal?.timeHint;
  late bool _counts = widget.meal?.countsForStreak ?? true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.meal == null ? l10n.addMeal : l10n.edit),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _name, autofocus: true, decoration: InputDecoration(labelText: l10n.mealName, hintText: l10n.mealNameHint)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(_time ?? l10n.setTime, textDirection: TextDirection.ltr),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
              if (picked != null) {
                setState(() => _time = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
              }
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.countsForStreak),
            value: _counts,
            onChanged: (v) => setState(() => _counts = v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(context, (_name.text, _time, _counts));
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
