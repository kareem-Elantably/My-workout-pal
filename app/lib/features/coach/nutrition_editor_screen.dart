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

/// One change to the plan, applied to the version being edited.
typedef NutritionEdit = Future<void> Function(NutritionVersion version);

/// Builds a nutrition plan: meals → options (A, B, ...) → foods with
/// amounts in grams or units. Macros add up as you go.
///
/// Like the workout editor, once the trainee has logged a meal the first
/// edit copies the version into a new one from today and applies there.
class NutritionEditorScreen extends ConsumerStatefulWidget {
  const NutritionEditorScreen({super.key, required this.planId});

  final String planId;

  @override
  ConsumerState<NutritionEditorScreen> createState() => _NutritionEditorScreenState();
}

class _NutritionEditorScreenState extends ConsumerState<NutritionEditorScreen> {
  bool _busy = false;

  Future<void> _edit(NutritionEdit edit) async {
    final data = ref.read(nutritionPlanProvider(widget.planId)).value;
    if (_busy || data == null) return;
    setState(() => _busy = true);
    try {
      final (plan, frozen) = data;
      var version = plan.latest!;
      if (frozen) {
        await ref.read(planEditorRepositoryProvider).copyNutritionVersion(version.id, plan.id);
        version = (await ref.read(nutritionRepositoryProvider).plan(plan.id)).latest!;
        if (mounted) showMessage(context, context.l10n.editSavedAsNewVersion);
      }
      await edit(version);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      ref.invalidate(nutritionPlanProvider(widget.planId));
      try {
        await ref.read(nutritionPlanProvider(widget.planId).future);
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Plan-level settings aren't versioned: no copy needed.
  Future<void> _plain(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    ref.invalidate(nutritionPlanProvider(widget.planId));
  }

  Future<void> _editMeal({int? index, Meal? meal, required int sortOrder}) async {
    final result = await showDialog<(String, String?, bool)>(
      context: context,
      builder: (_) => _MealDialog(meal: meal),
    );
    if (result == null) return;
    final (name, time, counts) = result;
    await _edit((v) => ref.read(planEditorRepositoryProvider).saveMeal(
          v.id,
          id: index == null ? null : v.meals[index].id,
          name: name,
          time: time,
          sortOrder: meal?.sortOrder ?? sortOrder,
          countsForStreak: counts,
        ));
  }

  Future<void> _mealAction(String action, int index, Meal meal) async {
    final l10n = context.l10n;
    final repo = ref.read(planEditorRepositoryProvider);
    List<Meal> moved(NutritionVersion v, int to) => [...v.meals]..insert(to, v.meals[index])..removeAt(to < index ? index + 1 : index);
    switch (action) {
      case 'edit':
        await _editMeal(index: index, meal: meal, sortOrder: meal.sortOrder);
      case 'up':
        await _edit((v) => repo.reorderMeals(moved(v, index - 1)));
      case 'down':
        await _edit((v) => repo.reorderMeals(moved(v, index + 2)));
      case 'option':
        final label = await promptText(context, title: l10n.optionName, initial: String.fromCharCode(65 + meal.options.length));
        if (label != null && label.trim().isNotEmpty) {
          await _edit((v) => repo.saveOption(v.meals[index].id, label: label, sortOrder: meal.options.length + 1));
        }
      case 'delete':
        if (await confirm(context, l10n.deleteMealConfirm, action: l10n.delete)) {
          await _edit((v) => repo.deleteMeal(v.meals[index].id));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final data = ref.watch(nutritionPlanProvider(widget.planId));
    final repo = ref.read(planEditorRepositoryProvider);
    final plan = data.value?.$1;
    return Scaffold(
      appBar: AppBar(
        title: Text(plan?.name ?? ''),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
        actions: [
          if (plan != null)
            PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'rename') {
                  final name = await promptText(context, title: l10n.renamePlan, initial: plan.name);
                  if (name != null && name.trim().isNotEmpty) await _plain(() => repo.updateNutritionPlan(widget.planId, name: name));
                } else if (action == 'template' && plan.latest != null) {
                  final name = await promptText(context, title: l10n.saveAsTemplate, initial: plan.name);
                  if (name != null && name.trim().isNotEmpty) {
                    await _plain(() => repo.saveNutritionAsTemplate(plan, plan.latest!, name));
                    if (context.mounted) showMessage(context, l10n.templateSaved);
                  }
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'rename', child: Text(l10n.renamePlan)),
                if (plan.traineeId != null) PopupMenuItem(value: 'template', child: Text(l10n.saveAsTemplate)),
              ],
            ),
        ],
      ),
      floatingActionButton: plan?.latest == null
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: Text(l10n.addMeal),
              onPressed: _busy ? null : () => _editMeal(sortOrder: plan!.latest!.meals.length + 1),
            ),
      body: AsyncBody(
        value: data,
        onRetry: () => ref.invalidate(nutritionPlanProvider(widget.planId)),
        builder: (d) {
          final (plan, _) = d;
          final version = plan.latest;
          if (version == null) return const SizedBox.shrink();
          final dayTotal = version.meals
              .where((m) => m.options.isNotEmpty)
              .fold(const Macros(), (sum, m) => sum + m.options.first.macros);
          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                SwitchListTile(
                  title: Text(l10n.showMacrosToTrainee),
                  value: plan.showMacros,
                  onChanged: (on) => _plain(() => repo.updateNutritionPlan(widget.planId, showMacros: on)),
                ),
                ListTile(title: Text(l10n.dayTotalFirstOptions), subtitle: MacrosLine(dayTotal)),
                if (version.meals.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(l10n.nutritionEditorEmptyHint),
                  ),
                for (final (mi, meal) in version.meals.indexed)
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
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) => _mealAction(action, mi, meal),
                              itemBuilder: (context) => [
                                PopupMenuItem(value: 'edit', child: Text(l10n.edit)),
                                if (mi > 0) PopupMenuItem(value: 'up', child: Text(l10n.moveUp)),
                                if (mi < version.meals.length - 1) PopupMenuItem(value: 'down', child: Text(l10n.moveDown)),
                                PopupMenuItem(value: 'option', child: Text(l10n.addOption)),
                                PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                              ],
                            ),
                          ),
                          if (meal.options.isEmpty)
                            TextButton.icon(
                              icon: const Icon(Icons.add),
                              label: Text(l10n.addOption),
                              onPressed: () => _edit((v) => repo.saveOption(v.meals[mi].id, label: 'A', sortOrder: 1)),
                            ),
                          for (final (oi, option) in meal.options.indexed)
                            _OptionTile(
                              option: option,
                              edit: _edit,
                              find: (v) => v.meals[mi].options[oi],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OptionTile extends ConsumerWidget {
  const _OptionTile({required this.option, required this.edit, required this.find});

  final MealOption option;
  final Future<void> Function(NutritionEdit edit) edit;

  /// The same option in the version being edited.
  final MealOption Function(NutritionVersion version) find;

  /// The same item in the version being edited (matched on what it holds,
  /// since ids change in a new version).
  static MealItem _sameItem(MealOption option, MealItem item) => option.items.firstWhere(
        (i) => i.food.id == item.food.id && i.quantity == item.quantity && i.unit?.id == item.unit?.id,
        orElse: () => item,
      );

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
            IconButton(
              tooltip: l10n.delete,
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () async {
                if (await confirm(context, l10n.deleteOptionConfirm, action: l10n.delete)) {
                  await edit((v) => repo.deleteOption(find(v).id));
                }
              },
            ),
          ]),
          for (final item in option.items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item.food.name(context)),
              subtitle: Text(item.amount(context)),
              onTap: () async {
                final amount = await _askAmount(context, item.food, item: item);
                if (amount != null) {
                  await edit((v) {
                    final o = find(v);
                    return repo.saveItem(o.id, id: _sameItem(o, item).id, foodId: item.food.id, quantity: amount.$1, unitId: amount.$2);
                  });
                }
              },
              trailing: IconButton(
                tooltip: l10n.delete,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => edit((v) => repo.deleteItem(_sameItem(find(v), item).id)),
              ),
            ),
          MacrosLine(option.macros),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(l10n.addFood),
              onPressed: () async {
                final food = await pickFood(context, canAdd: true);
                if (food == null || !context.mounted) return;
                final amount = await _askAmount(context, food);
                if (amount != null) await edit((v) => repo.saveItem(find(v).id, foodId: food.id, quantity: amount.$1, unitId: amount.$2));
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
