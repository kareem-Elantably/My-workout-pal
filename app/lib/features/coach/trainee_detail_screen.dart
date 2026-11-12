import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/models.dart';
import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../../data/milestone_repository.dart';
import '../admin/application_screen.dart' show formatAnswer;
import '../home/coach_home.dart';
import '../shared/notes_screen.dart';
import '../shared/plan_views.dart';
import '../shared/progress_views.dart';

final _traineeProfileProvider = FutureProvider.autoDispose.family<Profile, String>((ref, id) async {
  final row = await ref.watch(supabaseClientProvider).from('profiles').select().eq('id', id).single();
  return Profile.fromJson(row);
});

final _traineePlansProvider = FutureProvider.autoDispose.family<(WorkoutPlan?, NutritionPlan?), String>((ref, id) async {
  final results = await Future.wait<Object?>([
    ref.watch(workoutRepositoryProvider).activePlan(id),
    ref.watch(nutritionRepositoryProvider).activePlan(id),
  ]);
  return (results[0] as WorkoutPlan?, results[1] as NutritionPlan?);
});

final _answersProvider = FutureProvider.autoDispose.family<(List<QuestionStep>, Map<String, Object?>), String>((ref, id) async {
  final repo = ref.watch(onboardingRepositoryProvider);
  final results = await Future.wait([repo.loadSteps(AppRole.trainee), repo.loadAnswers(id)]);
  return (results[0] as List<QuestionStep>, results[1] as Map<String, Object?>);
});

final _recentSessionsProvider = FutureProvider.autoDispose.family<List<WorkoutSession>, String>(
  (ref, id) => ref.watch(workoutRepositoryProvider).recentSessions(id, limit: 20),
);

final _schedulesProvider = FutureProvider.autoDispose.family<List<MilestoneSchedule>, String>(
  (ref, id) => ref.watch(milestoneRepositoryProvider).schedules(id),
);

/// One trainee, for their coach: overview, plans, progress, logs, notes.
/// Arrows switch to the previous/next trainee without going back.
class TraineeDetailScreen extends ConsumerWidget {
  const TraineeDetailScreen({super.key, required this.traineeId});

  final String traineeId;

  Future<void> _sendNotification(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final title = TextEditingController();
    final body = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.sendNotification),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, autofocus: true, decoration: InputDecoration(labelText: l10n.notificationTitle)),
          const SizedBox(height: 12),
          TextField(controller: body, decoration: InputDecoration(labelText: l10n.notificationBody), maxLines: 3),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.send)),
        ],
      ),
    );
    if (send != true || title.text.trim().isEmpty) return;
    try {
      await ref.read(socialRepositoryProvider).sendCustom(traineeId, title.text, body.text);
      if (context.mounted) showMessage(context, l10n.notificationSent);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final profile = ref.watch(_traineeProfileProvider(traineeId));
    final trainees = ref.watch(coachDashboardProvider).value ?? const [];
    final index = trainees.indexWhere((t) => t.traineeId == traineeId);
    void go(int i) => context.pushReplacement('/coach/trainees/${trainees[i].traineeId}');
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(profile.value?.fullName ?? ''),
          actions: [
            if (index > 0)
              IconButton(tooltip: l10n.previousTrainee, icon: const Icon(Icons.navigate_before), onPressed: () => go(index - 1)),
            if (index >= 0 && index < trainees.length - 1)
              IconButton(tooltip: l10n.nextTrainee, icon: const Icon(Icons.navigate_next), onPressed: () => go(index + 1)),
            IconButton(
              tooltip: l10n.chat,
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () async {
                final id = await ref.read(socialRepositoryProvider).conversationWith(traineeId);
                if (id != null && context.mounted) {
                  context.push('/coach/chat/$id?name=${Uri.encodeComponent(profile.value?.fullName ?? '')}');
                }
              },
            ),
            IconButton(tooltip: l10n.sendNotification, icon: const Icon(Icons.campaign_outlined), onPressed: () => _sendNotification(context, ref)),
          ],
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: l10n.overview),
            Tab(text: l10n.workout),
            Tab(text: l10n.nutrition),
            Tab(text: l10n.progress),
            Tab(text: l10n.logs),
            Tab(text: l10n.notes),
          ]),
        ),
        body: TabBarView(children: [
          _OverviewTab(traineeId: traineeId),
          _WorkoutTab(traineeId: traineeId),
          _NutritionTab(traineeId: traineeId),
          _ProgressTab(traineeId: traineeId),
          _LogsTab(traineeId: traineeId),
          NotesList(aboutUserId: traineeId),
        ]),
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.traineeId});

  final String traineeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final status = ref.watch(coachDashboardProvider).value?.where((t) => t.traineeId == traineeId).firstOrNull;
    final profile = ref.watch(_traineeProfileProvider(traineeId)).value;
    final answers = ref.watch(_answersProvider(traineeId));
    final dob = profile?.dateOfBirth;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (status != null)
          Card(
            margin: const EdgeInsets.all(16),
            child: Column(children: [
              ListTile(
                leading: Icon(Icons.local_fire_department, color: Theme.of(context).colorScheme.tertiary),
                title: Text(l10n.streakDays(status.streak)),
              ),
              ListTile(
                leading: Icon(status.trainedToday ? Icons.check_circle : Icons.radio_button_unchecked),
                title: Text(status.trainedToday ? l10n.trainedToday : l10n.notTrainedToday),
              ),
              if (status.mealsTotalToday > 0)
                ListTile(leading: const Icon(Icons.restaurant), title: Text(l10n.mealsDone(status.mealsDoneToday, status.mealsTotalToday))),
              if (status.missedDays7 > 0) ListTile(leading: const Icon(Icons.warning_amber), title: Text(l10n.missedDays(status.missedDays7))),
              if (status.milestonesDue > 0) ListTile(leading: const Icon(Icons.monitor_weight_outlined), title: Text(l10n.milestonesDue(status.milestonesDue))),
            ]),
          ),
        if (profile != null)
          ListTile(
            title: Text(profile.fullName),
            subtitle: Text([
              profile.gender == 'female' ? l10n.female : l10n.male,
              if (dob != null) '${DateTime.now().difference(dob).inDays ~/ 365}',
              if (profile.heightCm != null) '${formatNum(profile.heightCm)} cm',
              ?profile.phone,
            ].join(' · ')),
          ),
        answers.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(errorMessage(context, e)),
          data: (result) {
            final (steps, values) = result;
            return Column(children: [
              for (final step in steps)
                ExpansionTile(
                  title: Text(step.section == null ? l10n.answers : localized(context, step.section!.titleEn, step.section!.titleAr)),
                  children: [
                    for (final q in step.questions)
                      ListTile(dense: true, title: Text(localized(context, q.textEn, q.textAr)), subtitle: Text(formatAnswer(context, q, values[q.id]))),
                  ],
                ),
            ]);
          },
        ),
      ],
    );
  }
}

