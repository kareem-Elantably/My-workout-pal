import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/ui.dart';
import '../shared/chat_screens.dart';
import '../shared/more_tab.dart';
import '../shared/progress_views.dart';
import 'plan_tab.dart';
import 'reminders_screen.dart';
import 'today_tab.dart';

/// Trainee home: Today first, then plan, progress, chat and more.
class TraineeShell extends ConsumerStatefulWidget {
  const TraineeShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<TraineeShell> createState() => _TraineeShellState();
}

class _TraineeShellState extends ConsumerState<TraineeShell> {
  late int _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    // Keep the phone's reminders in line with the settings (and plan meals).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) syncReminders(ref, context.l10n).catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final me = ref.watch(myIdProvider);
    final unreadChats = ref.watch(conversationsProvider).value?.fold<int>(0, (sum, c) => sum + c.unread) ?? 0;
    final tabs = [
      const TodayTab(),
      const PlanTab(),
      Scaffold(appBar: AppBar(title: Text(l10n.progress)), body: ProgressView(traineeId: me)),
      const ChatListTab(),
      MoreTab(extra: [
        ListTile(
          leading: const Icon(Icons.alarm),
          title: Text(l10n.reminders),
          onTap: () => context.push('/trainee/reminders'),
        ),
        ListTile(
          leading: const Icon(Icons.card_membership),
          title: Text(l10n.subscription),
          onTap: () => context.push('/trainee/subscription'),
        ),
      ]),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.today_outlined), selectedIcon: const Icon(Icons.today), label: l10n.today),
          NavigationDestination(icon: const Icon(Icons.list_alt_outlined), selectedIcon: const Icon(Icons.list_alt), label: l10n.myPlan),
          NavigationDestination(icon: const Icon(Icons.show_chart), label: l10n.progress),
          NavigationDestination(
            icon: Badge(isLabelVisible: unreadChats > 0, label: Text('$unreadChats'), child: const Icon(Icons.chat_bubble_outline)),
            label: l10n.chat,
          ),
          NavigationDestination(icon: const Icon(Icons.menu), label: l10n.more),
        ],
      ),
    );
  }
}
