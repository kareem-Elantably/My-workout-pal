import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../core/ui.dart';
import 'validators.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _logIn() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      // The session listener moves the user on once signed in.
      await ref.read(authRepositoryProvider).signIn(_email.text, _password.text);
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.statusCode == null) {
        showError(context, e);
      } else {
        showMessage(context, context.l10n.loginFailed);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final error = validateEmail(context, _email.text);
    if (error != null) {
      showMessage(context, error);
      return;
    }
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted) showMessage(context, context.l10n.resetSent);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.login)),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                controller: _email,
                decoration: InputDecoration(labelText: l10n.email),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textDirection: TextDirection.ltr,
                validator: (value) => validateEmail(context, value),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                decoration: InputDecoration(labelText: l10n.password),
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                validator: (value) => (value == null || value.isEmpty) ? l10n.required : null,
                onFieldSubmitted: (_) => _logIn(),
              ),
              const SizedBox(height: 24),
              BusyButton(label: l10n.login, busy: _busy, onPressed: _logIn),
              const SizedBox(height: 8),
              TextButton(onPressed: _resetPassword, child: Text(l10n.forgotPassword)),
            ],
          ),
        ),
      ),
    );
  }
}
