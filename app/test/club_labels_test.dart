import 'package:flutter_test/flutter_test.dart';
import 'package:allround/utils/club_labels.dart';

void main() {
  group('club labels', () {
    test('gender labels normalize stored codes and Korean labels', () {
      expect(clubGenderLabel('mixed'), '혼성');
      expect(clubGenderLabel('male'), '남성');
      expect(clubGenderLabel('female'), '여성');
      expect(clubGenderCode('혼성'), 'mixed');
    });

    test('gender matching accepts mixed code for Korean mixed filter', () {
      expect(clubGenderMatches('mixed', '혼성'), isTrue);
      expect(clubGenderMatches('male', '혼성'), isFalse);
      expect(clubGenderMatches(null, '혼성'), isTrue);
    });

    test('day matching accepts full weekday labels', () {
      expect(clubDaysMatch(const ['월요일', '목요일'], const {'목'}), isTrue);
      expect(clubDaysMatch(const ['월', '목'], const {'목요일'}), isTrue);
      expect(clubDaysMatch(const ['화'], const {'목'}), isFalse);
    });

    test('region matching accepts broad region labels', () {
      expect(clubRegionMatches('서울특별시', '서울'), isTrue);
      expect(clubRegionMatches('서울', '서울특별시'), isTrue);
      expect(clubRegionMatches('경기', '서울'), isFalse);
    });

    test('club name query matches partial words and compact input', () {
      const name = '해운대 웨이브 FS';
      expect(clubNameMatchesQuery(name, '해운대'), isTrue);
      expect(clubNameMatchesQuery(name, '웨이브 fs'), isTrue);
      expect(clubNameMatchesQuery(name, '해운대웨이브'), isTrue);
      expect(clubNameMatchesQuery(name, '분당'), isFalse);
    });

    test('monthly fee label includes context', () {
      expect(clubMonthlyFeeLabel(40000), '월회비 4만원');
      expect(clubMonthlyFeeLabel(0), '월회비 무료');
    });
  });

  group('club monthly fee input', () {
    test('empty and valid values pass', () {
      expect(clubMonthlyFeeInputError(''), isNull);
      expect(clubMonthlyFeeInputError('0'), isNull);
      expect(clubMonthlyFeeInputError('1000000'), isNull);
    });

    test('non-numeric and out-of-range values fail', () {
      expect(clubMonthlyFeeInputError('free'), isNotNull);
      expect(clubMonthlyFeeInputError('-1'), isNotNull);
      expect(clubMonthlyFeeInputError('1000001'), isNotNull);
    });
  });

  group('club website input', () {
    test('empty and web URLs pass', () {
      expect(clubWebsiteInputError(''), isNull);
      expect(clubWebsiteInputError('https://example.com/club'), isNull);
      expect(clubWebsiteInputError('http://example.com'), isNull);
    });

    test('missing scheme and non-web schemes fail', () {
      expect(clubWebsiteInputError('example.com'), isNotNull);
      expect(clubWebsiteInputError('ftp://example.com'), isNotNull);
      expect(clubWebsiteInputError('https://'), isNotNull);
    });
  });

  test('club member count label shows the total safely', () {
    expect(clubMemberCountLabel(12), '총 12명');
    expect(clubMemberCountLabel(0), '총 0명');
    expect(clubMemberCountLabel(-1), '총 0명');
  });

  test('club region and member count use a compact card label', () {
    expect(clubRegionMemberLabel('서울', 10), '서울 10명');
    expect(clubRegionMemberLabel(null, 0), '지역 미정 0명');
    expect(clubRegionMemberLabel('  ', -1), '지역 미정 0명');
  });

  // JY-149: 서버가 내려준 UTC 시각을 그대로 포맷하면 KST 에서 9시간 밀려 보였다.
  // 주의 — 이 성질은 실행 환경의 타임존에 의존한다. UTC 환경에서는 변환 누락이어도
  // 통과하므로 초록불이 곧 증거는 아니다. CI 는 TZ=Asia/Seoul 로 고정해 검증한다.
  test('club event label renders local time, not the raw UTC clock', () {
    final local = DateTime(2026, 8, 8, 19, 0);
    expect(clubEventDateTimeLabel(local.toUtc()), '8월 8일 (토) 19:00');
    expect(clubEventDateTimeLabel(local), '8월 8일 (토) 19:00');
    // 분이 정각뿐이면 분 보존·자릿수 채움 회귀를 못 잡는다. 5분은 둘 다 덮는다
    // (분을 버리면 19:00, padLeft 를 빠뜨리면 19:5).
    expect(
      clubEventDateTimeLabel(DateTime(2026, 8, 8, 19, 5).toUtc()),
      '8월 8일 (토) 19:05',
    );
  });

  // 변환을 빠뜨리면 시각뿐 아니라 날짜·요일까지 틀어진다(KST 이른 아침 모임이
  // 전날로 표시). 일요일은 weekday==7 이라 요일 인덱스 경계도 함께 덮는다.
  test('club event label keeps the local date across a day boundary', () {
    final sundayMorning = DateTime(2026, 8, 9, 7, 0);
    expect(clubEventDateTimeLabel(sundayMorning.toUtc()), '8월 9일 (일) 07:00');
  });
}
