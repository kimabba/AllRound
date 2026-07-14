import 'package:flutter_test/flutter_test.dart';
import 'package:allround/utils/age.dart';

void main() {
  final now = DateTime(2026, 7, 14);

  group('ageOn — 만 나이 경계', () {
    test('생일 당일이면 그 나이', () {
      expect(ageOn(DateTime(2007, 7, 14), now), 19); // 정확히 19년 전 = 생일 당일
    });
    test('생일 하루 전이면 한 살 적다', () {
      expect(ageOn(DateTime(2007, 7, 15), now), 18); // 아직 생일 안 지남
    });
    test('생일 지났으면 그대로', () {
      expect(ageOn(DateTime(2007, 7, 13), now), 19);
    });
  });

  group('isUnderMinSignupAge — 만 19세 게이트', () {
    test('만 19세 생일 당일 → 허용(미만 아님)', () {
      expect(isUnderMinSignupAge(DateTime(2007, 7, 14), now), isFalse);
    });
    test('만 18세(생일 하루 전) → 차단', () {
      expect(isUnderMinSignupAge(DateTime(2007, 7, 15), now), isTrue);
    });
    test('만 20세 → 허용', () {
      expect(isUnderMinSignupAge(DateTime(2006, 1, 1), now), isFalse);
    });
    test('만 13세 → 차단', () {
      expect(isUnderMinSignupAge(DateTime(2013, 1, 1), now), isTrue);
    });
  });
}
