import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('실제 기기 프리뷰 실행 명령은 profile 모드와 사용자 프리뷰 플래그를 사용한다', () {
    final makefile = File('../Makefile').readAsStringSync();

    expect(makefile, contains('device-preview:'));
    expect(makefile, contains('flutter run --profile -d \$(DEVICE_ID)'));
    expect(makefile, contains('--dart-define-from-file=.env.local'));
    expect(makefile, contains('--dart-define=USER_DESIGN_PREVIEW=true'));
  });

  test('실기기 DB 모드는 profile 빌드에서 실제 로컬 인증을 사용한다', () {
    final makefile = File('../Makefile').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final config = File('lib/config.dart').readAsStringSync();

    expect(makefile, contains('device-database:'));
    expect(makefile, contains('--dart-define=DEVICE_DATABASE_PREVIEW=true'));
    expect(main, contains('initializeDeviceDatabasePreviewSession'));
    expect(main, contains('auth.signInWithPassword'));
    expect(config, contains('deviceDatabasePreview'));
    expect(config, contains('deviceDatabasePreview ||'));
  });

  test('실제 기기 프리뷰 시작은 세션·원격 게이트·Crashlytics를 기다리지 않는다', () {
    final main = File('lib/main.dart').readAsStringSync();
    final router = File('lib/router.dart').readAsStringSync();

    expect(main, contains('persistSession: false'));
    expect(main, contains('localStorage: EmptyLocalStorage()'));
    expect(main, contains('pkceAsyncStorage: _PreviewPkceStorage()'));
    expect(main, contains('if (!AppConfig.userDesignPreview) {'));
    expect(main, contains('await _initCrashlytics();'));
    expect(
      main,
      contains(
          'if (AppConfig.userDesignPreview) {\n      await Future<void>.delayed'),
    );
    expect(router, contains('if (AppConfig.userDesignPreview) return;'));
    expect(
      router,
      contains("if (!kIsWeb && AppConfig.userDesignPreview) return '/clubs';"),
    );
  });
}
