import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/ui.dart';

/// While the session loads; offers a retry if loading failed.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      body: SafeArea(
        child: session.hasError && !session.isLoading
            ? ErrorRetry(error: session.error!, onRetry: () => ref.read(sessionProvider.notifier).refresh())
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
