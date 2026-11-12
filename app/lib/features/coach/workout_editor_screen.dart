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

/// One change to the plan, applied to the version being edited.
typedef WorkoutEdit = Future<void> Function(WorkoutVersion version);

/// Builds and edits a workout plan (a trainee's or a template): the cycle,
/// its training days and their exercises. Everything is editable here; the
/// Excel upload is only a shortcut.
///
/// Past workouts must keep pointing at what the trainee actually did, so
/// once they have logged against a version the first edit quietly copies
/// it into a new version from today and applies the change there.
class WorkoutEditorScreen extends ConsumerStatefulWidget {
  const WorkoutEditorScreen({super.key, required this.planId});

  final String planId;

  @override
  ConsumerState<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends ConsumerState<WorkoutEditorScreen> {
  bool _busy = false;

  Future<void> _edit(WorkoutEdit edit) async {
    final data = ref.read(workoutPlanProvider(widget.planId)).value;
    if (_busy || data == null) return;
    setState(() => _busy = true);
    try {
      final (plan, frozen) = data;
      var version = plan.latest!;
      if (frozen) {
        await ref.read(planEditorRepositoryProvider).copyWorkoutVersion(version.id, plan.id);
        version = (await ref.read(workoutRepositoryProvider).plan(plan.id)).latest!;
        if (mounted) showMessage(context, context.l10n.editSavedAsNewVersion);
      }
      await edit(version);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      ref.invalidate(workoutPlanProvider(widget.planId));
      // Wait for the fresh plan so the next tap edits what's on screen.
      try {
        await ref.read(workoutPlanProvider(widget.planId).future);
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _planAction(String action, WorkoutPlan plan) async {
    final l10n = context.l10n;
    final repo = ref.read(planEditorRepositoryProvider);
    if (action == 'rename') {
      final name = await promptText(context, title: l10n.renamePlan, initial: plan.name);
      if (name == null || name.trim().isEmpty) return;
      try {
        await repo.renameWorkoutPlan(plan.id, name);
      } catch (e) {
        if (mounted) showError(context, e);
      }
      ref.invalidate(workoutPlanProvider(widget.planId));
    } else if (action == 'template' && plan.latest != null) {
      final name = await promptText(context, title: l10n.saveAsTemplate, initial: plan.name);
      if (name == null || name.trim().isEmpty) return;
      try {
        await repo.saveWorkoutAsTemplate(plan, plan.latest!, name);
        if (mounted) showMessage(context, l10n.templateSaved);
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

  Future<void> _addDay(int dayNumber) async {
    final l10n = context.l10n;
    final name = await promptText(context, title: l10n.dayName, label: l10n.dayNameHint);
    if (name == null || name.trim().isEmpty) return;
    await _edit((v) async {
      await ref.read(planEditorRepositoryProvider).addDay(v.id, dayNumber, name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final data = ref.watch(workoutPlanProvider(widget.planId));
    final plan = data.value?.$1;
    return Scaffold(
      appBar: AppBar(
        title: Text(plan?.name ?? ''),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
        actions: [
          if (plan != null)
            PopupMenuButton<String>(
              onSelected: (action) => _planAction(action, plan),
              itemBuilder: (context) => [
                PopupMenuItem(value: 'rename', child: Text(l10n.renamePlan)),
                if (plan.traineeId != null) PopupMenuItem(value: 'template', child: Text(l10n.saveAsTemplate)),
              ],
            ),
        ],
      ),
      body: AsyncBody(
        value: data,
        onRetry: () => ref.invalidate(workoutPlanProvider(widget.planId)),
        builder: (d) {
          final (plan, _) = d;
          final version = plan.latest;
          if (version == null) return const SizedBox.shrink();
          final repo = ref.read(planEditorRepositoryProvider);
          final restDays = [
            for (var n = 1; n <= version.cycleLength; n++)
              if (version.dayByNumber(n) == null) n,
          ];
          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 48),
              children: [
                ListTile(
                  title: Text(l10n.cycleLength),
                  subtitle: Text(l10n.cycleLengthHint),
                  trailing: NumberStepper(
                    value: version.cycleLength,
                    min: [1, ...version.days.map((d) => d.dayNumber)].reduce((a, b) => a > b ? a : b),
                    max: 28,
                    onChanged: (n) => _edit((v) => repo.setCycleLength(v.id, n.toInt())),
                  ),
                ),
                if (version.days.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(l10n.workoutEditorEmptyHint, style: Theme.of(context).textTheme.bodyMedium),
                  ),
                for (var n = 1; n <= version.cycleLength; n++)
                  switch (version.dayByNumber(n)) {
                    final day? => _DayCard(day: day, restDays: restDays, edit: _edit),
                    null => ListTile(
                        leading: CircleAvatar(child: Text('$n')),
                        title: Text(l10n.restDay),
                        trailing: TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: Text(l10n.addTrainingDay),
                          onPressed: () => _addDay(n),
                        ),
                      ),
                  },
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A training day. Changes find the day again by its number and the
/// exercise by its position, so they still apply after a new version.
class _DayCard extends ConsumerWidget {
  const _DayCard({required this.day, required this.restDays, required this.edit});

  final WorkoutDay day;
  final List<int> restDays;
  final Future<void> Function(WorkoutEdit edit) edit;

  WorkoutDay _dayIn(WorkoutVersion v) => v.dayByNumber(day.dayNumber)!;

  Future<int?> _pickRestDay(BuildContext context, String title) => showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            for (final n in restDays)
              ListTile(
                leading: CircleAvatar(child: Text('$n')),
                title: Text(context.l10n.dayNumber(n)),
                onTap: () => Navigator.pop(context, n),
              ),
          ]),
        ),
      );

  Future<void> _dayAction(BuildContext context, WidgetRef ref, String action) async {
    final l10n = context.l10n;
    final repo = ref.read(planEditorRepositoryProvider);
    switch (action) {
      case 'rename':
        final name = await promptText(context, title: l10n.dayName, initial: day.name);
        if (name != null && name.trim().isNotEmpty) await edit((v) => repo.renameDay(_dayIn(v).id, name));
      case 'move':
        final n = await _pickRestDay(context, l10n.moveDayTo);
        if (n != null) await edit((v) => repo.moveDay(_dayIn(v).id, n));
      case 'duplicate':
        final n = await _pickRestDay(context, l10n.duplicateDayTo);
        if (n != null) await edit((v) => repo.duplicateDay(v.id, _dayIn(v), n, day.name));
      case 'delete':
        if (await confirm(context, l10n.deleteDayConfirm, action: l10n.makeRestDay)) {
          await edit((v) => repo.deleteDay(_dayIn(v).id));
        }
    }
  }

  Future<void> _exerciseAction(BuildContext context, WidgetRef ref, int i, String action) async {
    final repo = ref.read(planEditorRepositoryProvider);
    List<DayExercise> moved(WorkoutVersion v, int to) =>
        [..._dayIn(v).exercises]..insert(to, _dayIn(v).exercises[i])..removeAt(to < i ? i + 1 : i);
    switch (action) {
      case 'up':
        await edit((v) => repo.reorderDayExercises(moved(v, i - 1)));
      case 'down':
        await edit((v) => repo.reorderDayExercises(moved(v, i + 2)));
      case 'swap':
        final exercise = await pickExercise(context);
        if (exercise == null || !context.mounted) return;
        final current = day.exercises[i];
        final row = await editDayExercise(context, exercise: exercise, current: current, sortOrder: current.sortOrder);
        if (row != null) await edit((v) => repo.saveDayExercise(_dayIn(v).id, row, id: _dayIn(v).exercises[i].id));
      case 'duplicate':
        await edit((v) => repo.duplicateDayExercise(_dayIn(v), i));
      case 'delete':
        await edit((v) => repo.deleteDayExercise(_dayIn(v).exercises[i].id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final repo = ref.read(planEditorRepositoryProvider);
    final exercises = day.exercises;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: CircleAvatar(child: Text('${day.dayNumber}')),
            title: Text(day.name, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(l10n.exerciseCount(exercises.length)),
            trailing: PopupMenuButton<String>(
              tooltip: l10n.dayOptions,
              onSelected: (action) => _dayAction(context, ref, action),
              itemBuilder: (context) => [
                PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
                if (restDays.isNotEmpty) ...[
                  PopupMenuItem(value: 'move', child: Text(l10n.moveDayTo)),
                  PopupMenuItem(value: 'duplicate', child: Text(l10n.duplicateDayTo)),
                ],
                PopupMenuItem(value: 'delete', child: Text(l10n.makeRestDay)),
              ],
            ),
          ),
          for (var i = 0; i < exercises.length; i++)
            ListTile(
              dense: true,
              title: Text(exercises[i].exercise.name(context)),
              subtitle: Text([
                exercises[i].target(),
                if (exercises[i].restSeconds != null) l10n.restSeconds(exercises[i].restSeconds!),
                if (exercises[i].supersetGroup != null) l10n.superset(exercises[i].supersetGroup!),
              ].join(' · ')),
              // Tap to change sets, reps, rest, notes...
              onTap: () async {
                final edited = await editDayExercise(context,
                    exercise: exercises[i].exercise, current: exercises[i], sortOrder: exercises[i].sortOrder);
                if (edited != null) await edit((v) => repo.saveDayExercise(_dayIn(v).id, edited, id: _dayIn(v).exercises[i].id));
              },
              trailing: PopupMenuButton<String>(
                tooltip: l10n.exerciseOptions,
                onSelected: (action) => _exerciseAction(context, ref, i, action),
                itemBuilder: (context) => [
                  if (i > 0) PopupMenuItem(value: 'up', child: Text(l10n.moveUp)),
                  if (i < exercises.length - 1) PopupMenuItem(value: 'down', child: Text(l10n.moveDown)),
                  PopupMenuItem(value: 'swap', child: Text(l10n.swapExercise)),
                  PopupMenuItem(value: 'duplicate', child: Text(l10n.duplicate)),
                  PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                ],
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(l10n.addExercise),
              onPressed: () async {
                final exercise = await pickExercise(context);
                if (exercise == null || !context.mounted) return;
                final row = await editDayExercise(context, exercise: exercise, sortOrder: exercises.length + 1);
                if (row != null) await edit((v) => repo.saveDayExercise(_dayIn(v).id, row));
              },
            ),
          ),
        ],
      ),
    );
  }
}
