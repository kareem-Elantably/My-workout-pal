import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'local_notifications.dart';

/// Push notifications (Firebase Cloud Messaging). The server decides what
/// to send (send-push Edge Function); the app registers this phone's token
/// for the signed-in user, shows pushes that arrive while it's open, and
/// opens the right screen when one is tapped.
class Push {
  Push._();

  static final instance = Push._();

  bool _ready = false;
  String? _token;
  StreamSubscription<String>? _refresh;

  /// This phone's token, removed from the account on sign out.
  String? get token => _token;

  /// Call once at start-up. Failure (no Google Play services, no network)
  /// leaves the app working without push.
  Future<void> init({required void Function(Map<String, dynamic> data) onOpen}) async {
    final options = FirebaseConfig.current;
    if (_ready || options == null) return;
    try {
      await Firebase.initializeApp(options: options);
      FirebaseMessaging.onMessage.listen((message) {
        final n = message.notification;
        if (n == null) return;
        LocalNotifications.instance.show(
          id: message.hashCode & 0x7fffffff,
          title: n.title ?? '',
          body: n.body,
          payload: Uri(queryParameters: message.data.map((k, v) => MapEntry(k, '$v'))).query,
        );
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) => onOpen(message.data));
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) onOpen(initial.data);
      _ready = true;
    } catch (e) {
      debugPrint('Push unavailable: $e');
    }
  }

  /// Asks permission and registers this phone for the signed-in user.
  Future<void> register(Future<void> Function(String token, String platform) save) async {
    if (!_ready) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final platform = Platform.isIOS ? 'ios' : 'android';
      // A registration token, which the send-push function addresses with
      // FCM HTTP v1. (The newer register()/onRegistered gives an
      // installation ID for direct send instead.)
      // ignore: deprecated_member_use
      _token = await FirebaseMessaging.instance.getToken();
      if (_token != null) await save(_token!, platform);
      await _refresh?.cancel();
      // ignore: deprecated_member_use
      _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _token = token;
        save(token, platform);
      });
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }
}
