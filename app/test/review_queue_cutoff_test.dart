import 'package:allround/services/admin_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// 검수 큐 컷오프. 하루라도 어긋나면 오늘 열린 대회가 큐에서 사라지거나
/// 지난 대회가 계속 남는다.
void main() {
  test('오늘 날짜를 YYYY-MM-DD 로 만든다', () {
    expect(reviewQueueCutoff(DateTime(2026, 8, 4, 23, 59)), '2026-08-04');
  });

  test('한 자리 월·일을 0으로 채운다', () {
    expect(reviewQueueCutoff(DateTime(2026, 1, 5)), '2026-01-05');
    expect(reviewQueueCutoff(DateTime(2026, 12, 31)), '2026-12-31');
  });

  test('컷오프는 오늘을 포함한다 — 오늘 시작하는 대회는 큐에 남는다', () {
    final today = DateTime(2026, 8, 4);
    final cutoff = reviewQueueCutoff(today);
    // 쿼리는 .gte(start_date, cutoff) 이므로 문자열 비교가 곧 판정이다.
    expect('2026-08-04'.compareTo(cutoff) >= 0, isTrue, reason: '오늘 시작');
    expect('2026-08-05'.compareTo(cutoff) >= 0, isTrue, reason: '내일 시작');
    expect('2026-08-03'.compareTo(cutoff) >= 0, isFalse, reason: '어제 시작');
  });
}
