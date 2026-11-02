import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../../data/library_repository.dart';
import '../auth/validators.dart';
import '../shared/notifications_button.dart';
import 'exercise_picker.dart';

final _workoutTemplatesProvider = FutureProvider.autoDispose((ref) => ref.watch(planEditorRepositoryProvider).workoutTemplates());
final _nutritionTemplatesProvider = FutureProvider.autoDispose((ref) => ref.watch(planEditorRepositoryProvider).nutritionTemplates());

/// Coach library: templates, the exercise library and the food library.
class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.library),
          actions: const [NotificationsButton()],
          bottom: TabBar(tabs: [Tab(text: l10n.templates), Tab(text: l10n.exercises), Tab(text: l10n.foods)]),
        ),
        body: const TabBarView(children: [_Templates(), _Exercises(), _Foods()]),
      ),
    );
  }
}

class _Templates extends ConsumerWidget {
  const _Templates();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final workout = ref.watch(_workoutTemplatesProvider);
    final nutrition = ref.watch(_nutritionTemplatesProvider);
    final editor = ref.read(planEditorRepositoryProvider);
    Future<void> open(String path) async {
      await context.push(path);
      ref
        ..invalidate(_workoutTemplatesProvider)
        ..invalidate(_nutritionTemplatesProvider);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: Text(l10n.templatesHint)),
        SectionTitle(
          l10n.workoutTemplates,
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.add),
            tooltip: l10n.newTemplate,
            onSelected: (action) async {
              if (action == 'excel') return open('/coach/import');
              final name = await promptText(context, title: l10n.newTemplate, label: l10n.planName);
              if (name == null || name.trim().isEmpty) return;
              open('/coach/workout-plans/${await editor.createWorkoutPlan(name: name, cycleLength: 7)}');
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'blank', child: Text(l10n.newTemplate)),
              PopupMenuItem(value: 'excel', child: Text(l10n.uploadExcel)),
            ],
          ),
        ),
        ...workout.when(
          loading: () => [const LinearProgressIndicator()],
          error: (e, _) => [ErrorRetry(error: e, onRetry: () => ref.invalidate(_workoutTemplatesProvider))],
          data: (list) => list.isEmpty
              ? [ListTile(title: Text(l10n.noTemplates))]
              : [
                  for (final t in list)
                    ListTile(
                      leading: const Icon(Icons.fitness_center),
                      title: Text(t.name),
                      subtitle: Text(l10n.trainingDays(t.latest?.days.length ?? 0)),
                      onTap: () => open('/coach/workout-plans/${t.id}'),
                    ),
                ],
        ),
        SectionTitle(
          l10n.nutritionTemplates,
          trailing: IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.newTemplate,
            onPressed: () async {
              final name = await promptText(context, title: l10n.newTemplate, label: l10n.planName);
              if (name == null || name.trim().isEmpty) return;
              open('/coach/nutrition-plans/${await editor.createNutritionPlan(name: name)}');
            },
          ),
        ),
        ...nutrition.when(
          loading: () => [const LinearProgressIndicator()],
          error: (e, _) => [ErrorRetry(error: e, onRetry: () => ref.invalidate(_nutritionTemplatesProvider))],
          data: (list) => list.isEmpty
              ? [ListTile(title: Text(l10n.noTemplates))]
              : [
                  for (final t in list)
                    ListTile(
                      leading: const Icon(Icons.restaurant),
                      title: Text(t.name),
                      subtitle: Text(l10n.mealCount(t.latest?.meals.length ?? 0)),
                      onTap: () => open('/coach/nutrition-plans/${t.id}'),
                    ),
                ],
        ),
      ],
    );
  }
}

class _Exercises extends ConsumerStatefulWidget {
  const _Exercises();

  @override
  ConsumerState<_Exercises> createState() => _ExercisesState();
}

