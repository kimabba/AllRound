import 'package:allround/models/tournament.dart';
import 'package:allround/utils/kst.dart';
import 'package:flutter_test/flutter_test.dart';

/// KST 오늘 날짜. 검수 큐 컷오프가 이걸 쓴다.
/// 하루라도 어긋나면 오늘 열린 대회가 큐에서 사라지거나 지난 대회가 계속 남는다.
///
/// 서버의 자동 마감(syncTournamentStatus)이 KST 로 판정하므로 여기도 KST 다.
/// 기기 시간대를 따라가면 두 판정이 어긋난다.
void main() {
  _deadlineGroup();

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
}

/// 대회 마감 판정이 KST 인지. 서버(tournaments_for_user 의 p_recruiting)가
/// KST 로 판정하므로 앱이 기기 로컬을 쓰면 한국 자정 근처에서 하루 어긋난다.
void _deadlineGroup() {
  Tournament t({DateTime? deadline, DateTime? start, String status = 'published'}) =>
      Tournament(
        id: 't',
        sport: 'tennis',
        title: '대회',
        startDate: start ?? DateTime(2026, 9, 1),
        applicationDeadline: deadline,
        eligibleGrades: const [],
        status: status,
      );

  group('kstTodayDate', () {
    test('KST 자정 경계 — 기기가 UTC 여도 한국 날짜로 끊는다', () {
      // 2026-08-18 23:50 KST == 14:50 UTC
      expect(kstTodayDate(DateTime.utc(2026, 8, 18, 14, 50)), DateTime(2026, 8, 18));
      // 2026-08-19 00:10 KST == 8/18 15:10 UTC
      expect(kstTodayDate(DateTime.utc(2026, 8, 18, 15, 10)), DateTime(2026, 8, 19));
    });

    test('시각 성분이 0 이라 difference(...).inDays 가 정확하다', () {
      final today = kstTodayDate(DateTime.utc(2026, 8, 18, 3));
      expect(today.hour, 0);
      expect(today.minute, 0);
      expect(DateTime(2026, 8, 20).difference(today).inDays, 2);
    });
  });

  group('isRegistrationClosed — KST 기준', () {
    test('마감일이 지났으면 마감', () {
      expect(t(deadline: DateTime(2020, 1, 1)).isRegistrationClosed, isTrue);
    });

    test('마감일이 한참 뒤면 접수 중', () {
      expect(t(deadline: DateTime(2099, 1, 1)).isRegistrationClosed, isFalse);
    });

    test('closed/cancelled 는 날짜와 무관하게 마감', () {
      expect(
        t(deadline: DateTime(2099, 1, 1), status: 'closed').isRegistrationClosed,
        isTrue,
      );
      expect(
        t(deadline: DateTime(2099, 1, 1), status: 'cancelled').isRegistrationClosed,
        isTrue,
      );
    });

    test('마감일이 없으면 시작일로 판정한다', () {
      expect(t(start: DateTime(2020, 1, 1)).isRegistrationClosed, isTrue);
      expect(t(start: DateTime(2099, 1, 1)).isRegistrationClosed, isFalse);
    });

    test('기기 시계가 KST 보다 뒤처져도 한국 날짜로 판정한다 — 회귀 감지용', () {
      // 2026-08-18 15:10 UTC == KST 8/19 00:10. 한국은 날이 바뀌었지만 UTC 는 아직 8/18.
      // KST 로 판정하면 "오늘은 8/19" 라 8/18 마감은 지난 것이고,
      // 기기 시각(UTC)으로 판정하면 "오늘은 8/18" 이라 아직 접수 중으로 보인다.
      //
      // 이 방향으로 잡는 이유: 이 시각을 UTC 표현으로 넘기면 CI(TZ=UTC)에서도
      // 두 판정이 갈린다. 반대 방향(시드니)은 테스트 프로세스 TZ 가 KST 보다
      // 앞설 때만 갈려서, UTC 러너에서는 회귀를 놓친다.
      final afterKstMidnight = DateTime.utc(2026, 8, 18, 15, 10);
      expect(
        t(deadline: DateTime(2026, 8, 18))
            .isRegistrationClosedAt(afterKstMidnight),
        isTrue,
        reason: 'KST 로는 이미 8/19 — 8/18 마감은 지났다',
      );
      expect(
        t(deadline: DateTime(2026, 8, 19))
            .isRegistrationClosedAt(afterKstMidnight),
        isFalse,
        reason: 'KST 오늘(8/19) 마감은 아직 접수 중',
      );
      // 시작일 폴백도 같은 기준인지.
      expect(
        t(start: DateTime(2026, 8, 18)).isRegistrationClosedAt(afterKstMidnight),
        isTrue,
        reason: 'KST 로 어제 시작한 대회는 지났다',
      );
    });
  });
}
