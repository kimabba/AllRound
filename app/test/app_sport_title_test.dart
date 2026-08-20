import 'package:allround/widgets/app_sport_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('공통 종목 타이틀이 현재 종목을 표시하고 변경을 전달한다', (tester) async {
    String? selectedSport;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: AppSportTitle(
              sport: 'futsal',
              onSelected: (sport) => selectedSport = sport,
            ),
          ),
        ),
      ),
    );

    expect(find.text('올라운드 풋살'), findsOneWidget);

    await tester.tap(find.text('올라운드 풋살'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('테니스'));
    await tester.pumpAndSettle();

    expect(selectedSport, 'tennis');
  });
}
