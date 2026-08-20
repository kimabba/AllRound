import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('실기기 로컬 DB 실행은 정상 인증과 LAN 환경만 사용한다', () {
    final makefile = File('../Makefile').readAsStringSync();
    final targetStart = makefile.indexOf('device-local-db:');
    expect(targetStart, greaterThanOrEqualTo(0));

    final targetEnd = makefile.indexOf('\n# 터미널 3:', targetStart);
    expect(targetEnd, greaterThan(targetStart));

    final target = makefile.substring(targetStart, targetEnd);
    final config = File('lib/config.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(target, contains('flutter run --profile'));
    expect(target, contains('--dart-define-from-file=.env.local'));
    expect(target, contains('SUPABASE_URL'));
    expect(target, isNot(contains('USER_DESIGN_PREVIEW')));
    expect(target, isNot(contains('DEVICE_DATABASE_PREVIEW')));
    expect(config, isNot(contains('DEVICE_DATABASE_PREVIEW')));
    expect(main, isNot(contains('localQaPassword')));
  });

  test('iOS가 Mac의 로컬 Supabase 접속 권한을 선언한다', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(plist, contains('<key>NSLocalNetworkUsageDescription</key>'));
    expect(plist, contains('<key>NSAppTransportSecurity</key>'));
    expect(plist, contains('<key>NSAllowsLocalNetworking</key>'));
  });
}
