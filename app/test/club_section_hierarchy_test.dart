import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allround/models/tournament.dart';
import 'package:allround/widgets/clubs/club_section_widgets.dart';
import 'package:allround/widgets/clubs/club_tiles.dart';

void main() {
  final club = Club(
    id: 'club-1',
    sport: 'tennis',
    name: '서울 테니스 모임',
    region: '서울',
    memberCount: 10,
  );

  testWidgets('나의 모임 카드는 내 모임 상태를 명확히 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SimpleClubTile(
            club: club,
            isMyClub: true,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    );

    expect(find.text('내 모임'), findsOneWidget);
    expect(find.text('서울 10명'), findsOneWidget);
  });

  testWidgets('추천 섹션 헤더는 아이콘과 설명을 함께 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SimpleSectionHeader(
            title: '추천 모임',
            subtitle: '관심 종목과 지역을 기준으로 추천해요',
            icon: Icons.explore_outlined,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.explore_outlined), findsOneWidget);
    expect(find.text('관심 종목과 지역을 기준으로 추천해요'), findsOneWidget);
  });
}
