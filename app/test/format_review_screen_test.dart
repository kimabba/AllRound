import 'package:allround/screens/admin/format_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('검수 큐가 비어 있으면 안내 문구를 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          formatReviewQueueProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[],
          ),
        ],
        child: const MaterialApp(home: FormatReviewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('검수할 요강이 없습니다.'), findsOneWidget);
  });

  testWidgets('staged 행은 승인/반려 버튼을 모두 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          formatReviewQueueProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[
              {
                'id': 'tid-staged',
                'title': '스테이징된 대회',
                'source_url': 'https://example.com/tid-staged',
                'format_staged': {
                  'regulation_fields': [
                    {'label': '참가비', 'value': '30,000원'},
                  ],
                  'description': '요약 설명',
                },
                'format_flags': null,
              },
            ],
          ),
        ],
        child: const MaterialApp(home: FormatReviewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('스테이징된 대회'), findsOneWidget);
    expect(find.text('참가비: 30,000원'), findsOneWidget);
    expect(find.text('요약: 요약 설명'), findsOneWidget);
    expect(find.text('승인'), findsOneWidget);
    expect(find.text('반려'), findsOneWidget);
  });

  testWidgets('format_staged 가 없는 검증 실패 행은 flags 요약과 반려만 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          formatReviewQueueProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[
              {
                'id': 'tid-flags',
                'title': '검증 실패 대회',
                'source_url': 'https://example.com/tid-flags',
                'format_staged': null,
                'format_flags': [
                  {
                    'code': 'not_in_source',
                    'field': '참가비',
                    'masked': '3*,000원',
                  },
                  {
                    'code': 'unusual',
                    'field': '_model',
                    'masked': '',
                  },
                ],
              },
            ],
          ),
        ],
        child: const MaterialApp(home: FormatReviewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('검증 실패 대회'), findsOneWidget);
    // raw code 대신 한국어 라벨을 노출한다.
    expect(find.textContaining('검증 실패: 참가비 — 원문에서 확인 안 됨'), findsOneWidget);
    // _model 플래그는 필드명을 숨기고 라벨만 표시한다.
    expect(find.textContaining('검증 실패: 모델이 특이 요강으로 표시'), findsOneWidget);
    expect(find.textContaining('_model'), findsNothing);
    expect(find.textContaining('not_in_source'), findsNothing);
    expect(find.text('반려'), findsOneWidget);
    expect(find.text('승인'), findsNothing);
  });
}
