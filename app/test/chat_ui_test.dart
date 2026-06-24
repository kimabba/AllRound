import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/models/chat_ui.dart';
import 'package:matchup/widgets/chat_tournament_card.dart';

void main() {
  group('ChatUiBlock.listFromEvent', () {
    test('parses a tournament cards block', () {
      final data = {
        'blocks': [
          {
            'type': 'cards',
            'entity': 'tournament',
            'items': [
              {
                'id': '11111111-1111-1111-1111-111111111111',
                'title': '광주 테니스 오픈',
                'sport': 'tennis',
                'region': '광주',
                'location': '진월국제테니스장',
                'start_date': '2026-06-13',
                'end_date': '2026-06-13',
                'eligible': true,
                'eligible_grades': ['gj_m_gold'],
                'entry_fee': 30000,
                'format': '복식',
              }
            ],
          }
        ],
      };
      final blocks = ChatUiBlock.listFromEvent(data);
      expect(blocks.length, 1);
      expect(blocks.first.entity, 'tournament');
      expect(blocks.first.tournamentItems.length, 1);
      final item = blocks.first.tournamentItems.first;
      expect(item.title, '광주 테니스 오픈');
      expect(item.region, '광주');
      expect(item.entryFee, 30000);
      expect(item.eligible, true);
    });

    test('returns empty list on malformed payload', () {
      expect(ChatUiBlock.listFromEvent({'blocks': 'oops'}), isEmpty);
      expect(ChatUiBlock.listFromEvent(const {}), isEmpty);
      expect(ChatUiBlock.listFromEvent({'blocks': [42]}), isEmpty);
    });

    test('skips items with missing required fields', () {
      final data = {
        'blocks': [
          {
            'type': 'cards',
            'entity': 'tournament',
            'items': [
              {'id': 'x', 'sport': 'tennis'}, // no title/start_date
            ],
          }
        ],
      };
      final blocks = ChatUiBlock.listFromEvent(data);
      expect(blocks.single.tournamentItems, isEmpty);
    });

    test('club entity block yields no tournament items but is still emitted', () {
      final data = {
        'blocks': [
          {'type': 'cards', 'entity': 'club', 'items': []}
        ],
      };
      final blocks = ChatUiBlock.listFromEvent(data);
      expect(blocks.length, 1);
      expect(blocks.first.entity, 'club');
      expect(blocks.first.tournamentItems, isEmpty);
    });

    test('parses regulation_fields (normal)', () {
      final data = {
        'blocks': [
          {
            'type': 'cards',
            'entity': 'tournament',
            'items': [
              {
                'id': '11111111-1111-1111-1111-111111111111',
                'title': 'T',
                'sport': 'tennis',
                'start_date': '2026-06-13',
                'regulation_fields': [
                  {'label': '장소', 'value': '영암종합스포츠타운'},
                  {'label': '사용구', 'value': '헤드 챔피언십'},
                ],
              }
            ],
          }
        ],
      };
      final item = ChatUiBlock.listFromEvent(data).single.tournamentItems.single;
      expect(item.regulationFields.length, 2);
      expect(item.regulationFields.first.label, '장소');
      expect(item.regulationFields.first.value, '영암종합스포츠타운');
      expect(item.regulationFields[1].label, '사용구');
      expect(item.regulationFields[1].value, '헤드 챔피언십');
    });

    test('missing regulation_fields yields empty list', () {
      final data = {
        'blocks': [
          {
            'type': 'cards',
            'entity': 'tournament',
            'items': [
              {
                'id': '11111111-1111-1111-1111-111111111111',
                'title': 'T',
                'sport': 'tennis',
                'start_date': '2026-06-13',
              }
            ],
          }
        ],
      };
      final item = ChatUiBlock.listFromEvent(data).single.tournamentItems.single;
      expect(item.regulationFields, isEmpty);
    });

    test('malformed regulation_fields entries are skipped, capped at 3', () {
      final data = {
        'blocks': [
          {
            'type': 'cards',
            'entity': 'tournament',
            'items': [
              {
                'id': '11111111-1111-1111-1111-111111111111',
                'title': 'T',
                'sport': 'tennis',
                'start_date': '2026-06-13',
                'regulation_fields': [
                  'oops', // not a map
                  {'label': '장소', 'value': '영암'}, // ok
                  {'label': 123, 'value': '무시'}, // non-string label
                  {'label': '빈값', 'value': '   '}, // blank value
                  {'label': '주관', 'value': '협회'}, // ok
                  {'value': '라벨없음'}, // missing label
                  {'label': '사용구', 'value': '헤드'}, // ok (3rd)
                  {'label': '넷째', 'value': '잘림'}, // capped out
                ],
              }
            ],
          }
        ],
      };
      final item = ChatUiBlock.listFromEvent(data).single.tournamentItems.single;
      expect(item.regulationFields.length, 3);
      expect(
        item.regulationFields.map((f) => f.label).toList(),
        ['장소', '주관', '사용구'],
      );
    });

    test('regulation_fields not a list yields empty', () {
      final data = {
        'blocks': [
          {
            'type': 'cards',
            'entity': 'tournament',
            'items': [
              {
                'id': '11111111-1111-1111-1111-111111111111',
                'title': 'T',
                'sport': 'tennis',
                'start_date': '2026-06-13',
                'regulation_fields': {'label': '장소', 'value': '영암'},
              }
            ],
          }
        ],
      };
      final item = ChatUiBlock.listFromEvent(data).single.tournamentItems.single;
      expect(item.regulationFields, isEmpty);
    });

    test('non-string eligible_grades elements are filtered, not thrown', () {
      final data = {
        'blocks': [
          {
            'type': 'cards',
            'entity': 'tournament',
            'items': [
              {
                'id': '11111111-1111-1111-1111-111111111111',
                'title': 'T',
                'sport': 'tennis',
                'start_date': '2026-06-13',
                'eligible_grades': ['ok', 1, null],
              }
            ],
          }
        ],
      };
      final item = ChatUiBlock.listFromEvent(data).single.tournamentItems.single;
      expect(item.eligibleGrades, ['ok']);
    });
  });

  group('ChatTournamentCard', () {
    testWidgets('renders title, region and an action; hides id', (tester) async {
      const item = TournamentChatCardItem(
        id: '11111111-1111-1111-1111-111111111111',
        title: '광주 테니스 오픈',
        sport: 'tennis',
        region: '광주',
        location: '진월국제테니스장',
        startDate: '2026-06-13',
        endDate: '2026-06-13',
        eligible: true,
        eligibleGrades: ['gj_m_gold'],
        entryFee: 30000,
        format: '복식',
      );
      String? sent;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatTournamentCard(
            item: item,
            onAction: (message, entityId) => sent = message,
          ),
        ),
      ));

      expect(find.text('광주 테니스 오픈'), findsOneWidget);
      expect(find.textContaining('광주'), findsWidgets);
      expect(find.textContaining('11111111'), findsNothing);

      await tester.tap(find.text('상세 보기'));
      await tester.pump();
      expect(sent, '상세 알려줘');
    });

    testWidgets('renders regulation fields summary when present',
        (tester) async {
      const item = TournamentChatCardItem(
        id: '11111111-1111-1111-1111-111111111111',
        title: '영암 오픈',
        sport: 'tennis',
        startDate: '2026-06-13',
        eligible: true,
        eligibleGrades: [],
        regulationFields: [
          RegulationField(label: '장소', value: '영암종합스포츠타운'),
          RegulationField(label: '사용구', value: '헤드 챔피언십'),
        ],
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatTournamentCard(
            item: item,
            onAction: (_, __) {},
          ),
        ),
      ));

      expect(
        find.textContaining('영암종합스포츠타운', findRichText: true),
        findsWidgets,
      );
      expect(
        find.textContaining('헤드 챔피언십', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('renders nothing extra when regulation fields empty',
        (tester) async {
      const item = TournamentChatCardItem(
        id: '11111111-1111-1111-1111-111111111111',
        title: '영암 오픈',
        sport: 'tennis',
        startDate: '2026-06-13',
        eligible: true,
        eligibleGrades: [],
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatTournamentCard(
            item: item,
            onAction: (_, __) {},
          ),
        ),
      ));

      expect(find.text('영암 오픈'), findsOneWidget);
      expect(find.text('상세 보기'), findsOneWidget);
    });
  });
}
