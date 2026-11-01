import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui.dart';
import '../../router/redirect.dart';

/// Shown after sign-up when the project requires email confirmation.
class CheckEmailScreen extends StatelessWidget {
  const CheckEmailScreen({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: MessageView(
            icon: Icons.mark_email_read_outlined,
            title: context.l10n.checkEmailTitle,
            body: context.l10n.checkEmailBody(email),
            actions: [
              FilledButton(onPressed: () => context.go(Routes.login), child: Text(context.l10n.backToLogin)),
            ],
          ),
        ),
      );
}
