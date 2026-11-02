import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'core/local_notifications.dart';
import 'core/providers.dart';
import 'core/push.dart';
import 'features/shared/notifications_screen.dart';
import 'router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabasePublishableKey);
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(preferences)]);

  /// Opens the screen a tapped notification points to, once signed in.
  Future<void> open(Map<String, dynamic> data) async {
    final session = await container.read(sessionProvider.future);
    if (session is! SignedIn) return;
    final router = container.read(routerProvider);
    final role = router.routerDelegate.currentConfiguration.uri.pathSegments.firstOrNull ?? '';
    final target = notificationTarget('/$role', '${data['type']}', data);
    router.push(target ?? '/$role/notifications');
  }

  await LocalNotifications.instance.init(onTap: (payload) {
    if (payload == null) return;
    // Reminders carry a route; pushes shown in the foreground carry their data.
    payload.startsWith('/') ? container.read(routerProvider).go(payload) : open(Uri.splitQueryString(payload));
  });
  await Push.instance.init(onOpen: open);

  runApp(UncontrolledProviderScope(container: container, child: const FitnessApp()));
}
