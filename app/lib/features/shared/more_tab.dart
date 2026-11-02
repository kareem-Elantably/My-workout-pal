import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../../router/redirect.dart';
import 'notifications_button.dart';

/// "More": everything that isn't a daily task, one tap away.
class MoreTab extends StatelessWidget {
  const MoreTab({super.key, this.extra = const []});

  /// Role-specific entries, shown first.
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final base = rolePath(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.more)),
      body: ListView(
        children: [
          ...extra,
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(l10n.notifications),
            onTap: () => context.push('$base/notifications'),
          ),
          ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: Text(l10n.myNotes),
            onTap: () => context.push('$base/notes'),
          ),
          ListTile(
            leading: const Icon(Icons.calculate_outlined),
            title: Text(l10n.mealConverter),
            subtitle: Text(l10n.mealConverterHint),
            onTap: () => context.push('$base/tools'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(l10n.profile),
            onTap: () => context.push(Routes.profile),
          ),
        ],
      ),
    );
  }
}

final _mySubscriptionsProvider =
    FutureProvider.autoDispose((ref) => ref.watch(socialRepositoryProvider).mySubscriptions());

/// The trainee's subscription: dates and days left. Nothing is blocked
/// when it ends; the admin and the trainee get a heads-up a week before.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final format = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    final subs = ref.watch(_mySubscriptionsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.subscription)),
      body: AsyncBody(
        value: subs,
        onRetry: () => ref.invalidate(_mySubscriptionsProvider),
        builder: (list) => list.isEmpty
            ? EmptyList(icon: Icons.card_membership, title: l10n.noSubscription)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final s in list)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s['status'] == 'ended' ? l10n.subscriptionEnded : l10n.daysLeft(s['days_left'] as int),
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text('${format.format(DateTime.parse(s['starts_on'] as String))} → '
                                '${format.format(DateTime.parse(s['ends_on'] as String))}'),
                            Text(l10n.amountEgp('${s['amount_egp']}')),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
