import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// setState 콜백이 Future 를 "반환"하면 Flutter 가 던진다.
/// 화살표 `setState(() => _future = load())` 는 대입식 값(Future)을 리턴하므로 걸린다.
/// 클럽 가입 승인 흐름에서 이게 catch 되어 "승인 실패"로 오표시됐다(2026-07-23).
/// 블록 바디 `setState(() { _future = load(); })` 로 두어야 한다.
void main() {
  test('setState(() => _future = ...) 화살표 패턴이 lib 에 없어야 한다', () {
    final offenders = <String>[];
    final pattern = RegExp(r'setState\(\(\)\s*=>\s*_future\s*=');
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (pattern.hasMatch(entity.readAsStringSync())) {
        offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '화살표 setState 는 대입한 Future 를 반환해 던진다. '
          '블록 바디로 바꿔라: $offenders',
    );
  });
}
