import 'package:allround/models/regulation_document.dart';
import 'package:allround/widgets/tournaments/regulation_document_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('고정 섹션 제목과 다양한 블록을 같은 읽기 순서로 표시한다', (tester) async {
    final document = RegulationDocument.tryFromJson({
      'schema_version': 1,
      'summary': '대회 핵심 내용을 한눈에 확인하세요.',
      'sections': [
        {
          'code': 'registration_payment',
          'availability': 'present',
          'blocks': [
            {
              'type': 'key_values',
              'entries': [
                {'label': '참가비', 'value': '팀당 54,000원'},
              ],
            },
          ],
        },
        {
          'code': 'eligibility',
          'availability': 'present',
          'blocks': [
            {'type': 'subheading', 'text': '남자 일반부'},
            {
              'type': 'bullets',
              'items': ['광주광역시테니스협회 등록 회원'],
            },
          ],
        },
        {
          'code': 'schedule_venue',
          'availability': 'not_announced',
          'blocks': [],
        },
      ],
    })!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RegulationDocumentView(document: document),
          ),
        ),
      ),
    );

    expect(find.text('참가 부서 및 자격'), findsOneWidget);
    expect(find.text('일정 및 장소'), findsOneWidget);
    expect(find.text('신청 및 결제'), findsOneWidget);
    expect(find.text('아직 공지되지 않았습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px·200% 글자에서도 긴 표와 부서별 정보가 오버플로우하지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
                  'name': '남자 일반부 매우 긴 부서 이름',
                  'date': '2026년 9월 12일 토요일 오전 9시',
                  'venue': '진월국제테니스장 및 보조경기장 전체 코트',
                  'fee': '팀당 54,000원',
                  'account': '농협 123-4567-8901 예금주 광주테니스협회',
                },
              ],
            },
            {
              'type': 'table',
              'columns': ['부서', '경기일', '장소', '참가비'],
              'rows': [
                {
                  'cells': ['남자 일반부', '9월 12일', '진월국제테니스장', '54,000원'],
                },
              ],
            },
          ],
        },
      ],
    })!;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: RegulationDocumentView(document: document),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('일정 및 장소'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
