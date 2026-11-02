import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/ui.dart';
import 'validators.dart';

/// Sends a reset link that opens the app on the "set a new password" screen.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.email});

  final String? email;

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_sent) {
      return FormScaffold(
        title: l10n.forgotTitle,
        primary: FilledButton(onPressed: () => context.pop(), child: Text(l10n.backToLogin)),
        secondary: TextButton(onPressed: () => setState(() => _sent = false), child: Text(l10n.useDifferentEmail)),
        children: [
          MessageView(
            icon: Icons.mark_email_read_outlined,
            title: l10n.resetSentTitle,
            body: l10n.resetSentBody(_email.text.trim()),
          ),
        ],
      );
    }
    return FormScaffold(
      title: l10n.forgotTitle,
      formKey: _form,
      primary: BusyButton(label: l10n.sendLink, busy: _busy, onPressed: _send),
      children: [
        Text(l10n.forgotBody, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        TextFormField(
          controller: _email,
          autofocus: _email.text.isEmpty,
          decoration: InputDecoration(labelText: l10n.email),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.send,
          autofillHints: const [AutofillHints.email],
          textDirection: TextDirection.ltr,
          validator: (value) => validateEmail(context, value),
          onFieldSubmitted: (_) => _send(),
        ),
      ],
    );
  }
}
