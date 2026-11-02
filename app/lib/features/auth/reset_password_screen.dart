import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/ui.dart';
import 'validators.dart';

/// Opened from the reset-password email link. Cancelling signs out, so
/// nobody is left signed in without knowing their password.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).updatePassword(_password.text);
      if (!mounted) return;
      showMessage(context, context.l10n.passwordUpdated);
      ref.read(passwordRecoveryProvider.notifier).finish(); // the router continues to the user's home
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    ref.read(passwordRecoveryProvider.notifier).finish();
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: FormScaffold(
        title: l10n.newPasswordTitle,
        formKey: _form,
        automaticallyImplyLeading: false,
        actions: [IconButton(icon: const Icon(Icons.close), tooltip: l10n.cancel, onPressed: _cancel)],
        primary: BusyButton(label: l10n.save, busy: _busy, onPressed: _save),
        children: [
          PasswordField(
            controller: _password,
            label: l10n.newPassword,
            helperText: l10n.passwordHint,
            isNew: true,
            textInputAction: TextInputAction.next,
            validator: (value) => validatePassword(context, value),
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _confirm,
            label: l10n.confirmPassword,
            isNew: true,
            validator: (value) => value != _password.text ? l10n.passwordsDontMatch : null,
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
    );
  }
}
