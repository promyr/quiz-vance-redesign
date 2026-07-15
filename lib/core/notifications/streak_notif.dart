import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class StreakNotif {
  StreakNotif._();

  static final StreakNotif instance = StreakNotif._();

  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'quiz_vance_streak';
  static const _channelName = 'Streak e revisao';

  Future<void> init() async {
    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@drawable/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
  }

  Future<bool> requestPermissionAndSchedule() async {
    var granted = true;
    if (Platform.isAndroid) {
      granted = await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    } else if (Platform.isIOS) {
      granted = await _plugin
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: false) ??
          false;
    }
    if (granted) {
      await scheduleDailyReminder();
    }
    return granted;
  }

  Future<void> scheduleDailyReminder() async {
    // zonedSchedule not supported on Windows
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    await _plugin.cancel(1);

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      20,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      1,
      'Hora de manter o streak',
      'Abra o Quiz Vance e conclua sua revisao de hoje.',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> notifyAchievement(String achievement) async {
    await _plugin.show(
      2,
      'Conquista desbloqueada',
      achievement,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.defaultImportance,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
