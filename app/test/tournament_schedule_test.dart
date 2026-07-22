import 'package:allround/models/tournament_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

/// 프로덕션 DB(2026-07-22)의 실제 값 — 공주/서산 KATO 대회 12줄.
const _real = '국화부 · 2026년 08월 06일 (목) 09:00 · 공주시립테니스코트\n'
    '개나리부(공주) · 2026년 08월 07일 (금) 09:00 · 공주시립테니스코트\n'
    '개나리부(서산,태안) · 2026년 08월 07일 (금) 09:00 · 서산시 종합운동장 테니스장\n'
    '개나리부(보령,홍성) · 2026년 08월 07일 (금) 09:00 · 보령남포실내테니스장 외\n'
    '개나리부(부여,청양) · 2026년 08월 07일 (금) 09:00 · 부여종합운동장 테니스장\n'
    '챌린저부(공주) · 2026년 08월 08일 (토) 09:00 · 공주시립테니스코트\n'
    '챌린저부(서산,태안) · 2026년 08월 08일 (토) 09:00 · 서산시 종합운동장 테니스장\n'
    '챌린저부(보령,홍성) · 2026년 08월 08일 (토) 09:00 · 보령남포실내테니스장 외\n'
    '챌린저부(부여,청양) · 2026년 08월 08일 (토) 09:00 · 부여종합운동장 테니스장\n'
    '마스터스부 · 2026년 08월 09일 (일) 09:00 · 공주시립테니스코트\n'
    '베테랑부 · 2026년 08월 09일 (일) 09:00 · 서산시 종합운동장 테니스장';

void main() {
  test('12줄이 날짜 4개로 묶이고 부서 중복이 사라진다', () {
    final days = parseTournamentSchedule(_real);

    expect(days.map((d) => d.date.day), [6, 7, 8, 9]);
    expect(days.map((d) => d.weekday), ['목', '금', '토', '일']);

    // 8/7 은 개나리부 하나로 묶이고 장소 4개를 갖는다(원문은 4줄).
    final friday = days[1];
    expect(friday.divisions.length, 1);
    expect(friday.divisions.single.division, '개나리부');
    expect(friday.divisions.single.time, '09:00');
    expect(friday.divisions.single.places.length, 4);
    expect(
      friday.divisions.single.places.map((p) => p.area),
      ['공주', '서산·태안', '보령·홍성', '부여·청양'],
    );
    expect(
      friday.divisions.single.places.first.venue,
      '공주시립테니스코트',
    );

    // 8/9 는 부서가 둘. 괄호가 없으면 area 는 null.
    final sunday = days[3];
    expect(sunday.divisions.map((g) => g.division), ['마스터스부', '베테랑부']);
    expect(sunday.divisions.first.places.single.area, isNull);
  });

  test('같은 부서라도 시간이 다르면 나눈다', () {
    final days = parseTournamentSchedule(
      '개나리부(A) · 2026년 08월 07일 (금) 09:00 · 코트1\n'
      '개나리부(B) · 2026년 08월 07일 (금) 13:00 · 코트2',
    );

    expect(days.single.divisions.length, 2);
    expect(days.single.divisions.map((g) => g.time), ['09:00', '13:00']);
  });

  test('장소에 구분자가 들어가도 잘리지 않는다', () {
    final days = parseTournamentSchedule(
      '국화부 · 2026년 08월 06일 (목) 09:00 · A코트 · B코트',
    );

    expect(days.single.divisions.single.places.single.venue, 'A코트 · B코트');
  });

  test('한 줄이라도 형식이 어긋나면 전체를 포기한다(평문 폴백)', () {
    // 두 번째 줄에 날짜가 없다 → 일부만 해석해 정보를 잃지 않는다.
    expect(
      parseTournamentSchedule(
        '국화부 · 2026년 08월 06일 (목) 09:00 · 공주시립테니스코트\n'
        '개나리부는 추후 공지',
      ),
      isEmpty,
    );
    expect(parseTournamentSchedule(''), isEmpty);
    expect(parseTournamentSchedule('아직 미정입니다'), isEmpty);
  });
}
