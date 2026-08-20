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

  testWidgets('나의 클럽 카드는 내 클럽 상태를 명확히 표시한다', (tester) async {
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

    expect(find.text('내 클럽'), findsOneWidget);
    expect(find.text('서울 10명'), findsOneWidget);
  });

  testWidgets('원형 로고는 동그라미 안을 채우고 가장자리를 원형으로 자른다', (tester) async {
    final logoClub = Club(
      id: 'logo-club',
      sport: 'futsal',
      name: '풋살 클럽',
      region: '서울',
      logoUrl: 'https://example.com/logo.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SimpleClubAvatar(
            key: const ValueKey('circular-club-logo'),
            club: logoClub,
            size: 48,
            circular: true,
          ),
        ),
      ),
    );

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const ValueKey('circular-club-logo')),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
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

  testWidgets('모임이 없으면 첫 모임 만들기 행동을 안내한다', (tester) async {
    var createTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FirstClubEmptyState(
            onCreate: () => createTapped = true,
          ),
        ),
      ),
    );

    expect(find.text('첫 모임을 만들어보세요'), findsOneWidget);
    expect(find.text('모임 만들기'), findsOneWidget);
    await tester.tap(find.text('모임 만들기'));
    expect(createTapped, isTrue);
  });

  testWidgets('주변 클럽은 지역과 인원 뒤에 거리를 표시한다', (tester) async {
    final nearbyClub = Club(
      id: 'nearby-club',
      sport: 'tennis',
      name: '가까운 테니스 모임',
      region: '서울',
      memberCount: 10,
      distanceKm: 1.24,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SimpleClubTile(
            club: nearbyClub,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    );

    expect(find.text('서울 10명 · 1.2km'), findsOneWidget);
  });
}
