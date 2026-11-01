import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/gen/app_localizations.dart';

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// A user-facing message for an error from Supabase or the network.
String errorMessage(BuildContext context, Object error) {
  if (error is SocketException || (error is AuthException && error.statusCode == null)) {
    return context.l10n.noConnection;
  }
  return context.l10n.somethingWentWrong;
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(errorMessage(context, error))));
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Full-screen message with an icon, used for empty, waiting and error states.
class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.icon, required this.title, this.body, this.actions = const []});

  final IconData icon;
  final String title;
  final String? body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: 12),
              Text(body!, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
            ],
            if (actions.isNotEmpty) const SizedBox(height: 32),
            for (final action in actions) Padding(padding: const EdgeInsets.only(bottom: 12), child: action),
          ],
        ),
      ),
    );
  }
}

/// Error state with a retry button, for screens that load data.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MessageView(
        icon: Icons.cloud_off_outlined,
        title: errorMessage(context, error),
        actions: [OutlinedButton(onPressed: onRetry, child: Text(context.l10n.retry))],
      );
}

/// Button that shows a spinner while [busy].
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Text(label),
      );
}

/// Switches the UI language; shown on screens before and after sign-in.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key, required this.current, required this.onSelected});

  final Locale current;
  final ValueChanged<Locale> onSelected;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => onSelected(Locale(current.languageCode == 'ar' ? 'en' : 'ar')),
        child: Text(current.languageCode == 'ar' ? context.l10n.english : context.l10n.arabic),
      );
}
