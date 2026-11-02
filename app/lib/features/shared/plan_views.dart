import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/plan_models.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';

/// A workout version: the cycle with its training days (missing day
/// numbers are planned rest days).
class WorkoutVersionView extends StatelessWidget {
  const WorkoutVersionView({super.key, required this.version, this.header});

  final WorkoutVersion version;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        ?header,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(l10n.cycleOfDays(version.cycleLength), style: theme.textTheme.bodySmall),
        ),
        for (var n = 1; n <= version.cycleLength; n++)
          switch (version.dayByNumber(n)) {
            final day? => Card(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: ExpansionTile(
                  leading: CircleAvatar(child: Text('$n')),
                  title: Text(day.name),
                  subtitle: Text(l10n.exerciseCount(day.exercises.length)),
                  children: [
                    for (final e in day.exercises)
                      ListTile(
                        dense: true,
                        title: Text(e.exercise.name(context)),
                        subtitle: Text([
                          e.target(),
                          if (e.restSeconds != null) l10n.restSeconds(e.restSeconds!),
                          if (e.tempo != null) l10n.tempo(e.tempo!),
                          if (e.supersetGroup != null) l10n.superset(e.supersetGroup!),
                          if (e.coachNotes != null) e.coachNotes!,
                        ].join(' · ')),
                        trailing: e.videoUrl1 == null
                            ? null
                            : IconButton(
                                tooltip: l10n.watchVideo,
                                icon: const Icon(Icons.play_circle_outline),
                                onPressed: () => launchUrl(Uri.parse(e.videoUrl1!), mode: LaunchMode.externalApplication),
                              ),
                      ),
                  ],
                ),
              ),
            null => ListTile(
                leading: CircleAvatar(backgroundColor: theme.colorScheme.surfaceContainerHighest, child: Text('$n')),
                title: Text(l10n.restDay),
              ),
          },
      ],
    );
  }
}

/// A nutrition version: meals, their options and the foods in each.
class NutritionVersionView extends StatelessWidget {
  const NutritionVersionView({super.key, required this.version, required this.showMacros, this.header});

  final NutritionVersion version;
  final bool showMacros;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        ?header,
        for (final meal in version.meals)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [meal.name, if (meal.timeHint != null) meal.timeHint!, if (!meal.countsForStreak) l10n.optional].join(' · '),
                    style: theme.textTheme.titleMedium,
                  ),
                  for (final option in meal.options) ...[
                    const SizedBox(height: 8),
                    if (meal.options.length > 1) Text(l10n.optionLabel(option.label), style: theme.textTheme.labelLarge),
                    for (final item in option.items)
                      Text('• ${item.food.name(context)} — ${item.amount(context)}${item.note == null ? '' : ' (${item.note})'}'),
                    if (showMacros) MacrosLine(option.macros),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
