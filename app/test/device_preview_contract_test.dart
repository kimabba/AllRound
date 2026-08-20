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
}