class _ExercisesState extends ConsumerState<_Exercises> {
  Timer? _debounce;
  late Future<List<Exercise>> _results = ref.read(libraryRepositoryProvider).searchExercises('');

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-exercise',
        icon: const Icon(Icons.add),
        label: Text(l10n.newExercise),
        onPressed: () async {
          final created = await showDialog<Exercise>(context: context, builder: (_) => const NewExerciseDialog());
          if (created != null && context.mounted) showMessage(context, l10n.saved);
        },
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l10n.searchExercises),
            onChanged: (q) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300),
                  () => setState(() => _results = ref.read(libraryRepositoryProvider).searchExercises(q)));
            },
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: _results,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: snapshot.data!.length,
                itemBuilder: (context, i) {
                  final e = snapshot.data![i];
                  return ListTile(
                    title: Text(e.name(context)),
                    subtitle: Text([trackingLabel(context, e.tracking), ?e.category, ?e.equipment].join(' · ')),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _Foods extends ConsumerStatefulWidget {
  const _Foods();

  @override
  ConsumerState<_Foods> createState() => _FoodsState();
}

class _FoodsState extends ConsumerState<_Foods> {
  Timer? _debounce;
  String _query = '';
  late Future<List<Food>> _results = ref.read(libraryRepositoryProvider).searchFoods('');

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _reload() => setState(() => _results = ref.read(libraryRepositoryProvider).searchFoods(_query));

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _BarcodeScanner()));
    if (code == null || !mounted) return;
    final repo = ref.read(libraryRepositoryProvider);
    final existing = await repo.foodByBarcode(code);
    if (!mounted) return;
    if (existing != null) {
      showMessage(context, context.l10n.foodAlreadyInLibrary(existing.name(context)));
      return;
    }
    FoodDraft? draft;
    try {
      draft = await repo.lookupOpenFoodFacts(code);
    } catch (_) {}
    if (!mounted) return;
    if (draft == null) showMessage(context, context.l10n.barcodeNotFound);
    await _addFood(draft: draft, barcode: code);
  }

  Future<void> _addFood({FoodDraft? draft, String? barcode}) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _FoodDialog(draft: draft, barcode: barcode));
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.small(heroTag: 'scan', tooltip: l10n.scanBarcode, onPressed: _scan, child: const Icon(Icons.qr_code_scanner)),
        const SizedBox(height: 12),
        FloatingActionButton.extended(heroTag: 'new-food', icon: const Icon(Icons.add), label: Text(l10n.newFood), onPressed: () => _addFood()),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l10n.searchFoods),
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
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 140),
                itemCount: snapshot.data!.length,
                itemBuilder: (context, i) {
                  final f = snapshot.data![i];
                  return ListTile(
                    title: Text(f.name(context)),
                    subtitle: MacrosLine(f.forGrams(100)),
                    trailing: f.units.isEmpty ? null : Text(f.units.map((u) => u.name(context)).join(', ')),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(l10n.offAttribution, style: Theme.of(context).textTheme.labelSmall),
        ),
      ]),
    );
  }
}

class _BarcodeScanner extends StatelessWidget {
  const _BarcodeScanner();

  @override
  Widget build(BuildContext context) {
    var done = false;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.scanBarcode)),
      body: MobileScanner(
        onDetect: (capture) {
          final code = capture.barcodes.firstOrNull?.rawValue;
          if (code != null && !done) {
            done = true;
            Navigator.pop(context, code);
          }
        },
      ),
    );
  }
}

class _FoodDialog extends ConsumerStatefulWidget {
  const _FoodDialog({this.draft, this.barcode});

  final FoodDraft? draft;
  final String? barcode;

  @override
  ConsumerState<_FoodDialog> createState() => _FoodDialogState();
}

class _FoodDialogState extends ConsumerState<_FoodDialog> {
  final _form = GlobalKey<FormState>();
  late final _nameEn = TextEditingController(text: widget.draft?.name);
  final _nameAr = TextEditingController();
  late final _kcal = TextEditingController(text: formatNum(widget.draft?.kcal));
  late final _protein = TextEditingController(text: formatNum(widget.draft?.protein));
  late final _carbs = TextEditingController(text: formatNum(widget.draft?.carbs));
  late final _fat = TextEditingController(text: formatNum(widget.draft?.fat));
  final _unitName = TextEditingController();
  final _unitGrams = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_nameEn, _nameAr, _kcal, _protein, _carbs, _fat, _unitName, _unitGrams]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final unitGrams = parseNumber(_unitGrams.text);
      await ref.read(libraryRepositoryProvider).createFood(
            nameEn: _nameEn.text,
            nameAr: _nameAr.text,
            kcal: parseNumber(_kcal.text)!,
            protein: parseNumber(_protein.text) ?? 0,
            carbs: parseNumber(_carbs.text) ?? 0,
            fat: parseNumber(_fat.text) ?? 0,
            barcode: widget.barcode,
            units: _unitName.text.trim().isEmpty || unitGrams == null ? const [] : [(_unitName.text.trim(), _unitName.text.trim(), unitGrams)],
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget field(TextEditingController c, String label, {bool required = false}) => TextFormField(
          controller: c,
          decoration: InputDecoration(labelText: label),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) => validateNumber(context, v, required: required, min: 0, max: 900),
        );
    return AlertDialog(
      title: Text(widget.barcode == null ? l10n.newFood : l10n.foodFromBarcode),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _nameEn,
              decoration: InputDecoration(labelText: l10n.nameEnglish),
              validator: (v) => v == null || v.trim().isEmpty ? l10n.required : null,
            ),
            TextFormField(controller: _nameAr, decoration: InputDecoration(labelText: l10n.nameArabicOptional)),
            const SizedBox(height: 8),
            Text(l10n.per100g, style: Theme.of(context).textTheme.labelLarge),
            field(_kcal, l10n.kcal, required: true),
            Row(children: [
              Expanded(child: field(_protein, l10n.protein)),
              const SizedBox(width: 8),
              Expanded(child: field(_carbs, l10n.carbs)),
              const SizedBox(width: 8),
              Expanded(child: field(_fat, l10n.fat)),
            ]),
            const SizedBox(height: 8),
            Text(l10n.unitOptional, style: Theme.of(context).textTheme.labelLarge),
            Row(children: [
              Expanded(child: TextFormField(controller: _unitName, decoration: InputDecoration(labelText: l10n.unitName, hintText: l10n.unitNameHint))),
              const SizedBox(width: 8),
              Expanded(child: field(_unitGrams, l10n.gramsPerUnit)),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: _busy ? null : _save, child: Text(l10n.save)),
      ],
    );
  }
}
