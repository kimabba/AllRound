import 'package:allround/models/chat_ui.dart';
import 'package:allround/utils/kst.dart';
import 'package:flutter_test/flutter_test.dart';

/// KST 오늘 날짜. 검수 큐 컷오프와 채팅 카드의 '종료' 판정이 이걸 쓴다.
/// 하루라도 어긋나면 오늘 열린 대회가 큐에서 사라지거나 지난 대회가 계속 남는다.
///
/// 서버의 자동 마감(syncTournamentStatus)이 KST 로 판정하므로 여기도 KST 다.
/// 기기 시간대를 따라가면 두 판정이 어긋난다.
void main() {
  test('KST 자정 직후 — 그날 날짜가 된다', () {
    // 2026-08-04 00:10 KST == 2026-08-03 15:10 UTC
    expect(kstToday(DateTime.utc(2026, 8, 3, 15, 10)), '2026-08-04');
  });

  test('KST 자정 직전 — 아직 전날이다', () {
    // 2026-08-03 23:50 KST == 2026-08-03 14:50 UTC
    expect(kstToday(DateTime.utc(2026, 8, 3, 14, 50)), '2026-08-03');
  });

  test('같은 순간이면 기기 시간대 표현이 달라도 같은 답이 나온다', () {
    // DateTime.now() 는 기기 로컬 표현으로 온다. 같은 순간을 UTC 로 표현하든
    // 로컬로 표현하든 KST 날짜는 하나여야 한다 — 이게 깨지면 관리자가 어디에
    // 있느냐에 따라 큐가 달라진다.
    final utc = DateTime.utc(2026, 8, 3, 15, 10);
    final sameInstantLocal =
        DateTime.fromMillisecondsSinceEpoch(utc.millisecondsSinceEpoch);
    expect(sameInstantLocal.isUtc, isFalse, reason: '로컬 표현이어야 의미가 있다');
    expect(kstToday(sameInstantLocal), kstToday(utc));
    expect(kstToday(sameInstantLocal), '2026-08-04');
  });

  test('한 자리 월·일을 0으로 채운다', () {
    expect(kstToday(DateTime.utc(2026, 1, 4, 15)), '2026-01-05');
    expect(kstToday(DateTime.utc(2026, 12, 30, 15)), '2026-12-31');
  });

  test('컷오프는 오늘을 포함한다 — 오늘 시작하는 대회는 큐에 남는다', () {
    final cutoff = kstToday(DateTime.utc(2026, 8, 3, 15, 10));
    // 쿼리는 .gte(start_date, cutoff) 이므로 문자열 비교가 곧 판정이다.
    expect('2026-08-04'.compareTo(cutoff) >= 0, isTrue, reason: '오늘 시작');
    expect('2026-08-05'.compareTo(cutoff) >= 0, isTrue, reason: '내일 시작');
    expect('2026-08-03'.compareTo(cutoff) >= 0, isFalse, reason: '어제 시작');
  });

  group('채팅 카드 종료 판정', () {
    // 2026-08-18 12:00 KST == 2026-08-18 03:00 UTC
    final now = DateTime.utc(2026, 8, 18, 3);

    TournamentChatCardItem card(String start, String? end) =>
        TournamentChatCardItem(
          id: 't',
          title: '대회',
          sport: 'tennis',
          startDate: start,
          endDate: end,
          eligible: true,
          eligibleGrades: const [],
        );

    test('여러 날 대회는 마지막 날이 지나야 종료다', () {
      // 진행 중(8/14~8/17 는 끝, 8/14~8/18 은 오늘까지)
      expect(card('2026-08-14', '2026-08-17').isFinished(now), isTrue);
      expect(card('2026-08-14', '2026-08-18').isFinished(now), isFalse);
      expect(card('2026-08-21', '2026-08-23').isFinished(now), isFalse);
    });

    test('종료일이 없으면 시작일로 판정한다', () {
      expect(card('2026-08-17', null).isFinished(now), isTrue);
      expect(card('2026-08-18', null).isFinished(now), isFalse, reason: '오늘 시작');
      expect(card('2026-08-29', null).isFinished(now), isFalse);
    });

    test('KST 자정 경계 — 기기가 UTC 여도 한국 날짜로 끊는다', () {
      // 2026-08-18 23:50 KST == 14:50 UTC → 아직 8/18, 8/18 대회는 진행 중
      expect(
        card('2026-08-18', null).isFinished(DateTime.utc(2026, 8, 18, 14, 50)),
        isFalse,
      );
      // 2026-08-19 00:10 KST == 8/18 15:10 UTC → 날이 바뀌어 종료
      expect(
        card('2026-08-18', null).isFinished(DateTime.utc(2026, 8, 18, 15, 10)),
        isTrue,
      );
    });
  });
}
