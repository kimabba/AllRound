import 'package:allround/models/regulation_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v1 문서는 입력 순서와 무관하게 고정 섹션 순서로 파싱된다', () {
    final document = RegulationDocument.tryFromJson({
      'schema_version': 1,
      'summary': '  대회 요약  ',
      'sections': [
        {
          'code': 'awards',
          'availability': 'present',
          'blocks': [
            {'type': 'paragraph', 'text': '우승 30만원'},
          ],
        },
        {
          'code': 'eligibility',
          'availability': 'present',
          'blocks': [
            {
              'type': 'bullets',
              'items': ['광주협회 등록 회원'],
            },
          ],
        },
      ],
    });

    expect(document, isNotNull);
    expect(document!.summary, '대회 요약');
    expect(document.sections.map((section) => section.code), [
      RegulationSectionCode.eligibility,
      RegulationSectionCode.awards,
    ]);
  });

  test('지원하지 않는 버전과 내용 없는 present 섹션은 거부한다', () {
    expect(
      RegulationDocument.tryFromJson({'schema_version': 2, 'sections': []}),
      isNull,
    );
    expect(
      RegulationDocument.tryFromJson({
        'schema_version': 1,
        'sections': [
          {'code': 'eligibility', 'availability': 'present', 'blocks': []},
        ],
      }),
      isNull,
    );
  });

  test('공지 전 섹션은 블록이 없어도 상태를 보존한다', () {
    final document = RegulationDocument.tryFromJson({
      'schema_version': 1,
      'sections': [
        {
          'code': 'schedule_venue',
          'availability': 'not_announced',
          'blocks': [],
        },
      ],
    });
    expect(document, isNotNull);
    expect(
      document!.sections.single.availability,
      RegulationAvailability.notAnnounced,
    );
  });

  test('기존 자유 라벨과 본문도 공통 섹션 문서로 변환한다', () {
    final document = RegulationDocument.fromLegacy(
      fields: [
        (label: '시상', value: '우승 30만원'),
        (label: '참가신청 기간', value: '8월 1일~10일'),
        (label: '남자 일반부 입금계좌', value: '농협 123-456'),
      ],
      notes: ['우천 시 일정 변경'],
      body: '● 경기방식\n1. 예선 조별리그',
    );

    expect(document, isNotNull);
    expect(document!.sections.map((section) => section.code), [
      RegulationSectionCode.registrationPayment,
      RegulationSectionCode.awards,
      RegulationSectionCode.noticesContact,
      RegulationSectionCode.other,
    ]);
    final other = document.sections.last;
    expect(other.blocks.first.type, RegulationBlockType.subheading);
    expect(other.blocks.last.type, RegulationBlockType.bullets);
  });

  test('부서별 일정 블록을 타입 안전하게 파싱한다', () {
    final document = RegulationDocument.tryFromJson({
      'schema_version': 1,
      'sections': [
        {
          'code': 'schedule_venue',
          'availability': 'present',
          'blocks': [
            {
              'type': 'division_schedule',
              'divisions': [
                {
                  'name': '남자 일반부',
                  'date': '2026-09-12',
                  'venue': '진월국제테니스장',
                },
              ],
            },
          ],
        },
      ],
    });
    final division = document!.sections.single.blocks.single.divisions.single;
    expect(division.name, '남자 일반부');
    expect(division.venue, '진월국제테니스장');
  });
}