/// Shared empty-state actions for a trainee without a plan.
class _NoPlan extends StatelessWidget {
  const _NoPlan({required this.title, required this.actions});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => ListView(children: [MessageView(icon: Icons.add_task, title: title, actions: actions)]);
}

class _WorkoutTab extends ConsumerWidget {
  const _WorkoutTab({required this.traineeId});

  final String traineeId;

  Future<void> _create(BuildContext context, WidgetRef ref, {bool replacing = false}) async {
    final l10n = context.l10n;
    if (replacing && !await confirm(context, l10n.replacePlanConfirm, action: l10n.newWorkoutPlan)) return;
    if (!context.mounted) return;
    final name = await promptText(context, title: l10n.newWorkoutPlan, label: l10n.planName);
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    try {
      final id = await ref.read(planEditorRepositoryProvider).createWorkoutPlan(traineeId: traineeId, name: name, cycleLength: 7);
      ref.invalidate(_traineePlansProvider(traineeId));
      if (context.mounted) await context.push('/coach/workout-plans/$id');
      ref.invalidate(_traineePlansProvider(traineeId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _fromTemplate(BuildContext context, WidgetRef ref) async {
    final templates = await ref.read(planEditorRepositoryProvider).workoutTemplates();
    if (!context.mounted) return;
    final chosen = await _chooseTemplate<WorkoutPlan>(context, templates, (t) => t.name);
    if (chosen == null || !context.mounted) return;
    try {
      final id = await ref.read(planEditorRepositoryProvider).applyWorkoutTemplate(chosen, traineeId);
      ref.invalidate(_traineePlansProvider(traineeId));
      if (context.mounted) await context.push('/coach/workout-plans/$id');
      ref.invalidate(_traineePlansProvider(traineeId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final plans = ref.watch(_traineePlansProvider(traineeId));
    final actions = [
      FilledButton.icon(icon: const Icon(Icons.add), label: Text(l10n.newWorkoutPlan), onPressed: () => _create(context, ref)),
      OutlinedButton.icon(icon: const Icon(Icons.copy_all), label: Text(l10n.fromTemplate), onPressed: () => _fromTemplate(context, ref)),
      OutlinedButton.icon(
        icon: const Icon(Icons.upload_file),
        label: Text(l10n.uploadExcel),
        onPressed: () async {
          await context.push('/coach/import?trainee=$traineeId');
          ref.invalidate(_traineePlansProvider(traineeId));
        },
      ),
    ];
    return AsyncBody(
      value: plans,
      onRetry: () => ref.invalidate(_traineePlansProvider(traineeId)),
      builder: (p) {
        final plan = p.$1;
        final version = plan?.versionOn(today()) ?? plan?.latest;
        if (plan == null || version == null) return _NoPlan(title: l10n.noWorkoutPlan, actions: actions);
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'edit-workout',
            icon: const Icon(Icons.edit),
            label: Text(l10n.editPlan),
            onPressed: () async {
              await context.push('/coach/workout-plans/${plan.id}');
              ref.invalidate(_traineePlansProvider(traineeId));
            },
          ),
          body: WorkoutVersionView(
            version: version,
            header: Column(children: [
              ListTile(
                title: Text(plan.name, style: Theme.of(context).textTheme.titleLarge),
                subtitle: Text(l10n.versionFrom(version.versionNo, DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(version.effectiveFrom))),
              ),
              Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(l10n.newWorkoutPlan),
                  onPressed: () => _create(context, ref, replacing: true),
                ),
                actions[1],
                actions[2],
              ]),
            ]),
          ),
        );
      },
    );
  }
}

class _NutritionTab extends ConsumerWidget {
  const _NutritionTab({required this.traineeId});

  final String traineeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final plans = ref.watch(_traineePlansProvider(traineeId));
    Future<void> open(String id) async {
      await context.push('/coach/nutrition-plans/$id');
      ref.invalidate(_traineePlansProvider(traineeId));
    }

    final actions = [
      FilledButton.icon(
        icon: const Icon(Icons.add),
        label: Text(l10n.newNutritionPlan),
        onPressed: () async {
          final name = await promptText(context, title: l10n.newNutritionPlan, label: l10n.planName);
          if (name == null || name.trim().isEmpty) return;
          try {
            await open(await ref.read(planEditorRepositoryProvider).createNutritionPlan(traineeId: traineeId, name: name));
          } catch (e) {
            if (context.mounted) showError(context, e);
          }
        },
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.copy_all),
        label: Text(l10n.fromTemplate),
        onPressed: () async {
          final templates = await ref.read(planEditorRepositoryProvider).nutritionTemplates();
          if (!context.mounted) return;
          final chosen = await _chooseTemplate<NutritionPlan>(context, templates, (t) => t.name);
          if (chosen == null) return;
          try {
            await open(await ref.read(planEditorRepositoryProvider).applyNutritionTemplate(chosen, traineeId));
          } catch (e) {
            if (context.mounted) showError(context, e);
          }
        },
      ),
    ];
    return AsyncBody(
      value: plans,
      onRetry: () => ref.invalidate(_traineePlansProvider(traineeId)),
      builder: (p) {
        final plan = p.$2;
        final version = plan?.versionOn(today()) ?? plan?.latest;
        if (plan == null || version == null) return _NoPlan(title: l10n.noNutritionPlan, actions: actions);
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'edit-nutrition',
            icon: const Icon(Icons.edit),
            label: Text(l10n.editPlan),
            onPressed: () => open(plan.id),
          ),
          body: NutritionVersionView(
            version: version,
            showMacros: true,
            header: Column(children: [
              ListTile(title: Text(plan.name, style: Theme.of(context).textTheme.titleLarge)),
              actions[1],
            ]),
          ),
        );
      },
    );
  }
}

