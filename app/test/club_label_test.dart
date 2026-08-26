import 'package:allround/utils/club_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('clubLabel — 협회 원문 소속(club_raw) 표시 정리', () {
    test('꼬리 슬래시를 떼어낸다 — 원문이 "어등산/" 형태로 미러된다(실측)', () {
      expect(clubLabel('어등산/'), '어등산');
    });

    test('여러 클럽은 가운뎃점으로 잇는다', () {
      expect(clubLabel('금호/어등산'), '금호 · 어등산');
      // 사이에 빈 조각이 껴도(연속 슬래시) 건너뛴다.
      expect(clubLabel('금호//어등산/'), '금호 · 어등산');
    });

    test('조각의 앞뒤 공백을 정리한다', () {
      expect(clubLabel(' 금호 / 어등산 '), '금호 · 어등산');
    });

    test('구분자 없는 단일 클럽은 그대로다', () {
      expect(clubLabel('어등산'), '어등산');
    });

    test('남는 조각이 없으면 null — 호출부가 줄을 생략한다', () {
      expect(clubLabel(null), isNull);
      expect(clubLabel(''), isNull);
      expect(clubLabel('  '), isNull);
      expect(clubLabel('/'), isNull);
      expect(clubLabel(' / '), isNull);
    });
  });
}
