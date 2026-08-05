import 'package:allround/services/admin_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// 검수 큐 컷오프. 하루라도 어긋나면 오늘 열린 대회가 큐에서 사라지거나
/// 지난 대회가 계속 남는다.
///
/// 서버의 자동 마감(syncTournamentStatus)이 KST 로 판정하므로 여기도 KST 다.
/// 기기 시간대를 따라가면 두 판정이 어긋난다.
void main() {
  test('KST 자정 직후 — 그날 날짜가 된다', () {
    // 2026-08-04 00:10 KST == 2026-08-03 15:10 UTC
    expect(reviewQueueCutoff(DateTime.utc(2026, 8, 3, 15, 10)), '2026-08-04');
  });

  test('KST 자정 직전 — 아직 전날이다', () {
    // 2026-08-03 23:50 KST == 2026-08-03 14:50 UTC
    expect(reviewQueueCutoff(DateTime.utc(2026, 8, 3, 14, 50)), '2026-08-03');
  });

  test('같은 순간이면 기기 시간대 표현이 달라도 같은 답이 나온다', () {
    // DateTime.now() 는 기기 로컬 표현으로 온다. 같은 순간을 UTC 로 표현하든
    // 로컬로 표현하든 KST 날짜는 하나여야 한다 — 이게 깨지면 관리자가 어디에
    // 있느냐에 따라 큐가 달라진다.
    final utc = DateTime.utc(2026, 8, 3, 15, 10);
    final sameInstantLocal =
        DateTime.fromMillisecondsSinceEpoch(utc.millisecondsSinceEpoch);
    expect(sameInstantLocal.isUtc, isFalse, reason: '로컬 표현이어야 의미가 있다');
    expect(reviewQueueCutoff(sameInstantLocal), reviewQueueCutoff(utc));
    expect(reviewQueueCutoff(sameInstantLocal), '2026-08-04');
  });

  test('한 자리 월·일을 0으로 채운다', () {
    expect(reviewQueueCutoff(DateTime.utc(2026, 1, 4, 15)), '2026-01-05');
    expect(reviewQueueCutoff(DateTime.utc(2026, 12, 30, 15)), '2026-12-31');
  });

  test('컷오프는 오늘을 포함한다 — 오늘 시작하는 대회는 큐에 남는다', () {
    final cutoff = reviewQueueCutoff(DateTime.utc(2026, 8, 3, 15, 10));
    // 쿼리는 .gte(start_date, cutoff) 이므로 문자열 비교가 곧 판정이다.
    expect('2026-08-04'.compareTo(cutoff) >= 0, isTrue, reason: '오늘 시작');
    expect('2026-08-05'.compareTo(cutoff) >= 0, isTrue, reason: '내일 시작');
    expect('2026-08-03'.compareTo(cutoff) >= 0, isFalse, reason: '어제 시작');
  });
}