Future<T?> _chooseTemplate<T>(BuildContext context, List<T> templates, String Function(T) name) => showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: templates.isEmpty
            ? Padding(padding: const EdgeInsets.all(24), child: Text(context.l10n.noTemplates))
            : ListView(shrinkWrap: true, children: [
                for (final t in templates) ListTile(title: Text(name(t)), onTap: () => Navigator.pop(context, t)),
              ]),
      ),
    );

class _ProgressTab extends ConsumerWidget {
  const _ProgressTab({required this.traineeId});

  final String traineeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'checkins',
        icon: const Icon(Icons.event_repeat),
        label: Text(l10n.checkInSchedules),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: _SchedulesSheet(traineeId: traineeId)),
        ),
      ),
      body: ProgressView(traineeId: traineeId, isCoach: true),
    );
  }
}

/// Repeating check-in schedules plus "ask for a check-in now".
class _SchedulesSheet extends ConsumerWidget {
  const _SchedulesSheet({required this.traineeId});

  final String traineeId;

  Future<void> _add(BuildContext context, WidgetRef ref, {required bool oneOff}) async {
    final fields = await ref.read(milestoneRepositoryProvider).fields();
    if (!context.mounted) return;
    final result = await showDialog<(String, int, Map<int, bool>)>(
      context: context,
      builder: (_) => _CheckInDialog(fields: fields, oneOff: oneOff),
    );
    if (result == null) return;
    final (name, days, chosen) = result;
    try {
      final repo = ref.read(milestoneRepositoryProvider);
      oneOff
          ? await repo.addOneOff(traineeId: traineeId, title: name, dueDate: today(), fields: chosen)
          : await repo.addSchedule(traineeId: traineeId, name: name, everyNDays: days, startsOn: today(), fields: chosen);
      ref.invalidate(_schedulesProvider(traineeId));
      ref.invalidate(milestonesProvider(traineeId));
      if (context.mounted) showMessage(context, oneOff ? context.l10n.checkInRequested : context.l10n.scheduleSaved);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final schedules = ref.watch(_schedulesProvider(traineeId));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(l10n.checkInSchedules, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        FilledButton.icon(icon: const Icon(Icons.add_alert), label: Text(l10n.askForCheckInNow), onPressed: () => _add(context, ref, oneOff: true)),
        const SizedBox(height: 8),
        OutlinedButton.icon(icon: const Icon(Icons.event_repeat), label: Text(l10n.addSchedule), onPressed: () => _add(context, ref, oneOff: false)),
        const SizedBox(height: 16),
        ...schedules.when(
          loading: () => [const LinearProgressIndicator()],
          error: (e, _) => [Text(errorMessage(context, e))],
          data: (list) => [
            for (final s in list)
              SwitchListTile(
                title: Text(s.name),
                subtitle: Text('${l10n.everyNDays(s.everyNDays)} · ${s.fields.map((f) => f.$1.label(context)).join(', ')}'),
                value: s.isActive,
                onChanged: (on) async {
                  await ref.read(milestoneRepositoryProvider).setScheduleActive(s.id, on);
                  ref.invalidate(_schedulesProvider(traineeId));
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _CheckInDialog extends StatefulWidget {
  const _CheckInDialog({required this.fields, required this.oneOff});

  final List<MilestoneField> fields;
  final bool oneOff;

  @override
  State<_CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends State<_CheckInDialog> {
  late final _name = TextEditingController(text: widget.oneOff ? null : 'Weekly check-in');
  int _days = 7;
  late final Map<int, bool?> _fields = {for (final f in widget.fields) f.id: f.key == 'weight' ? true : null};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.oneOff ? l10n.askForCheckInNow : l10n.addSchedule),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name, decoration: InputDecoration(labelText: l10n.checkInName)),
          if (!widget.oneOff)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.everyNDays(_days)),
              trailing: NumberStepper(value: _days, min: 1, max: 60, onChanged: (v) => setState(() => _days = v.toInt())),
            ),
          for (final f in widget.fields)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              tristate: true,
              title: Text(f.label(context)),
              subtitle: Text(switch (_fields[f.id]) { true => l10n.required, false => l10n.optional, null => l10n.notAsked }),
              value: _fields[f.id],
              onChanged: (_) => setState(() => _fields[f.id] = switch (_fields[f.id]) { null => true, true => false, false => null }),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: () {
            final chosen = {for (final e in _fields.entries) if (e.value != null) e.key: e.value!};
            if (_name.text.trim().isEmpty || chosen.isEmpty) return;
            Navigator.pop(context, (_name.text.trim(), _days, chosen));
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _LogsTab extends ConsumerWidget {
  const _LogsTab({required this.traineeId});

  final String traineeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final sessions = ref.watch(_recentSessionsProvider(traineeId));
    final plans = ref.watch(_traineePlansProvider(traineeId)).value;
    final format = DateFormat.MMMEd(Localizations.localeOf(context).toString());
    final dayNames = {
      for (final v in plans?.$1?.versions ?? const <WorkoutVersion>[])
        for (final d in v.days) d.id: d,
    };
    final exercises = {
      for (final d in dayNames.values)
        for (final e in d.exercises) e.id: e,
    };
    return AsyncBody(
      value: sessions,
      onRetry: () => ref.invalidate(_recentSessionsProvider(traineeId)),
      builder: (list) => list.isEmpty
          ? EmptyList(icon: Icons.history, title: l10n.noWorkoutsYet)
          : ListView(
              children: [
                for (final s in list)
                  ExpansionTile(
                    title: Text('${format.format(s.date)} · ${dayNames[s.workoutDayId]?.name ?? ''}'),
                    subtitle: Text(l10n.setsLogged(s.sets.length)),
                    children: [
                      for (final set in (s.sets.toList()..sort((a, b) => a.setNumber.compareTo(b.setNumber))))
                        ListTile(
                          dense: true,
                          title: Text(exercises[set.dayExerciseId]?.exercise.name(context) ?? ''),
                          trailing: Text(
                            [
                              if (set.weightKg != null) '${formatNum(set.weightKg)} ${l10n.kg}',
                              if (set.reps != null) '× ${set.reps}',
                              if (set.distanceM != null) '${formatNum(set.distanceM)} m',
                              if (set.durationSeconds != null) '${set.durationSeconds} ${l10n.secondsShort}',
                            ].join('  '),
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                      if (s.note != null) ListTile(dense: true, title: Text(s.note!)),
                    ],
                  ),
              ],
            ),
    );
  }
}
