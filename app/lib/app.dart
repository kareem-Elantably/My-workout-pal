import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/push.dart';
import 'l10n/gen/app_localizations.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class FitnessApp extends ConsumerWidget {
  const FitnessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Once someone is signed in and approved, this phone receives their pushes.
    ref.listen(sessionProvider, (previous, next) {
      final session = next.value;
      if (session is SignedIn && session.data.roles.isNotEmpty && previous?.value is! SignedIn) {
        Push.instance.register(ref.read(socialRepositoryProvider).registerDeviceToken);
      }
    });
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      routerConfig: ref.watch(routerProvider),
      locale: ref.watch(localeProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
    );
  }
}
