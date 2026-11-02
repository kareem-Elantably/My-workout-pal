import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import 'exercise_picker.dart';

final workoutPlanProvider = FutureProvider.autoDispose.family<(WorkoutPlan, bool), String>((ref, planId) async {
  final plan = await ref.watch(workoutRepositoryProvider).plan(planId);
  final frozen = plan.latest == null ? false : await ref.watch(planEditorRepositoryProvider).workoutVersionFrozen(plan.latest!);
  return (plan, frozen);
});

/// Builds a workout plan (a trainee's or a template): the cycle, its
/// training days and their exercises. A version with logs is read-only;
/// "new version" copies it to edit from today on.
class WorkoutEditorScreen extends ConsumerWidget {
  const WorkoutEditorScreen({super.key, required this.planId});

  final String planId;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(workoutPlanProvider(planId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final data = ref.watch(workoutPlanProvider(planId));
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
                    await _run(context, ref, () => repo.renameWorkoutPlan(planId, name));
                  }
                } else if (action == 'template' && plan.latest != null) {
                  final name = await promptText(context, title: l10n.saveAsTemplate, initial: plan.name);
                  if (name != null && name.trim().isNotEmpty && context.mounted) {
                    await _run(context, ref, () => repo.saveWorkoutAsTemplate(plan, plan.latest!, name));
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
      body: AsyncBody(
        value: data,
        onRetry: () => ref.invalidate(workoutPlanProvider(planId)),
        builder: (d) {
          final (plan, frozen) = d;
          final version = plan.latest;
          if (version == null) return const SizedBox.shrink();
          return ListView(
            padding: const EdgeInsets.only(bottom: 48),
            children: [
              if (frozen)
                MaterialBanner(
                  content: Text(l10n.versionHasLogs),
                  leading: const Icon(Icons.lock_outline),
                  actions: [
                    TextButton(
                      onPressed: () => _run(context, ref, () => repo.copyWorkoutVersion(version.id, plan.id)),
                      child: Text(l10n.newVersion),
                    ),
                  ],
                ),
              ListTile(
                title: Text(l10n.cycleLength),
                subtitle: Text(l10n.cycleLengthHint),
                trailing: NumberStepper(
                  value: version.cycleLength,
                  min: [1, ...version.days.map((d) => d.dayNumber)].reduce((a, b) => a > b ? a : b),
                  max: 28,
                  onChanged: frozen ? (_) {} : (v) => _run(context, ref, () => repo.setCycleLength(version.id, v.toInt())),
                ),
              ),
              for (var n = 1; n <= version.cycleLength; n++)
                switch (version.dayByNumber(n)) {
                  final day? => _DayCard(day: day, frozen: frozen, run: (a) => _run(context, ref, a)),
                  null => ListTile(
                      leading: CircleAvatar(child: Text('$n')),
                      title: Text(l10n.restDay),
                      trailing: frozen
                          ? null
                          : TextButton.icon(
                              icon: const Icon(Icons.add),
                              label: Text(l10n.addTrainingDay),
                              onPressed: () async {
                                final name = await promptText(context, title: l10n.dayName, label: l10n.dayNameHint);
                                if (name != null && name.trim().isNotEmpty && context.mounted) {
                                  await _run(context, ref, () => repo.addDay(version.id, n, name));
                                }
                              },
                            ),
                    ),
                },
            ],
          );
        },
      ),
    );
  }
}

class _DayCard extends ConsumerWidget {
  const _DayCard({required this.day, required this.frozen, required this.run});

  final WorkoutDay day;
  final bool frozen;
  final Future<void> Function(Future<void> Function() action) run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final repo = ref.read(planEditorRepositoryProvider);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: CircleAvatar(child: Text('${day.dayNumber}')),
            title: Text(day.name, style: Theme.of(context).textTheme.titleMedium),
            trailing: frozen
                ? null
                : PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'rename') {
                        final name = await promptText(context, title: l10n.dayName, initial: day.name);
                        if (name != null && name.trim().isNotEmpty) await run(() => repo.renameDay(day.id, name));
                      } else if (context.mounted && await confirm(context, l10n.deleteDayConfirm, action: l10n.delete)) {
                        await run(() => repo.deleteDay(day.id));
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
                      PopupMenuItem(value: 'delete', child: Text(l10n.makeRestDay)),
                    ],
                  ),
          ),
          for (var i = 0; i < day.exercises.length; i++)
            ListTile(
              dense: true,
              title: Text(day.exercises[i].exercise.name(context)),
              subtitle: Text([
                day.exercises[i].target(),
                if (day.exercises[i].restSeconds != null) l10n.restSeconds(day.exercises[i].restSeconds!),
                if (day.exercises[i].supersetGroup != null) l10n.superset(day.exercises[i].supersetGroup!),
              ].join(' · ')),
              onTap: frozen
                  ? null
                  : () async {
                      final edited = await editDayExercise(context,
                          exercise: day.exercises[i].exercise, current: day.exercises[i], sortOrder: day.exercises[i].sortOrder);
                      if (edited != null) await run(() => repo.saveDayExercise(day.id, edited, id: day.exercises[i].id));
                    },
              trailing: frozen
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: l10n.moveUp,
                        icon: const Icon(Icons.arrow_upward, size: 20),
                        onPressed: i == 0
                            ? null
                            : () => run(() => repo.reorderDayExercises([...day.exercises]..insert(i - 1, day.exercises[i])..removeAt(i + 1))),
                      ),
                      IconButton(
                        tooltip: l10n.delete,
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => run(() => repo.deleteDayExercise(day.exercises[i].id)),
                      ),
                    ]),
            ),
          if (!frozen)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(l10n.addExercise),
                onPressed: () async {
                  final exercise = await pickExercise(context);
                  if (exercise == null || !context.mounted) return;
                  final row = await editDayExercise(context, exercise: exercise, sortOrder: day.exercises.length + 1);
                  if (row != null) await run(() => repo.saveDayExercise(day.id, row));
                },
              ),
            ),
        ],
      ),
    );
  }
}
