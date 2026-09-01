import 'package:allround/widgets/app_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('대회·클럽 메뉴를 표시하고 MY는 제외한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(currentIndex: 0, onChanged: (_) {}),
        ),
      ),
    );

    for (final label in ['대회', '클럽']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('MY'), findsNothing);
    // 룰북은 대회 화면 안에서 연다. '일정'·'모임'은 탭 라벨이 아니다.
    expect(find.text('일정'), findsNothing);
    expect(find.text('모임'), findsNothing);
    expect(find.text('룰북'), findsNothing);
    expect(find.text('코치'), findsNothing);
  });

  testWidgets('클럽 탭은 두 번째 인덱스를 전달한다', (tester) async {
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

    await tester.tap(find.text('클럽'));
    expect(selectedIndex, 1);
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

  testWidgets('볼보이는 클럽 다음에 표시된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(
            currentIndex: 0,
            onChanged: (_) {},
            onChatTap: () {},
          ),
        ),
      ),
    );

    final ballboyX = tester.getCenter(find.text('볼보이')).dx;
    expect(ballboyX, greaterThan(tester.getCenter(find.text('클럽')).dx));
  });

  testWidgets('현재 탭은 채운 아이콘으로, 볼보이는 중립 아이콘으로 구분한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(
            currentIndex: 1,
            onChanged: (_) {},
            onChatTap: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_rounded), findsNothing);
  });
}
