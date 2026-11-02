import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/ui.dart';

/// Leaves sign-up (e.g. to use another account). Shown where there's no
/// screen to go back to, so nobody is stuck.
class SignOutAction extends ConsumerWidget {
  const SignOutAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
        onPressed: () => ref.read(authRepositoryProvider).signOut(),
        child: Text(context.l10n.signOut),
      );
}
