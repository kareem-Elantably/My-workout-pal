import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../shared/new_food.dart';
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
                  () => setState(() { _results = ref.read(libraryRepositoryProvider).searchExercises(q); }));
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

  void _reload() => setState(() { _results = ref.read(libraryRepositoryProvider).searchFoods(_query); });

  Future<void> _scan() async {
    if (await scanFood(context, ref) != null) _reload();
  }

  Future<void> _addFood() async {
    if (await addNewFood(context, name: _query) != null) _reload();
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
