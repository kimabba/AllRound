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
}
