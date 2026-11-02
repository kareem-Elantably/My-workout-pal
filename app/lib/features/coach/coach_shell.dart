import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/ui.dart';
import '../home/coach_home.dart';
import '../shared/chat_screens.dart';
import '../shared/earnings_view.dart';
import '../shared/more_tab.dart';
import 'library_tab.dart';

/// Coach home: trainees by who needs attention, chats, library, earnings.
class CoachShell extends ConsumerStatefulWidget {
  const CoachShell({super.key});

  @override
  ConsumerState<CoachShell> createState() => _CoachShellState();
}

class _CoachShellState extends ConsumerState<CoachShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final me = ref.watch(myIdProvider);
    final unreadChats = ref.watch(conversationsProvider).value?.fold<int>(0, (sum, c) => sum + c.unread) ?? 0;
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        const CoachHome(),
        const ChatListTab(),
        const LibraryTab(),
        Scaffold(appBar: AppBar(title: Text(l10n.earnings)), body: EarningsView(byTrainee: true, coachId: me)),
        const MoreTab(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.groups_outlined), selectedIcon: const Icon(Icons.groups), label: l10n.trainees),
          NavigationDestination(
            icon: Badge(isLabelVisible: unreadChats > 0, label: Text('$unreadChats'), child: const Icon(Icons.chat_bubble_outline)),
            label: l10n.chat,
          ),
          NavigationDestination(icon: const Icon(Icons.library_books_outlined), label: l10n.library),
          NavigationDestination(icon: const Icon(Icons.payments_outlined), label: l10n.earnings),
          NavigationDestination(icon: const Icon(Icons.menu), label: l10n.more),
        ],
      ),
    );
  }
}
