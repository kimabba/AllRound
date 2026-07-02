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
}
