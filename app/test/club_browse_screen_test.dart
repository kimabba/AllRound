import 'package:allround/models/club_recruiting.dart';
import 'package:allround/models/tournament.dart';
import 'package:allround/screens/clubs/club_browse_screen.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final clubs = [
    Club(
      id: 'club-tennis',
      sport: 'tennis',
      name: '강남 테니스클럽',
      region: '서울 강남구',
      memberCount: 28,
      meetingDays: const ['토'],
      genderPreference: 'mixed',
      monthlyFee: 30000,
    ),
    Club(
      id: 'club-futsal',
      sport: 'futsal',
      name: '잠실 풋살클럽',
      region: '서울 송파구',
      memberCount: 20,
      meetingDays: const ['수'],
      genderPreference: 'male',
      monthlyFee: 20000,
    ),
  ];
  final posts = [
    RecruitingPostPreview(
      id: 'recruiting-tennis',
      clubId: clubs.first.id,
      sport: 'tennis',
      clubName: clubs.first.name,
      title: '주말 복식 회원 모집',
      region: '서울 강남구',
      place: '강남 테니스장',
      schedule: '매주 토요일',
      grade: '신입–3부',
      gender: '혼성',
      age: '20–40대',
      position: '복식',
      fieldCount: 0,
      keeperCount: 0,
      totalCount: 4,
      cost: '월 3만원',
      createdAt: DateTime(2026, 8, 19),
    ),
  ];

  testWidgets('전체보기는 클럽과 팀원 모집 탭에 검색창과 필터를 제공한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ClubBrowseScreen(
          clubs: clubs,
          recruitingPosts: posts,
          recruitingCapped: true,
          initialSports: const {'tennis', 'futsal'},
          favoriteClubIds: const {},
          managedClubIds: const {},
          openRecruitingClubIds: {clubs.first.id},
          onOpenClub: (_) {},
          onFavoriteToggle: (_, __) async {},
          onOpenPost: (_) {},
          onClosePost: (_) async => posts,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('전체보기'), findsOneWidget);
    expect(find.text('클럽 2'), findsOneWidget);
    expect(find.text('팀원 모집 1'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('지역·종목·조건 필터'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '강남');
    await tester.pump();

    expect(find.text('클럽 1'), findsOneWidget);
    expect(find.text('강남 테니스클럽'), findsOneWidget);
    expect(find.text('잠실 풋살클럽'), findsNothing);

    await tester.tap(find.text('팀원 모집 1'));
    await tester.pumpAndSettle();
    expect(find.text('주말 복식 회원 모집'), findsOneWidget);
    expect(find.textContaining('최신 글만 표시'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('전체보기 상세 필터 시트를 열 수 있다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ClubBrowseScreen(
          clubs: clubs,
          recruitingPosts: posts,
          recruitingCapped: false,
          initialSports: const {'tennis'},
          favoriteClubIds: const {},
          managedClubIds: const {},
          openRecruitingClubIds: {clubs.first.id},
          onOpenClub: (_) {},
          onFavoriteToggle: (_, __) async {},
          onOpenPost: (_) {},
          onClosePost: (_) async => posts,
        ),
      ),
    );

    await tester.tap(find.byTooltip('지역·종목·조건 필터'));
    await tester.pumpAndSettle();

    expect(find.text('클럽 전체 필터'), findsOneWidget);
    expect(find.text('종목'), findsOneWidget);
    expect(find.text('지역'), findsOneWidget);
    expect(find.text('모집 상태'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
