import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../router/redirect.dart';
import 'validators.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.email});

  /// Pre-filled, e.g. when coming from "check your email".
  final String? email;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
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
      e.statusCode == null ? showError(context, e) : showMessage(context, context.l10n.loginFailed);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AutofillGroup(
      child: FormScaffold(
        title: l10n.login,
        formKey: _form,
        primary: BusyButton(label: l10n.login, busy: _busy, onPressed: _logIn),
        secondary: TextButton(onPressed: () => context.go(Routes.welcome), child: Text(l10n.noAccount)),
        children: [
          TextFormField(
            controller: _email,
            decoration: InputDecoration(labelText: l10n.email),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            textDirection: TextDirection.ltr,
            validator: (value) => validateEmail(context, value),
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _password,
            label: l10n.password,
            validator: (value) => (value == null || value.isEmpty) ? l10n.required : null,
            onSubmitted: (_) => _logIn(),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => context.push(
                Uri(path: Routes.forgotPassword, queryParameters: {'email': _email.text.trim()}).toString(),
              ),
              child: Text(l10n.forgotPassword),
            ),
          ),
        ],
      ),
    );
  }
}
