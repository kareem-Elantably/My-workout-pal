import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../../data/milestone_repository.dart';
import '../../data/workout_repository.dart';
import '../shared/notifications_button.dart';
import 'water_card.dart';

class TodayData {
  const TodayData({
    required this.day,
    required this.workoutPlan,
    required this.nutritionPlan,
    required this.session,
    required this.mealLogs,
    required this.milestones,
    required this.next,
    required this.streak,
  });

  final DateTime day;
  final WorkoutPlan? workoutPlan;
  final NutritionPlan? nutritionPlan;
  final WorkoutSession? session;
  final List<MealLog> mealLogs;
  final List<Milestone> milestones;

  /// Only for today: the suggested workout and the streak.
  final NextWorkout? next;
  final int streak;

  bool get isToday => day == today();

  NutritionVersion? get nutritionVersion => nutritionPlan?.versionOn(day);

  WorkoutDay? dayById(String id) {
    for (final version in workoutPlan?.versions ?? const <WorkoutVersion>[]) {
      for (final d in version.days) {
        if (d.id == id) return d;
      }
    }
    return null;
  }
}

final todayDataProvider = FutureProvider.autoDispose.family<TodayData, DateTime>((ref, day) async {
  final me = ref.watch(myIdProvider);
  final workout = ref.watch(workoutRepositoryProvider);
  final nutrition = ref.watch(nutritionRepositoryProvider);
  final isToday = day == today();
  final results = await Future.wait<Object?>([
    workout.activePlan(me),
    nutrition.activePlan(me),
    workout.sessionOn(me, day),
    nutrition.logsOn(me, day),
    ref.watch(milestoneRepositoryProvider).forTrainee(me),
    if (isToday) workout.nextWorkout(me) else Future.value(),
    if (isToday) workout.streak(me) else Future.value(0),
  ]);
  return TodayData(
    day: day,
    workoutPlan: results[0] as WorkoutPlan?,
    nutritionPlan: results[1] as NutritionPlan?,
    session: results[2] as WorkoutSession?,
    mealLogs: results[3] as List<MealLog>,
    milestones: results[4] as List<Milestone>,
    next: results[5] as NextWorkout?,
    streak: results[6] as int,
  );
});

/// Trainee home = today: workout, meals, streak and any check-in due.
/// Arrows go back up to 7 days, the window in which logs can be changed.
class TodayTab extends ConsumerStatefulWidget {
  const TodayTab({super.key});

  @override
  ConsumerState<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends ConsumerState<TodayTab> {
  late DateTime _day = today();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final data = ref.watch(todayDataProvider(_day));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.today),
        actions: const [NotificationsButton(), ProfileButton()],
      ),
      body: Column(
        children: [
          DateBar(
            day: _day,
            first: today().subtract(const Duration(days: 7)),
            last: today(),
            onChanged: (day) => setState(() => _day = day),
          ),
          Expanded(
            child: AsyncBody(
              value: data,
              onRetry: () => ref.invalidate(todayDataProvider(_day)),
              builder: (d) => RefreshIndicator(
                onRefresh: () {
                ref.invalidate(waterProvider(_day));
                return ref.refresh(todayDataProvider(_day).future);
              },
                child: d.workoutPlan == null && d.nutritionPlan == null
                    ? EmptyList(icon: Icons.construction_outlined, title: l10n.preparingTitle, body: l10n.preparingBody)
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (d.isToday) _StreakCard(streak: d.streak),
                          for (final m in d.milestones)
                            if (d.isToday && m.submittedAt == null && !m.dueDate.isAfter(_day)) _MilestoneDueCard(milestone: m),
                          _WorkoutSection(data: d),
                          if (d.nutritionVersion != null) _MealsSection(data: d),
                          WaterCard(day: _day),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final milestone = const [100, 30, 7].where((m) => streak >= m).firstOrNull;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      color: theme.colorScheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.local_fire_department, color: theme.colorScheme.tertiary, size: 36),
        title: Text(context.l10n.streakDays(streak), style: theme.textTheme.titleLarge),
        subtitle: milestone == null ? null : Text(context.l10n.streakMilestone(milestone)),
      ),
    );
  }
}

class _MilestoneDueCard extends StatelessWidget {
  const _MilestoneDueCard({required this.milestone});

  final Milestone milestone;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: ListTile(
          leading: const Icon(Icons.monitor_weight_outlined),
          title: Text(context.l10n.checkInDue),
          subtitle: Text(milestone.name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/trainee/milestone/${milestone.id}'),
        ),
      );
}

class _WorkoutSection extends ConsumerWidget {
  const _WorkoutSection({required this.data});

  final TodayData data;

  void _open(BuildContext context, String workoutDayId) =>
      context.push('/trainee/workout?day=$workoutDayId&date=${isoDate(data.day)}');

