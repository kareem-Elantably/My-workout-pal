import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../router/redirect.dart';

/// Separate entry points for trainees and coaches on the same screen.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(actions: [
        LanguageButton(current: ref.watch(localeProvider), onSelected: ref.read(localeProvider.notifier).select),
      ]),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.fitness_center, size: 80, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(l10n.appName, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(l10n.welcomeTitle, style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(l10n.welcomeSubtitle, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
              const Spacer(),
              FilledButton(
                onPressed: () => context.push(Routes.signup(AppRole.trainee)),
                child: Text(l10n.joinAsTrainee),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.push(Routes.signup(AppRole.coach)),
                child: Text(l10n.joinAsCoach),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: () => context.push(Routes.login), child: Text(l10n.haveAccount)),
            ],
          ),
        ),
      ),
    );
  }
}
