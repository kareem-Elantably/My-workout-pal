import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../data/admin_repository.dart';
import '../../router/redirect.dart';
import '../home/profile_screen.dart';

final pendingApplicationsProvider = FutureProvider.autoDispose<List<PendingApplication>>(
  (ref) => ref.watch(adminRepositoryProvider).pendingApplications(),
);

/// Admin home: sign-ups waiting for review, oldest first.
class AdminHome extends ConsumerWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final pending = ref.watch(pendingApplicationsProvider);
    final dateFormat = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminHome),
        actions: [IconButton(icon: const Icon(Icons.person_outline), onPressed: () => context.push(Routes.profile))],
      ),
      body: pending.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(error: error, onRetry: () => ref.invalidate(pendingApplicationsProvider)),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(pendingApplicationsProvider.future),
          child: list.isEmpty
              ? ListView(children: [MessageView(icon: Icons.inbox_outlined, title: l10n.noPendingApplications)])
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = list[i];
                    final role = item.application.role;
                    return ListTile(
                      leading: CircleAvatar(child: Text(item.applicant.fullName.characters.firstOrNull ?? '?')),
                      title: Text(item.applicant.fullName),
                      subtitle: Text([
                        if (role != null) roleLabel(context, role),
                        l10n.submittedOn(dateFormat.format(item.application.submittedAt.toLocal())),
                      ].join(' · ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.application(item.application.id)),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
