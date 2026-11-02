import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local_notifications.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../../data/social_repository.dart';
import '../../l10n/gen/app_localizations.dart';

final remindersProvider = FutureProvider.autoDispose<List<Reminder>>((ref) => ref.watch(socialRepositoryProvider).reminders());

String reminderTitle(AppLocalizations l10n, Reminder r) => switch (r.kind) {
      'workout' => l10n.reminderWorkout,
      'meal' => r.label ?? l10n.mealTime(r.mealSlot ?? 1),
      'milestone' => l10n.reminderMilestone,
      _ => l10n.reminderDailyLog,
    };

/// Notification text for each reminder.
(String, String) reminderText(AppLocalizations l10n, Reminder r) => switch (r.kind) {
      'workout' => (l10n.reminderWorkoutTitle, l10n.reminderWorkoutBody),
      'meal' => (l10n.reminderMealTitle(r.label ?? l10n.mealTime(r.mealSlot ?? 1)), l10n.reminderMealBody),
      'milestone' => (l10n.reminderMilestoneTitle, l10n.reminderMilestoneBody),
      _ => (l10n.nNoDataTitle, l10n.nNoDataBody),
    };

/// Schedules the reminders on this phone; called on start and after changes.
Future<void> syncReminders(WidgetRef ref, AppLocalizations l10n) async {
  final reminders = await ref.read(socialRepositoryProvider).reminders();
  await LocalNotifications.instance.scheduleReminders(reminders, (r) => reminderText(l10n, r));
}

/// The trainee's own reminder times: one per meal, plus workout, check-in
/// and daily log. Until changed, the defaults apply (meal times from the
/// plan or the sign-up answers).
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  Future<void> _save(BuildContext context, WidgetRef ref, Reminder r, {String? time, bool? enabled}) async {
    try {
      await ref.read(socialRepositoryProvider).saveReminder(
            kind: r.kind,
            mealSlot: r.mealSlot,
            time: time ?? r.time ?? '09:00',
            enabled: enabled ?? r.enabled,
          );
      ref.invalidate(remindersProvider);
      if (!context.mounted) return;
      final l10n = context.l10n;
      await LocalNotifications.instance.requestPermission();
      await syncReminders(ref, l10n);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final reminders = ref.watch(remindersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reminders)),
      body: AsyncBody(
        value: reminders,
        onRetry: () => ref.invalidate(remindersProvider),
        builder: (list) => ListView(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(l10n.remindersHint)),
            for (final r in list)
              SwitchListTile(
                title: Text(reminderTitle(l10n, r)),
                subtitle: InkWell(
                  onTap: () async {
                    final parts = (r.time ?? '09:00').split(':');
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
                    );
                    if (picked != null && context.mounted) {
                      final time = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                      await _save(context, ref, r, time: time, enabled: true);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      r.time == null ? l10n.setTime : '${r.time}  ✎',
                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                ),
                value: r.enabled,
                onChanged: (on) => _save(context, ref, r, enabled: on),
              ),
          ],
        ),
      ),
    );
  }
}
