import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../data/home_repository.dart';
import '../../router/redirect.dart';

final coachDashboardProvider = FutureProvider.autoDispose<List<CoachTrainee>>(
  (ref) => ref.watch(homeRepositoryProvider).coachDashboard(),
);

/// Coach home = who needs attention: trainees sorted by missed days, due
/// check-ins and unread messages (sorted by the database).
class CoachHome extends ConsumerWidget {
  const CoachHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final trainees = ref.watch(coachDashboardProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.coachHome),
        actions: [IconButton(icon: const Icon(Icons.person_outline), onPressed: () => context.push(Routes.profile))],
      ),
      body: trainees.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(coachDashboardProvider)),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(coachDashboardProvider.future),
          child: list.isEmpty
              ? ListView(children: [MessageView(icon: Icons.groups_outlined, title: l10n.noTraineesYet)])
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _TraineeTile(trainee: list[i]),
                ),
        ),
      ),
    );
  }
}

class _TraineeTile extends StatelessWidget {
  const _TraineeTile({required this.trainee});

  final CoachTrainee trainee;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final status = [
      trainee.trainedToday ? l10n.trainedToday : l10n.notTrainedToday,
      if (trainee.mealsTotalToday > 0) l10n.mealsDone(trainee.mealsDoneToday, trainee.mealsTotalToday),
      if (trainee.missedDays7 > 0) l10n.missedDays(trainee.missedDays7),
      if (trainee.milestonesDue > 0) l10n.milestonesDue(trainee.milestonesDue),
      if (trainee.unreadMessages > 0) l10n.unreadMessages(trainee.unreadMessages),
    ];
    final needsAttention = trainee.missedDays7 > 0 || trainee.milestonesDue > 0 || trainee.unreadMessages > 0;
    return ListTile(
      leading: CircleAvatar(child: Text(trainee.fullName.characters.first)),
      title: Text(trainee.fullName),
      subtitle: Text(status.join(' · '), style: needsAttention ? TextStyle(color: theme.colorScheme.error) : null),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department, color: theme.colorScheme.tertiary),
          Text('${trainee.streak}'),
        ],
      ),
    );
  }
}
