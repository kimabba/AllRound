import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allround/models/club_recruiting.dart';
import 'package:allround/widgets/clubs/team_recruiting_widgets.dart';

void main() {
  final posts = List.generate(
    4,
    (index) => RecruitingPostPreview(
      id: 'post-$index',
      clubId: 'club-$index',
      sport: 'tennis',
      clubName: '테니스 모임 $index',
      title: '팀원 모집 $index',
      region: '서울',
      place: '테니스장',
      schedule: '토요일',
      grade: '무관',
      gender: '무관',
      age: '무관',
      position: null,
      fieldCount: 0,
      keeperCount: 0,
      totalCount: 2,
      cost: '무료',
      createdAt: DateTime(2026, 7, 29, 12, index),
    ),
  );

  testWidgets('클럽 탭은 모집글 2개와 전체보기 진입점을 먼저 노출한다', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamRecruitingBoard(
              posts: posts,
              isLoading: false,
              managedClubIds: const {},
              onClosePost: (_) {},
              onOpenPost: (_) {},
              onViewAll: () => opened = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('팀원 모집 0'), findsOneWidget);
    expect(find.text('팀원 모집 1'), findsOneWidget);
    expect(find.text('팀원 모집 2'), findsNothing);
    expect(find.text('팀원 모집 3'), findsNothing);
    await tester.tap(find.text('전체보기'));
    expect(opened, isTrue);
  });

  testWidgets('전체 팀원모집 화면은 모든 글을 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeamRecruitingListScreen(
          posts: posts,
          managedClubIds: const {},
          onClosePost: (_) async => posts,
          onOpenPost: (_) {},
        ),
      ),
    );

    expect(find.text('전체 팀원모집'), findsOneWidget);
    expect(find.text('최신 등록순 · 4개'), findsOneWidget);
    for (var index = 0; index < 4; index++) {
      expect(find.text('팀원 모집 $index'), findsOneWidget);
    }
  });

  testWidgets('마감하면 돌려받은 목록으로 화면이 갱신된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeamRecruitingListScreen(
          posts: posts,
          managedClubIds: {posts.first.clubId},
          onClosePost: (post) async =>
              posts.where((p) => p.id != post.id).toList(growable: false),
          onOpenPost: (_) {},
        ),
      ),
    );

    expect(find.text('팀원 모집 0'), findsOneWidget);
    await tester.tap(find.text('마감하기'));
    await tester.pumpAndSettle();

    expect(find.text('팀원 모집 0'), findsNothing);
    expect(find.text('최신 등록순 · 3개'), findsOneWidget);
  });

  testWidgets('조회 상한에 걸리면 전체가 아님을 알린다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeamRecruitingListScreen(
          posts: posts,
          managedClubIds: const {},
          capped: true,
          onClosePost: (_) async => posts,
          onOpenPost: (_) {},
        ),
      ),
    );

    expect(find.text('최신 등록순 · 4개 (최신 글만 표시)'), findsOneWidget);
  });
}
