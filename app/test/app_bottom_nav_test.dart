import 'package:allround/widgets/app_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('오늘·대회·클럽·코치·MY 탭을 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(
            currentIndex: 0,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    for (final label in ['오늘', '대회', '클럽', '코치', 'MY']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('룰북'), findsNothing);
  });

  testWidgets('코치 탭은 네 번째 인덱스를 전달한다', (tester) async {
    int? selectedIndex;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(
            currentIndex: 0,
            onChanged: (index) => selectedIndex = index,
          ),
        ),
      ),
    );

    await tester.tap(find.text('코치'));
    expect(selectedIndex, 3);
  });
}
