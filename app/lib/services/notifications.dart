import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'notification_events.dart';

bool _messageListenersInitialized = false;

NotificationEvent _eventFromMessage(
  RemoteMessage message, {
  required bool openedFromSystem,
}) {
  return NotificationEvent(
    title: message.notification?.title ?? '새 알림',
    body: message.notification?.body ?? '',
    referenceType: message.data['reference_type'],
    referenceId: message.data['reference_id'],
    clubId: message.data['club_id'],
    openedFromSystem: openedFromSystem,
  );
}

/// FCM 토큰을 가져와 Supabase 에 등록한다.
///
/// firebase 구성 파일 (GoogleService-Info.plist / google-services.json) 이
/// 없는 환경에서는 조용히 skip — 개발 단계에서 앱이 부팅 자체를 막지 않도록.
Future<void> initNotifications(ApiService api) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // 구성 파일 없으면 skip
    return;
  }

  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  final token = await messaging.getToken();
  if (token != null) {
    final platform =
        Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'web');
    await api.registerDeviceToken(token, platform);
  }

  if (_messageListenersInitialized) return;
  _messageListenersInitialized = true;

  messaging.onTokenRefresh.listen((t) {
    final platform =
        Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'web');
    api.registerDeviceToken(t, platform);
  });

  FirebaseMessaging.onMessage.listen((message) async {
    final preferences = await SharedPreferences.getInstance();
    final soundEnabled = preferences.getBool('notify.sound') ?? true;
    if (soundEnabled) {
      await SystemSound.play(SystemSoundType.alert);
    }
    notificationEvents.add(
      _eventFromMessage(message, openedFromSystem: false),
    );
  });

  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    notificationEvents.add(
      _eventFromMessage(message, openedFromSystem: true),
    );
  });
}
