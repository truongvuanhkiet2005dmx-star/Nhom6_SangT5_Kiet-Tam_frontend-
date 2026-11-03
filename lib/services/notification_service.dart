import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService instance =
  NotificationService._init();

  final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  NotificationService._init();

  Future<void> initialize() async {
    await initializeForBackground();

    try {
      final androidPlugin =
      _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.requestNotificationsPermission();
    } catch (e) {
      debugPrint("Error requesting notification permission: $e");
    }
  }

  Future<void> initializeForBackground() async {
    if (_isInitialized) return;
    try {
      tz.initializeTimeZones();

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );

      const iosSettings = DarwinInitializationSettings();

      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(settings);
      _isInitialized = true;
    } catch (e) {
      debugPrint("Error in initializeForBackground: $e");
    }
  }

  Future<void> scheduleDailyReminder() async {
    await cancelDailyReminder();

    final now = tz.TZDateTime.now(tz.local);

    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      21,
      30,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate =
          scheduledDate.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      100,
      'SmartMoney',
      'Bạn đã nhập chi tiêu hôm nay chưa?',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder',
          'Nhắc nhở chi tiêu',
          channelDescription:
          'Nhắc người dùng nhập chi tiêu hàng ngày',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),

      androidScheduleMode:
      AndroidScheduleMode.inexactAllowWhileIdle,

      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,

      matchDateTimeComponents:
      DateTimeComponents.time,
    );
  }

  Future<void> showNotification(String title, String body) async {
    if (!_isInitialized) {
      await initializeForBackground();
    }

    const androidDetails = AndroidNotificationDetails(
      'auto_sms_channel',
      'Tự động ghi nhận SMS',
      channelDescription: 'Thông báo khi tự động ghi nhận giao dịch từ SMS ngân hàng',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    try {
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
      );
    } catch (e) {
      debugPrint("Error showing notification in background: $e");
    }
  }

  Future<void> cancelDailyReminder() async {
    await _notifications.cancel(100);
  }
}