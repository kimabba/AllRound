import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

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

  messaging.onTokenRefresh.listen((t) {
    final platform =
        Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'web');
    api.registerDeviceToken(t, platform);
  });

  FirebaseMessaging.onMessage.listen((_) async {
    final preferences = await SharedPreferences.getInstance();
    final soundEnabled = preferences.getBool('notify.sound') ?? true;
    if (soundEnabled) {
      await SystemSound.play(SystemSoundType.alert);
    }
  });
}
