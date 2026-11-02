import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../../data/social_repository.dart';
import 'notifications_button.dart';

final inboxProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) => ref.watch(socialRepositoryProvider).inbox());

/// Title and body in the reader's language (system notifications store only
/// the type and its data; custom ones carry their own text).
(String, String?) notificationText(BuildContext context, AppNotification n) {
  final l10n = context.l10n;
  final d = n.data;
  return switch (n.type) {
    'custom' => (n.title ?? '', n.body),
    'application_result' => d['status'] == 'approved'
        ? (l10n.nApprovedTitle, l10n.nApprovedBody)
        : (l10n.nRejectedTitle, l10n.rejectedBody),
    'plan_ready' => (l10n.nPlanReadyTitle, d['kind'] == 'nutrition' ? l10n.nPlanReadyNutrition : l10n.nPlanReadyWorkout),
    'milestone_due' => (l10n.checkInDue, l10n.nMilestoneDueBody),
    'milestone_uploaded' => (l10n.nMilestoneUploadedTitle, null),
    'trainee_assigned' => (l10n.nTraineeAssignedTitle, null),
    'subscription_recorded' => (l10n.nPaymentTitle, l10n.nPaymentBody('${d['amount_egp']}', '${d['days']}')),
    'subscription_ending' => d['trainee_name'] != null
        ? (l10n.nSubscriptionEndingTitle, l10n.nSubscriptionEndingAdmin('${d['trainee_name']}', '${d['days_left']}'))
        : (l10n.nSubscriptionEndingTitle, l10n.daysLeft(int.tryParse('${d['days_left']}') ?? 0)),
    'no_data_today' => (l10n.nNoDataTitle, l10n.nNoDataBody),
    _ => (n.title ?? n.type, n.body),
  };
}

/// Where tapping a notification goes (also used for push taps).
String? notificationTarget(String rolePath, String type, Map<String, dynamic> data) => switch (type) {
      'milestone_due' when data['milestone_id'] != null => '$rolePath/milestone/${data['milestone_id']}',
      'milestone_uploaded' || 'trainee_assigned' when data['trainee_id'] != null => '$rolePath/trainees/${data['trainee_id']}',
      'chat_message' when data['conversation_id'] != null => '$rolePath/chat/${data['conversation_id']}',
      'subscription_recorded' || 'subscription_ending' => rolePath == '/admin' ? '/admin?tab=2' : '$rolePath/subscription',
      _ => null,
    };

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the inbox marks everything read.
    Future.microtask(() => ref.read(socialRepositoryProvider).markNotificationsRead().catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final inbox = ref.watch(inboxProvider);
    final format = DateFormat.MMMd(Localizations.localeOf(context).toString()).add_jm();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notifications)),
      body: AsyncBody(
        value: inbox,
        onRetry: () => ref.invalidate(inboxProvider),
        builder: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(inboxProvider.future),
          child: list.isEmpty
              ? EmptyList(icon: Icons.notifications_none, title: l10n.noNotifications)
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final n = list[i];
                    final (title, body) = notificationText(context, n);
                    final target = notificationTarget(rolePath(context), n.type, n.data);
                    return ListTile(
                      leading: Icon(n.readAt == null ? Icons.circle : Icons.circle_outlined,
                          size: 12, color: Theme.of(context).colorScheme.primary),
                      title: Text(title, style: n.readAt == null ? const TextStyle(fontWeight: FontWeight.w600) : null),
                      subtitle: Text([?body, format.format(n.createdAt.toLocal())].join('\n')),
                      isThreeLine: body != null,
                      onTap: target == null ? null : () => context.push(target),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
