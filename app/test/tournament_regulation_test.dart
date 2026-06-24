import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/models/tournament.dart';

Map<String, dynamic> _baseJson() => {
      'id': 't1',
      'sport': 'tennis',
      'title': '테스트 대회',
      'start_date': '2026-06-20',
      'status': 'published',
    };

void main() {
  group('Tournament.fromJson — regulation_fields', () {
    test('정상: [{label, value}] 배열을 순서 보존하여 파싱', () {
      final j = _baseJson()
        ..['regulation_fields'] = [
          {'label': '장소', 'value': '서울 코트'},
          {'label': '주최', 'value': 'KTA'},
          {'label': '경기방식', 'value': '복식 토너먼트'},
        ];
      final t = Tournament.fromJson(j);
      expect(t.regulationFields.length, 3);
      expect(t.regulationFields[0].label, '장소');
      expect(t.regulationFields[0].value, '서울 코트');
      expect(t.regulationFields[1].label, '주최');
      expect(t.regulationFields[2].value, '복식 토너먼트');
    });

    test('누락: regulation_fields 없으면 빈 리스트', () {
      final t = Tournament.fromJson(_baseJson());
      expect(t.regulationFields, isEmpty);
    });

    test('형식이상: null/문자열/숫자/라벨누락 요소는 건너뛰고 유효 항목만 유지', () {
      final j = _baseJson()
        ..['regulation_fields'] = [
          {'label': '장소', 'value': '서울 코트'}, // 유효
          {'value': '라벨 없음'}, // label 누락 → skip
          {'label': '', 'value': '빈 라벨'}, // 빈 label → skip
          {'label': 123, 'value': 'x'}, // label 비문자열 → skip
          'not a map', // 비-Map → skip
          null, // null → skip
          {'label': '주최'}, // value 누락 → 빈 문자열 value 로 유지
        ];
      final t = Tournament.fromJson(j);
      expect(t.regulationFields.length, 2);
      expect(t.regulationFields[0].label, '장소');
      expect(t.regulationFields[1].label, '주최');
      expect(t.regulationFields[1].value, ''); // value 누락 → 빈 문자열
    });

    test('형식이상: regulation_fields 가 배열이 아니면 빈 리스트', () {
      final j = _baseJson()..['regulation_fields'] = {'label': 'x'};
      final t = Tournament.fromJson(j);
      expect(t.regulationFields, isEmpty);
    });

    test('label/value 양끝 공백은 트림', () {
      final j = _baseJson()
        ..['regulation_fields'] = [
          {'label': '  장소  ', 'value': '  서울  '},
        ];
      final t = Tournament.fromJson(j);
      expect(t.regulationFields.single.label, '장소');
      expect(t.regulationFields.single.value, '서울');
    });
  });

  group('Tournament.fromJson — regulation_notes', () {
    test('정상: 문자열 배열 파싱', () {
      final j = _baseJson()
        ..['regulation_notes'] = ['참가비로 보험 가입', '접수 마감 엄수'];
      final t = Tournament.fromJson(j);
      expect(t.regulationNotes, ['참가비로 보험 가입', '접수 마감 엄수']);
    });

    test('누락: regulation_notes 없으면 빈 리스트', () {
      final t = Tournament.fromJson(_baseJson());
      expect(t.regulationNotes, isEmpty);
    });

    test('형식이상: 비문자열/빈문자열 제거, 트림 적용', () {
      final j = _baseJson()
        ..['regulation_notes'] = ['  보험 가입  ', '', 42, null, '   '];
      final t = Tournament.fromJson(j);
      expect(t.regulationNotes, ['보험 가입']);
    });

    test('형식이상: regulation_notes 가 배열이 아니면 빈 리스트', () {
      final j = _baseJson()..['regulation_notes'] = '문자열';
      final t = Tournament.fromJson(j);
      expect(t.regulationNotes, isEmpty);
    });
  });

  group('Tournament.fromJson — regulation_body', () {
    test('정상: 여러 줄 문자열을 "\\n" 보존하여 파싱', () {
      final body = '◈ 시상내역\n우승: 트로피\n준우승: 메달\n\n◎ 입금계좌\n123-456';
      final j = _baseJson()..['regulation_body'] = body;
      final t = Tournament.fromJson(j);
      expect(t.regulationBody, body);
      expect(t.regulationBody!.split('\n').length, 6);
      expect(t.regulationBody, contains('◈'));
    });

    test('누락: regulation_body 없으면 null', () {
      final t = Tournament.fromJson(_baseJson());
      expect(t.regulationBody, isNull);
    });

    test('형식이상: 비문자열이면 null', () {
      final j = _baseJson()..['regulation_body'] = 42;
      final t = Tournament.fromJson(j);
      expect(t.regulationBody, isNull);
    });

    test('형식이상: 빈/공백 문자열이면 null', () {
      expect(
        Tournament.fromJson(_baseJson()..['regulation_body'] = '')
            .regulationBody,
        isNull,
      );
      expect(
        Tournament.fromJson(_baseJson()..['regulation_body'] = '   \n  ')
            .regulationBody,
        isNull,
      );
    });

    test('내부 줄바꿈은 보존, 원문 유지', () {
      final j = _baseJson()..['regulation_body'] = '첫 줄\n둘째 줄';
      final t = Tournament.fromJson(j);
      expect(t.regulationBody, '첫 줄\n둘째 줄');
    });
  });

  group('RegulationField.tryFromJson', () {
    test('비-Map 입력은 null', () {
      expect(RegulationField.tryFromJson('x'), isNull);
      expect(RegulationField.tryFromJson(null), isNull);
      expect(RegulationField.tryFromJson(7), isNull);
    });

    test('정상 Map 은 모델 반환', () {
      final f = RegulationField.tryFromJson({'label': '시상', 'value': '트로피'});
      expect(f, isNotNull);
      expect(f!.label, '시상');
      expect(f.value, '트로피');
    });
  });
}
