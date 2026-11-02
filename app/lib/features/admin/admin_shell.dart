import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui.dart';
import '../shared/more_tab.dart';
import 'admin_home.dart';
import 'people_screens.dart';

/// Admin home: applications, people, subscriptions, more (earnings).
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        const AdminHome(),
        const PeopleTab(),
        const SubscriptionsTab(),
        MoreTab(extra: [
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(l10n.earningsByCoach),
            onTap: () => context.push('/admin/earnings'),
          ),
        ]),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.inbox_outlined), label: l10n.adminHome),
          NavigationDestination(icon: const Icon(Icons.people_outline), label: l10n.people),
          NavigationDestination(icon: const Icon(Icons.card_membership), label: l10n.subscriptions),
          NavigationDestination(icon: const Icon(Icons.menu), label: l10n.more),
        ],
      ),
    );
  }
}