  Future<void> _chooseDay(BuildContext context) async {
    final version = data.workoutPlan?.versionOn(data.day);
    if (version == null) return;
    final chosen = await showModalBottomSheet<WorkoutDay>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(context.l10n.chooseWorkoutDay, style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final day in version.days)
              ListTile(
                leading: CircleAvatar(child: Text('${day.dayNumber}')),
                title: Text(day.name),
                subtitle: Text(context.l10n.exerciseCount(day.exercises.length)),
                onTap: () => Navigator.pop(context, day),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && context.mounted) _open(context, chosen.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    if (data.workoutPlan == null) {
      return SectionTitle(l10n.workoutPlanPreparing);
    }
    final session = data.session;
    final loggedDay = session == null ? null : data.dayById(session.workoutDayId);
    final next = data.next;
    final suggested = next?.workoutDayId == null ? null : data.dayById(next!.workoutDayId!);

    Widget card;
    if (session != null && loggedDay != null) {
      card = ListTile(
        leading: Icon(session.completedAt != null ? Icons.check_circle : Icons.timelapse, color: theme.colorScheme.tertiary),
        title: Text('${l10n.dayNumber(loggedDay.dayNumber)} · ${loggedDay.name}'),
        subtitle: Text(session.completedAt != null ? l10n.workoutDone : l10n.workoutInProgress),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(context, loggedDay.id),
      );
    } else if (data.isToday && next != null && !next.isPlannedRest && suggested != null) {
      card = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${l10n.dayNumber(suggested.dayNumber)} · ${suggested.name}', style: theme.textTheme.titleLarge),
            Text(l10n.exerciseCount(suggested.exercises.length), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.startWorkout),
              onPressed: () => _open(context, suggested.id),
            ),
            TextButton(onPressed: () => _chooseDay(context), child: Text(l10n.chooseAnotherDay)),
          ],
        ),
      );
    } else {
      // Planned rest today, or a past day with nothing logged.
      card = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.bedtime_outlined),
              const SizedBox(width: 12),
              Text(data.isToday ? l10n.plannedRest : l10n.restDay, style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _chooseDay(context),
              child: Text(data.isToday ? l10n.trainAnyway : l10n.logWorkoutForDay),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(l10n.todayWorkout),
        Card(margin: const EdgeInsets.symmetric(horizontal: 16), child: card),
      ],
    );
  }
}

class _MealsSection extends ConsumerWidget {
  const _MealsSection({required this.data});

  final TodayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final version = data.nutritionVersion!;
    final logs = {for (final log in data.mealLogs) log.mealId: log};
    final allDone = version.meals.every((m) => logs.containsKey(m.id));
    final me = ref.watch(myIdProvider);
    final repo = ref.read(nutritionRepositoryProvider);

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
        ref.invalidate(todayDataProvider(data.day));
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          l10n.meals,
          trailing: allDone
              ? Chip(avatar: const Icon(Icons.check, size: 18), label: Text(l10n.allMealsDone))
              : TextButton.icon(
                  icon: const Icon(Icons.done_all),
                  label: Text(l10n.markAllMealsDone),
                  onPressed: () => run(() => repo.logAll(traineeId: me, meals: version.meals, existing: data.mealLogs, day: data.day)),
                ),
        ),
        for (final meal in version.meals)
          _MealCard(
            meal: meal,
            log: logs[meal.id],
            showMacros: data.nutritionPlan!.showMacros,
            onSelect: (option) => run(() => repo.logMeal(
                  traineeId: me,
                  mealId: meal.id,
                  day: data.day,
                  optionId: option?.id,
                  changeNote: logs[meal.id]?.changeNote,
                )),
            onUndo: (log) => run(() => repo.unlogMeal(log.id)),
            onNote: (log, note) => run(() => repo.logMeal(
                  traineeId: me,
                  mealId: meal.id,
                  day: data.day,
                  optionId: log.optionId,
                  changeNote: note,
                )),
          ),
      ],
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.meal,
    required this.log,
    required this.showMacros,
    required this.onSelect,
    required this.onUndo,
    required this.onNote,
  });

  final Meal meal;
  final MealLog? log;
  final bool showMacros;
  final ValueChanged<MealOption?> onSelect;
  final ValueChanged<MealLog> onUndo;
  final void Function(MealLog log, String note) onNote;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final done = log != null;
    final selected = meal.options.where((o) => o.id == log?.optionId).firstOrNull ??
        (meal.options.length == 1 ? meal.options.first : null);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: done,
                  onChanged: (checked) => checked == true ? onSelect(selected) : onUndo(log!),
                ),
                Expanded(
                  child: Text(
                    [meal.name, if (meal.timeHint != null) meal.timeHint!].join(' · '),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (!meal.countsForStreak) Text(l10n.optional, style: theme.textTheme.labelSmall),
              ],
            ),
            if (meal.options.length > 1)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final option in meal.options)
                      ChoiceChip(
                        label: Text(option.label),
                        selected: option.id == log?.optionId,
                        onSelected: (_) => onSelect(option),
                      ),
                  ],
                ),
              ),
            if (selected != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 12, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in selected.items)
                      Text('• ${item.food.name(context)} — ${item.amount(context)}', style: theme.textTheme.bodyMedium),
                    if (showMacros) Padding(padding: const EdgeInsets.only(top: 4), child: MacrosLine(selected.macros)),
                  ],
                ),
              ),
            if (done)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: TextButton.icon(
                  icon: Icon(log!.changeNote == null ? Icons.edit_note : Icons.sticky_note_2_outlined, size: 18),
                  label: Text(log!.changeNote ?? l10n.didYouChangeAnything, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onPressed: () async {
                    final note = await promptText(context, title: l10n.didYouChangeAnything, initial: log!.changeNote, multiline: true);
                    if (note != null) onNote(log!, note);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
