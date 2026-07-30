import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'notification_events.dart';

bool _messageListenersInitialized = false;
const _notificationSoundPreferenceKey = 'notify.sound';

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
    final preferences = await SharedPreferences.getInstance();
    final soundEnabled =
        preferences.getBool(_notificationSoundPreferenceKey) ?? true;
    await api.setDeviceTokenSound(token, soundEnabled);
  }

  if (_messageListenersInitialized) return;
  _messageListenersInitialized = true;

  messaging.onTokenRefresh.listen((t) async {
    final platform =
        Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'web');
    await api.registerDeviceToken(t, platform);
    final preferences = await SharedPreferences.getInstance();
    final soundEnabled =
        preferences.getBool(_notificationSoundPreferenceKey) ?? true;
    await api.setDeviceTokenSound(t, soundEnabled);
  });

  FirebaseMessaging.onMessage.listen((message) async {
    final preferences = await SharedPreferences.getInstance();
    final soundEnabled =
        preferences.getBool(_notificationSoundPreferenceKey) ?? true;
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

/// 현재 기기의 알림음 설정을 서버와 동기화한다.
///
/// 토큰이 아직 발급되지 않은 경우에는 다음 앱 시작 또는 토큰 갱신 때
/// 로컬 설정이 자동으로 동기화된다.
Future<void> syncNotificationSoundPreference(
  ApiService api, {
  required bool enabled,
}) async {
  final token = await FirebaseMessaging.instance.getToken();
  if (token == null) return;
  await api.setDeviceTokenSound(token, enabled);
}
