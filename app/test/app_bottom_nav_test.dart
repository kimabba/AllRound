import 'package:allround/widgets/app_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('일정·클럽·룰북 탭을 표시한다', (tester) async {
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

    for (final label in ['일정', '클럽', '룰북']) {
      expect(find.text(label), findsOneWidget);
    }
    // 탭에서 빠진 것들 — 대회는 일정 화면의 "전체 보기", 마이는 앱바 우상단.
    expect(find.text('대회'), findsNothing);
    expect(find.text('모임'), findsNothing);
    expect(find.text('MY'), findsNothing);
    expect(find.text('코치'), findsNothing);
  });

  testWidgets('룰북 탭은 세 번째 인덱스를 전달한다', (tester) async {
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

    await tester.tap(find.text('룰북'));
    expect(selectedIndex, 2);
  });

  testWidgets('볼보이 버튼은 탭이 아니라 별도 콜백으로 열린다', (tester) async {
    var chatOpened = false;
    var changedIndex = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(
            currentIndex: 0,
            onChanged: (index) => changedIndex = index,
            onChatTap: () => chatOpened = true,
          ),
        ),
      ),
    );

    expect(find.text('볼보이'), findsOneWidget);
    expect(find.text('BB'), findsNothing);

    await tester.tap(find.text('볼보이'));
    expect(chatOpened, isTrue);
    // 볼보이는 탭 슬롯을 차지하지 않으므로 탭 인덱스를 바꾸지 않는다.
    expect(changedIndex, -1);
  });
}
