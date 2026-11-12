import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../../router/redirect.dart';
import '../auth/validators.dart';

String roleLabel(BuildContext context, AppRole role) => switch (role) {
      AppRole.trainee => context.l10n.roleTrainee,
      AppRole.coach => context.l10n.roleCoach,
      AppRole.admin => context.l10n.roleAdmin,
    };

/// Language, role switcher (for people with several roles) and sign out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, String column, String label, String? current) async {
    final isPhone = column == 'phone';
    final value = await promptText(context, title: label, initial: current, keyboardType: isPhone ? TextInputType.phone : null);
    if (value == null || !context.mounted) return;
    if (value.trim().isEmpty) {
      showMessage(context, isPhone ? context.l10n.phoneRequired : context.l10n.required);
      return;
    }
    final stored = isPhone ? normalizePhone(value) : value.trim();
    if (stored == null) {
      showMessage(context, context.l10n.invalidPhone);
      return;
    }
    try {
      await ref.read(sessionRepositoryProvider).updateProfile(ref.read(myIdProvider), {column: stored});
      await ref.read(sessionProvider.notifier).refresh();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(sessionProvider).value;
    if (session is! SignedIn) return const Scaffold();
    final data = session.data;
    final locale = ref.watch(localeProvider);
    final activeRole =
        data.roles.isEmpty ? null : resolveActiveRole(data.roles, ref.watch(activeRoleProvider));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profile)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: CircleAvatar(child: Text(data.profile?.fullName.characters.firstOrNull ?? '?')),
            title: Text(data.profile?.fullName ?? ''),
            subtitle: Text(data.email ?? '', textDirection: TextDirection.ltr),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _edit(context, ref, 'full_name', l10n.fullName, data.profile?.fullName),
          ),
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: Text(l10n.phone),
            subtitle: Text(data.profile?.phone ?? '—', textDirection: TextDirection.ltr),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _edit(context, ref, 'phone', l10n.phone, data.profile?.phone),
          ),
          const Divider(),
          ListTile(
            title: Text(l10n.language),
            trailing: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'ar', label: Text(l10n.arabic)),
                ButtonSegment(value: 'en', label: Text(l10n.english)),
              ],
              selected: {locale.languageCode},
              onSelectionChanged: (selection) =>
                  ref.read(localeProvider.notifier).select(Locale(selection.first)),
            ),
          ),
          if (data.roles.length > 1) ...[
            const Divider(),
            ListTile(title: Text(l10n.activeRole)),
            for (final role in AppRole.values.where(data.roles.contains))
              ListTile(
                leading: Icon(role == activeRole ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                title: Text(roleLabel(context, role)),
                onTap: () => ref.read(activeRoleProvider.notifier).select(role),
              ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l10n.signOut),
            onTap: () => ref.read(authRepositoryProvider).signOut(),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text(l10n.deleteAccount, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () async {
              if (!await confirm(context, l10n.deleteAccountConfirm, action: l10n.deleteAccount)) return;
              try {
                await ref.read(socialRepositoryProvider).deleteAccount();
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
          ),
        ],
      ),
    );
  }
}
