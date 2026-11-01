import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../data/home_repository.dart';
import '../../router/redirect.dart';

final todayProvider = FutureProvider.autoDispose<TodaySummary>((ref) {
  final session = ref.watch(sessionProvider).requireValue as SignedIn;
  return ref.watch(homeRepositoryProvider).today(session.data.userId);
});

/// Trainee home = today: the suggested workout and the streak. Logging comes
/// in the next round; until a coach builds a plan this shows "preparing".
class TraineeHome extends ConsumerWidget {
  const TraineeHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.today),
        actions: [IconButton(icon: const Icon(Icons.person_outline), onPressed: () => context.push(Routes.profile))],
      ),
      body: today.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(todayProvider)),
        data: (summary) => RefreshIndicator(
          onRefresh: () => ref.refresh(todayProvider.future),
          child: summary.hasPlan
              ? _Today(summary: summary)
              : ListView(children: [
                  MessageView(icon: Icons.construction_outlined, title: l10n.preparingTitle, body: l10n.preparingBody),
                ]),
        ),
      ),
    );
  }
}

class _Today extends StatelessWidget {
  const _Today({required this.summary});

  final TodaySummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final workout = summary.workout;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: theme.colorScheme.tertiaryContainer,
          child: ListTile(
            leading: Icon(Icons.local_fire_department, color: theme.colorScheme.tertiary, size: 36),
            title: Text(l10n.streakDays(summary.streak), style: theme.textTheme.titleLarge),
          ),
        ),
        if (workout != null)
          Card(
            child: ListTile(
              leading: Icon(workout.loggedToday
                  ? Icons.check_circle
                  : workout.isPlannedRest
                      ? Icons.bedtime_outlined
                      : Icons.fitness_center),
              title: Text(l10n.todayWorkout),
              subtitle: Text(workout.isPlannedRest
                  ? l10n.plannedRest
                  : '${l10n.dayNumber(workout.dayNumber)}${workout.dayName == null ? '' : ' · ${workout.dayName}'}'),
              trailing: workout.loggedToday ? Text(l10n.loggedToday) : null,
            ),
          ),
      ],
    );
  }
}
