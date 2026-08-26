import 'package:allround/models/regulation_document.dart';
import 'package:allround/theme/tokens.dart';
import 'package:allround/widgets/tournaments/regulation_document_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('기본은 참가 탭이고 8개 섹션을 5개 탭으로 묶는다', (tester) async {
    final document = RegulationDocument.tryFromJson({
      'schema_version': 1,
      'sections': [
        _paragraphSection('eligibility', '참가 자격 내용'),
        _paragraphSection('schedule_venue', '일정 내용'),
        _paragraphSection('registration_payment', '신청 내용'),
        _paragraphSection('refund_changes', '환불 내용'),
        _paragraphSection('match_operations', '경기 운영 내용'),
        _paragraphSection('awards', '시상 내용'),
        _paragraphSection('notices_contact', '문의 내용'),
        _paragraphSection('other', '기타 내용'),
      ],
    })!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RegulationTabbedDocumentView(document: document),
          ),
        ),
      ),
    );

    for (final label in ['참가', '일정', '신청', '경기', '안내']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('참가 자격 내용'), findsOneWidget);
    expect(find.text('신청 내용'), findsNothing);

    await tester.tap(find.text('신청'));
    await tester.pump();
    expect(find.text('신청 내용'), findsOneWidget);
    expect(find.text('환불 내용'), findsOneWidget);
    expect(find.text('참가 자격 내용'), findsNothing);

    await tester.tap(find.text('경기'));
    await tester.pump();
    expect(find.text('경기 운영 내용'), findsOneWidget);
    expect(find.text('시상 내용'), findsOneWidget);

    await tester.tap(find.text('안내'));
    await tester.pump();
    expect(find.text('문의 내용'), findsOneWidget);
    expect(find.text('기타 내용'), findsOneWidget);
  });

  testWidgets('전체보기는 내용을 줄이지 않고 모든 섹션을 표시한다', (tester) async {
    final semantics = tester.ensureSemantics();
    final document = RegulationDocument.tryFromJson({
      'schema_version': 1,
      'sections': [
        _paragraphSection('eligibility', '참가 자격 내용'),
        _paragraphSection('registration_payment', '신청 내용'),
        _paragraphSection('awards', '시상 내용'),
      ],
    })!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RegulationTabbedDocumentView(document: document),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('전체 요강 보기'), findsOneWidget);
    expect(find.bySemanticsLabel('전체보기'), findsNothing);

    await tester.tap(find.text('전체보기'));
    await tester.pump();

    expect(find.bySemanticsLabel('전체 요강 보기, 선택됨'), findsOneWidget);
    expect(find.bySemanticsLabel('전체보기'), findsNothing);
    expect(find.text('참가 자격 내용'), findsOneWidget);
    expect(find.text('신청 내용'), findsOneWidget);
    expect(find.text('시상 내용'), findsOneWidget);

    await tester.tap(find.text('신청'));
    await tester.pump();
    expect(find.text('참가 자격 내용'), findsNothing);
    expect(find.text('신청 내용'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('빈 탭은 숨기고 미공지·해당 없음 상태는 유지한다', (tester) async {
    final document = RegulationDocument(
      schemaVersion: 1,
      sections: const [
        RegulationSection(
          code: RegulationSectionCode.scheduleVenue,
          availability: RegulationAvailability.notApplicable,
          blocks: [],
        ),
        RegulationSection(
          code: RegulationSectionCode.registrationPayment,
          availability: RegulationAvailability.notAnnounced,
          blocks: [],
        ),
        RegulationSection(
          code: RegulationSectionCode.other,
          availability: RegulationAvailability.present,
          blocks: [
            RegulationBlock(
              type: RegulationBlockType.keyValues,
              entries: [RegulationEntry(label: '출처', value: '내부 수집기')],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RegulationTabbedDocumentView(
            document: document,
            hidePublicMetadata: true,
          ),
        ),
      ),
    );

    expect(find.text('참가'), findsNothing);
    expect(find.text('일정'), findsOneWidget);
    expect(find.text('신청'), findsOneWidget);
    expect(find.text('안내'), findsNothing);
    expect(find.text('이 대회에는 해당하지 않습니다.'), findsOneWidget);

    await tester.tap(find.text('신청'));
    await tester.pump();
    expect(find.text('아직 공지되지 않았습니다.'), findsOneWidget);
  });

  testWidgets('320px·130% 글자에서 5개 탭이 한 줄이고 터치 영역은 48px이다', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    final document = RegulationDocument.tryFromJson({
      'schema_version': 1,
      'sections': [
        _paragraphSection('eligibility', '참가'),
        _paragraphSection('schedule_venue', '일정'),
        _paragraphSection('registration_payment', '신청'),
        _paragraphSection('match_operations', '경기'),
        _paragraphSection('notices_contact', '안내'),
      ],
    })!;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: RegulationTabbedDocumentView(document: document),
            ),
          ),
        ),
      ),
    );

    final tabInkWell = find.ancestor(
      of: find.text('참가'),
      matching: find.byType(InkWell),
    );
    expect(tabInkWell, findsOneWidget);
    expect(tester.getSize(tabInkWell).height, 48);
    expect(find.bySemanticsLabel('참가 요강 탭, 선택됨'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

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

  testWidgets('사용자 화면에서는 수집 출처·내부 ID·모집상태를 숨긴다', (tester) async {
    final document = RegulationDocument.fromLegacy(
      fields: const [
        (label: '출처', value: '풋살허브'),
        (label: '풋살허브 ID', value: '82'),
        (label: '모집상태', value: 'OPEN'),
        (label: '장소', value: '서울 풋살장'),
      ],
      notes: const [],
    )!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RegulationDocumentView(
            document: document,
            hidePublicMetadata: true,
          ),
        ),
      ),
    );

    expect(find.text('출처'), findsNothing);
    expect(find.text('풋살허브 ID'), findsNothing);
    expect(find.text('모집상태'), findsNothing);
    expect(find.text('장소'), findsOneWidget);
    expect(find.text('서울 풋살장'), findsOneWidget);
  });
}

Map<String, Object> _paragraphSection(String code, String text) => {
      'code': code,
      'availability': 'present',
      'blocks': [
        {'type': 'paragraph', 'text': text},
      ],
    };
