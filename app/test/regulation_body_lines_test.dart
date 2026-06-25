import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/regulation_body_lines.dart';

void main() {
  group('parseRegulationBody — 줄 분류', () {
    test('대분류 헤더 ● / ◎ → header (마커 제거)', () {
      final lines = parseRegulationBody('● 경기방식 및 진행안내\n◎ 부서별 시상내역');
      expect(lines.map((l) => l.kind),
          [RegulationLineKind.header, RegulationLineKind.header]);
      expect(lines[0].text, '경기방식 및 진행안내');
      expect(lines[1].text, '부서별 시상내역');
    });

    test('항목 ◈ → item (마커 제거)', () {
      final lines = parseRegulationBody('◈ 남자일반부');
      expect(lines.single.kind, RegulationLineKind.item);
      expect(lines.single.text, '남자일반부');
    });

    test('번호 목록 ^\\d+\\. → numbered (라벨/본문 분리)', () {
      final lines = parseRegulationBody('1. 첫째 항목\n11. 열한번째');
      expect(lines.map((l) => l.kind),
          [RegulationLineKind.numbered, RegulationLineKind.numbered]);
      expect(lines[0].label, '1.');
      expect(lines[0].text, '첫째 항목');
      expect(lines[1].label, '11.');
    });

    test('대시 하위 ^-\\s? → dash', () {
      final lines = parseRegulationBody('- 우 승 : 시상금 110만원');
      expect(lines.single.kind, RegulationLineKind.dash);
      expect(lines.single.text, '우 승 : 시상금 110만원');
    });

    test('표 데이터행 ( | , 숫자 포함) → tableRow (셀 분리)', () {
      final lines = parseRegulationBody(
        '남자일반부(192팀) | 7월 4일(토) 09시00분 | 입금계좌 : 농협 667-02-238327',
      );
      expect(lines.single.kind, RegulationLineKind.tableRow);
      expect(lines.single.cells, [
        '남자일반부(192팀)',
        '7월 4일(토) 09시00분',
        '입금계좌 : 농협 667-02-238327',
      ]);
    });

    test('알려진 헤더행(첫 셀=경기종목)은 렌더 생략', () {
      final lines = parseRegulationBody('경기종목 | 경기일자 | 참가비 입금계좌');
      expect(lines, isEmpty);
    });

    test('숫자 없는 일반 텍스트 파이프 행은 보존 (헤더 오인 금지)', () {
      // "남자부 | 여자부" 는 숫자가 없지만 헤더가 아니다 → tableRow 로 보존.
      final lines = parseRegulationBody('남자부 | 여자부');
      expect(lines.single.kind, RegulationLineKind.tableRow);
      expect(lines.single.cells, ['남자부', '여자부']);
    });

    test('알려진 헤더 라벨이 아닌 첫 셀 → 보존', () {
      final lines = parseRegulationBody('우승 | 준우승 | 3위');
      expect(lines.single.kind, RegulationLineKind.tableRow);
      expect(lines.single.cells, ['우승', '준우승', '3위']);
    });

    test('첫 셀이 헤더 라벨(부서)이면 숫자 유무와 무관하게 생략', () {
      final lines = parseRegulationBody('부서 | 인원 | 비고');
      expect(lines, isEmpty);
    });

    test('라벨:값 → labelValue', () {
      final lines = parseRegulationBody('일시: 2026년 7월 4일\n참가비: 팀당 34,000원');
      expect(lines.map((l) => l.kind),
          [RegulationLineKind.labelValue, RegulationLineKind.labelValue]);
      expect(lines[0].label, '일시');
      expect(lines[0].value, '2026년 7월 4일');
      expect(lines[1].label, '참가비');
      expect(lines[1].value, '팀당 34,000원');
    });

    test('14자 초과 라벨은 labelValue 가 아니라 paragraph', () {
      // 라벨 후보가 15자 → 매칭 안 됨
      final lines = parseRegulationBody('가나다라마바사아자차카타파하가: 값');
      expect(lines.single.kind, RegulationLineKind.paragraph);
    });

    test('마커 모르는 줄 → paragraph (graceful)', () {
      final lines = parseRegulationBody('자유로운 안내 문장입니다');
      expect(lines.single.kind, RegulationLineKind.paragraph);
      expect(lines.single.text, '자유로운 안내 문장입니다');
    });
  });

  group('parseRegulationBody — ※ 분리', () {
    test('줄 중간 ※ → 앞부분 규칙 적용 + ※ 조각 note 분리', () {
      final lines = parseRegulationBody('참가비: 팀당 34,000원 ※ 보험료 포함 ※ 환불 불가');
      expect(lines.length, 3);
      expect(lines[0].kind, RegulationLineKind.labelValue);
      expect(lines[0].label, '참가비');
      expect(lines[0].value, '팀당 34,000원');
      expect(lines[1].kind, RegulationLineKind.note);
      expect(lines[1].text, '※ 보험료 포함');
      expect(lines[2].kind, RegulationLineKind.note);
      expect(lines[2].text, '※ 환불 불가');
    });

    test('줄 맨 앞 ※ → 앞부분 없이 note 만', () {
      final lines = parseRegulationBody('※ 접수 마감 후 변경 불가');
      expect(lines.single.kind, RegulationLineKind.note);
      expect(lines.single.text, '※ 접수 마감 후 변경 불가');
    });
  });

  group('parseRegulationBody — 정규화', () {
    test('빈 줄 제외, \\r\\n 정규화, 양끝 트림', () {
      final lines = parseRegulationBody('\r\n\n  ● 헤더  \n\n◈ 항목\n\n');
      expect(lines.map((l) => l.kind),
          [RegulationLineKind.header, RegulationLineKind.item]);
      expect(lines[0].text, '헤더');
    });

    test('빈 본문 → 빈 리스트', () {
      expect(parseRegulationBody('   \n  \n'), isEmpty);
    });
  });

  group('cleanPlainRegulationLines (단순 공고 평문 폴백)', () {
    test('중복 메타라인 제거 + 부서 접수 항목 줄바꿈', () {
      const desc =
          '참가부서: 오픈부 · 일반부 | 신청마감: 2026-06-24 | 대회일: 2026-06-27 | 지역: 전남\n\n'
          '전라남도테니스협회  제19회 전라남도지사기 시, 군 테니스대회  선수 변경시 대기 마지막(대기) 순으로 변경됩니다. 이점 참고하여 신중하게 신청 바랍니다  '
          '남자단체전 2026년 6월 01일 ~ 2026년 6월 24일 1800시 까지  2026년 6월 27일 21 / 90  '
          '여자단체전 2026년 6월 01일 ~ 2026년 6월 24일 1800시 까지  2026년 6월 27일 21 / 90';
      final lines = cleanPlainRegulationLines(desc);
      expect(lines.any((l) => l.startsWith('참가부서:')), isFalse);
      expect(lines.where((l) => l.startsWith('남자단체전')).length, 1);
      expect(lines.where((l) => l.startsWith('여자단체전')).length, 1);
      expect(lines.first.contains('전라남도테니스협회'), isTrue);
      expect(lines.every((l) => !l.contains('  ')), isTrue);
    });

    test('메타라인 없는 평문은 그대로 한 줄', () {
      expect(cleanPlainRegulationLines('준비 중인 대회입니다.'), ['준비 중인 대회입니다.']);
    });

    test('빈/공백 → 빈 리스트', () {
      expect(cleanPlainRegulationLines('   '), isEmpty);
    });
  });
}
