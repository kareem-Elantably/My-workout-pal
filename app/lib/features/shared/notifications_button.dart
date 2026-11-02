import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../router/redirect.dart';

/// First path segment of the current screen: trainee, coach or admin.
/// Shared screens live under each role's home so back stays in that role.
String rolePath(BuildContext context) => '/${GoRouterState.of(context).matchedLocation.split('/')[1]}';

final unreadNotificationsProvider =
    FutureProvider.autoDispose<int>((ref) => ref.watch(socialRepositoryProvider).unreadNotifications());

class NotificationsButton extends ConsumerWidget {
  const NotificationsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider).value ?? 0;
    return IconButton(
      tooltip: context.l10n.notifications,
      icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_outlined)),
      onPressed: () async {
        await context.push('${rolePath(context)}/notifications');
        ref.invalidate(unreadNotificationsProvider);
      },
    );
  }
}

class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: context.l10n.profile,
        icon: const Icon(Icons.person_outline),
        onPressed: () => context.push(Routes.profile),
      );
}
