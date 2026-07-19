import 'dart:math';

import 'package:allround/utils/storage_object_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates an opaque fixed-length image object name', () {
    final name = newOpaqueImageObjectName('jpeg', random: Random(7));

    expect(name, matches(RegExp(r'^[0-9a-f]{48}\.jpg$')));
    expect(name, isNot(contains('/')));
  });

  test('rejects formats that the privacy sanitizer does not emit', () {
    expect(
      () => newOpaqueImageObjectName('svg'),
      throwsArgumentError,
    );
  });
}
