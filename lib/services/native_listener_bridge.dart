import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'package:telephony/telephony.dart';

class NativeListenerBridge {
  static Future<bool> hasNotificationPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      bool? isGranted = await NotificationsListener.hasPermission;
      return isGranted == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openNotificationPermissionSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await NotificationsListener.openPermissionSettings();
    } catch (_) {}
  }

  static Future<void> initializeNotificationListener(dynamic callbackHandle) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      if (callbackHandle is Function) {
        await NotificationsListener.initialize(callbackHandle: callbackHandle as EventCallbackFunc);
      }
    } catch (_) {}
  }

  static Stream<dynamic>? get receiveNotificationPort {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      return NotificationsListener.receivePort;
    } catch (_) {
      return null;
    }
  }

  static Future<void> listenIncomingSms({
    required Function(String body) onNewMessage,
    required Function(SmsMessage message) onBackgroundMessage,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final Telephony telephony = Telephony.instance;
      telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) {
          if (message.body != null && message.body!.isNotEmpty) {
            onNewMessage(message.body!);
          }
        },
        onBackgroundMessage: onBackgroundMessage,
      );
    } catch (_) {}
  }

  static Future<List<Map<String, String>>> getInboxSms() async {
    if (kIsWeb || !Platform.isAndroid) return [];
    try {
      final Telephony telephony = Telephony.instance;
      List<SmsMessage> messages = await telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      );

      messages.sort((a, b) => (b.date ?? 0).compareTo(a.date ?? 0));

      return messages.map((m) => {
        'address': m.address ?? 'Không rõ',
        'body': m.body ?? '',
        'date': (m.date ?? 0).toString(),
      }).toList();
    } catch (_) {
      return [];
    }
  }
}