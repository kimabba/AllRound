import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allround/widgets/clubs/club_filter_widgets.dart';

void main() {
  testWidgets('모임 상세검색은 헤더 닫기 버튼으로 이전 화면에 돌아간다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const ClubFilterSheet(
                    initialFilters: ClubSearchFilters(),
                    initialInterests: {'tennis', 'futsal'},
                    title: '상세검색',
                    icon: Icons.tune_rounded,
                    accentColor: Colors.blue,
                    onAccentColor: Colors.white,
                  ),
                ),
                child: const Text('상세검색 열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('상세검색 열기'));
    await tester.pumpAndSettle();
    expect(find.text('상세검색'), findsOneWidget);
    expect(find.byTooltip('상세검색 닫기'), findsOneWidget);

    await tester.tap(find.byTooltip('상세검색 닫기'));
    await tester.pumpAndSettle();
    expect(find.text('상세검색'), findsNothing);
  });
}
