import 'package:allround/models/format_review.dart';
import 'package:allround/screens/admin/format_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('검수 큐가 비어 있으면 완료 상태를 표시한다', (tester) async {
    await tester.pumpWidget(_app(queue: const <FormatReviewItem>[]));
    await tester.pumpAndSettle();

    expect(find.text('검수할 요강이 없습니다'), findsOneWidget);
    expect(find.text('새 검수 항목이 생기면 이곳에 표시됩니다.'), findsOneWidget);
  });

  testWidgets('staged 행은 Pureform 정보 위계와 48px 승인 행동을 표시한다', (tester) async {
    await tester.pumpWidget(_app(queue: [_stagedItem()]));
    await tester.pumpAndSettle();

    expect(find.text('스테이징된 대회'), findsOneWidget);
    expect(find.textContaining('참가비'), findsOneWidget);
    expect(find.text('요약 설명'), findsOneWidget);
    expect(find.text('승인'), findsOneWidget);
    expect(find.text('반려'), findsOneWidget);

    final approve = find.widgetWithText(FilledButton, '승인');
    final reject = find.widgetWithText(OutlinedButton, '반려');
    expect(tester.getSize(approve).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(reject).height, greaterThanOrEqualTo(48));
  });

  testWidgets('format_staged가 없는 검증 실패 행은 flags와 반려만 표시한다', (tester) async {
    await tester.pumpWidget(_app(queue: [_failedItem()]));
    await tester.pumpAndSettle();

    expect(find.text('검증 실패 대회'), findsOneWidget);
    expect(find.textContaining('참가비 · not_in_source'), findsOneWidget);
    expect(find.text('반려'), findsOneWidget);
    expect(find.text('승인'), findsNothing);
  });

  testWidgets('승인 성공은 한 번만 요청하고 결과를 안내한다', (tester) async {
    final actions = _FakeActions();
    await tester.pumpWidget(_app(queue: [_stagedItem()], actions: actions));
    await tester.pumpAndSettle();

    await tester.tap(find.text('승인'));
    await tester.pumpAndSettle();

    expect(actions.approvedIds, ['tid-staged']);
    expect(find.text('요강을 승인했습니다.'), findsOneWidget);
  });

  testWidgets('stale 승인 응답은 새로고침 안내를 표시한다', (tester) async {
    final actions = _FakeActions(approveResult: false);
    await tester.pumpWidget(_app(queue: [_stagedItem()], actions: actions));
    await tester.pumpAndSettle();

    await tester.tap(find.text('승인'));
    await tester.pumpAndSettle();

    expect(find.textContaining('원문이 변경됐습니다'), findsOneWidget);
  });

  testWidgets('검증 실패 행도 반려 사유와 함께 처리한다', (tester) async {
    final actions = _FakeActions();
    await tester.pumpWidget(_app(queue: [_failedItem()], actions: actions));
    await tester.pumpAndSettle();

    await tester.tap(find.text('반려'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '원문에 참가비 확인 필요');
    await tester.tap(find.text('반려 확정'));
    await tester.pumpAndSettle();

    expect(actions.rejectedIds, ['tid-failed']);
    expect(actions.lastReason, '원문에 참가비 확인 필요');
    expect(find.text('요강을 반려했습니다.'), findsOneWidget);
  });

  testWidgets('큰 글자와 좁은 화면에서도 검수 행동이 잘리지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: _app(queue: [_stagedItem()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('승인'), findsOneWidget);
    expect(find.text('반려'), findsOneWidget);
  });
}

Widget _app({
  required List<FormatReviewItem> queue,
  FormatReviewActions? actions,
}) {
  return ProviderScope(
    overrides: [
      formatReviewQueueProvider.overrideWith((ref) async => queue),
      if (actions != null)
        formatReviewActionsProvider.overrideWithValue(actions),
    ],
    child: MaterialApp(
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: const FormatReviewScreen(),
    ),
  );
}

FormatReviewItem _stagedItem() {
  return FormatReviewItem.fromJson({
    'id': 'tid-staged',
    'title': '스테이징된 대회',
    'source_url': 'https://example.com/tid-staged',
    'format_source_hash': 'hash-staged',
    'format_staged': {
      'regulation_fields': [
        {'label': '참가비', 'value': '30,000원'},
      ],
      'regulation_notes': ['입금 전 참가 자격을 확인하세요.'],
      'description': '요약 설명',
    },
    'format_flags': null,
  });
}

FormatReviewItem _failedItem() {
  return FormatReviewItem.fromJson({
    'id': 'tid-failed',
    'title': '검증 실패 대회',
    'source_url': 'https://example.com/tid-failed',
    'format_source_hash': 'hash-failed',
    'format_staged': null,
    'format_flags': [
      {'code': 'not_in_source', 'field': '참가비', 'masked': '3*,000원'},
    ],
  });
}

class _FakeActions implements FormatReviewActions {
  _FakeActions({this.approveResult = true});

  final bool approveResult;
  final List<String> approvedIds = [];
  final List<String> rejectedIds = [];
  String? lastReason;

  @override
  Future<bool> approve(FormatReviewItem item) async {
    approvedIds.add(item.id);
    return approveResult;
  }

  @override
  Future<bool> reject(FormatReviewItem item, String reason) async {
    rejectedIds.add(item.id);
    lastReason = reason;
    return true;
  }
}
