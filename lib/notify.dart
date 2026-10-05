import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

final notifications = FlutterLocalNotificationsPlugin();

/// Debug builds nudge after 10 seconds so the reminder is testable.
const followUpDelay = bool.fromEnvironment('dart.vm.product') ? Duration(days: 5) : Duration(seconds: 10);

/// Returns false when the student said no to notifications (the reminder won't show).
Future<bool> scheduleFollowUp(int id, String company) async {
  final allowed = await notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  await notifications
      .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, sound: true);
  await notifications.zonedSchedule(
    id: id,
    title: 'Nudge $company? 👀',
    body: 'No reply yet. A short follow-up with one new thing you shipped works wonders.',
    scheduledDate: tz.TZDateTime.now(tz.UTC).add(followUpDelay),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails('follow_ups', 'Follow-up reminders', importance: Importance.high),
      iOS: DarwinNotificationDetails(),
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
  return allowed ?? true;
}
