import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../router/redirect.dart';

/// After sign-up, until an admin decides. Checks again whenever the app
/// comes back to the foreground; the router moves on once a role is granted.
class WaitingScreen extends ConsumerStatefulWidget {
  const WaitingScreen({super.key});

  @override
  ConsumerState<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends ConsumerState<WaitingScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _check);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    await ref.read(sessionProvider.notifier).refresh();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = ref.watch(sessionProvider).value;
    final data = session is SignedIn ? session.data : null;
    final rejected = data?.latestApplicationFor(data.signupRole)?.status == ApplicationStatus.rejected;
    final signOut = TextButton(
      onPressed: () => ref.read(authRepositoryProvider).signOut(),
      child: Text(l10n.signOut),
    );

    return Scaffold(
      body: SafeArea(
        child: rejected
            ? MessageView(
                icon: Icons.info_outline,
                title: l10n.rejectedTitle,
                body: l10n.rejectedBody,
                actions: [
                  FilledButton(onPressed: () => context.go(Routes.onboarding), child: Text(l10n.applyAgain)),
                  signOut,
                ],
              )
            : MessageView(
                icon: Icons.hourglass_top,
                title: l10n.waitingTitle,
                body: l10n.waitingBody,
                actions: [
                  BusyButton(label: l10n.checkAgain, busy: _checking, onPressed: _check),
                  signOut,
                ],
              ),
      ),
    );
  }
}
