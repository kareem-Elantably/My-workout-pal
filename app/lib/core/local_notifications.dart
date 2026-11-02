import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/social_repository.dart';

/// Text for each reminder, in the user's language (built by the UI).
typedef ReminderText = (String title, String body) Function(Reminder reminder);

/// Device notifications: reminders scheduled on the phone (they work
/// offline) and pushes received while the app is open.
class LocalNotifications {
  LocalNotifications._();

  static final instance = LocalNotifications._();
  static const _channel = AndroidNotificationDetails(
    'default',
    'Fitness App',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _details = NotificationDetails(android: _channel, iOS: DarwinNotificationDetails());
  static const _reminderIdBase = 1000;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// [onTap] receives the payload (a route) of a tapped notification.
  Future<void> init({required void Function(String? payload) onTap}) async {
    if (_ready || kIsWeb) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
    _ready = true;
  }

  Future<void> requestPermission() async {
    if (!_ready) return;
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> show({required int id, required String title, String? body, String? payload}) async {
    if (!_ready) return;
    await _plugin.show(id: id, title: title, body: body, notificationDetails: _details, payload: payload);
  }

  /// Replaces all scheduled reminders with [reminders] (enabled ones with a time).
  Future<void> scheduleReminders(List<Reminder> reminders, ReminderText text) async {
    if (!_ready) return;
    for (var id = _reminderIdBase; id < _reminderIdBase + 200; id++) {
      await _plugin.cancel(id: id);
    }
    var slot = 0;
    for (final reminder in reminders) {
      final time = reminder.time;
      if (!reminder.enabled || time == null) continue;
      final (title, body) = text(reminder);
      final hour = int.parse(time.substring(0, 2));
      final minute = int.parse(time.substring(3, 5));
      final everyDay = reminder.weekdays.toSet().length == 7;
      // Weekdays are stored 0 = Sunday .. 6 = Saturday.
      for (final weekday in everyDay ? const [-1] : reminder.weekdays) {
        await _plugin.zonedSchedule(
          id: _reminderIdBase + slot * 8 + (weekday + 1),
          title: title,
          body: body,
          scheduledDate: _next(hour, minute, weekday == -1 ? null : (weekday == 0 ? DateTime.sunday : weekday)),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: everyDay ? DateTimeComponents.time : DateTimeComponents.dayOfWeekAndTime,
          payload: reminder.kind == 'milestone' ? null : '/trainee',
        );
      }
      slot++;
    }
  }

  tz.TZDateTime _next(int hour, int minute, int? weekday) {
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    while (!at.isAfter(now) || (weekday != null && at.weekday != weekday)) {
      at = at.add(const Duration(days: 1));
    }
    return at;
  }
}
