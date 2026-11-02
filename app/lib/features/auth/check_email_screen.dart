import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui.dart';
import '../../router/redirect.dart';

/// After sign-up when the project requires email confirmation. The link
/// opens the app and signs the user in; logging in by hand also works.
class CheckEmailScreen extends StatelessWidget {
  const CheckEmailScreen({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FormScaffold(
      title: '', // the message below carries the title
      primary: FilledButton(
        onPressed: () => context.go(Uri(path: Routes.login, queryParameters: {'email': email}).toString()),
        child: Text(l10n.goToLogin),
      ),
      children: [
        MessageView(
          icon: Icons.mark_email_read_outlined,
          title: l10n.checkEmailTitle,
          body: '${l10n.checkEmailBody(email)}\n\n${l10n.checkEmailHint}',
        ),
      ],
    );
  }
}
