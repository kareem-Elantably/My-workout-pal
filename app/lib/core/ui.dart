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

/// Standard layout for form screens: scrolling content, and the primary
/// action pinned to the bottom, above the keyboard, always in the same place.
/// [leading] (e.g. a Back button) sits before the primary button, which
/// mirrors correctly in right-to-left; [secondary] is a text link below it.
class FormScaffold extends StatelessWidget {
  const FormScaffold({
    super.key,
    required this.title,
    required this.children,
    required this.primary,
    this.leading,
    this.secondary,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.progress,
    this.formKey,
    this.scrollController,
  });

  final String title;
  final List<Widget> children;
  final Widget primary;
  final Widget? leading;
  final Widget? secondary;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;

  /// 0..1, shown as a thin bar under the app bar for multi-step flows.
  final double? progress;
  final GlobalKey<FormState>? formKey;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: actions,
          automaticallyImplyLeading: automaticallyImplyLeading,
          bottom: progress == null
              ? null
              : PreferredSize(preferredSize: const Size.fromHeight(4), child: LinearProgressIndicator(value: progress)),
        ),
        body: Form(
          key: formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: children,
                ),
              ),
              Material(
                elevation: 3,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            if (leading != null) ...[Expanded(child: leading!), const SizedBox(width: 12)],
                            Expanded(flex: 2, child: primary),
                          ],
                        ),
                        if (secondary != null) Padding(padding: const EdgeInsets.only(top: 4), child: secondary!),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Password input with a show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.validator,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.isNew = false,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final FormFieldValidator<String>? validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  /// A password being created (autofill suggests a strong one).
  final bool isNew;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        obscureText: _hidden,
        autofillHints: [widget.isNew ? AutofillHints.newPassword : AutofillHints.password],
        textInputAction: widget.textInputAction,
        onFieldSubmitted: widget.onSubmitted,
        validator: widget.validator,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
          suffixIcon: IconButton(
            icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            tooltip: _hidden ? context.l10n.showPassword : context.l10n.hidePassword,
            onPressed: () => setState(() => _hidden = !_hidden),
          ),
        ),
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
