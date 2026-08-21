import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS SceneDelegate는 명시적 Flutter 엔진 화면을 한 번만 연결한다', () {
    final sceneDelegate = File(
      'ios/Runner/SceneDelegate.swift',
    ).readAsStringSync();

    expect(sceneDelegate, contains('appDelegate.flutterEngine'));
    expect(sceneDelegate, contains('FlutterViewController('));
    expect(sceneDelegate,
        contains('window.rootViewController = flutterViewController'));
    expect(sceneDelegate, isNot(contains('super.scene(')));
  });

  test('비어 있는 모델 자리 파일을 iOS 앱 자산으로 묶지 않는다', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, isNot(contains('- assets/models/')));
    expect(File('assets/models/.gitkeep').existsSync(), isFalse);
  });
}
