import 'package:allround/models/tournament.dart';
import 'package:allround/screens/friend_schedule_screen.dart';
import 'package:allround/screens/more_screen.dart';
import 'package:allround/screens/tournaments/tournaments_screen.dart';
import 'package:allround/screens/tournaments/tournament_submit_screen.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:allround/theme/tokens.dart';
import 'package:allround/widgets/profile/profile_settings_widgets.dart';
import 'package:allround/widgets/profile/profile_records_widgets.dart';
import 'package:allround/widgets/profile/profile_sports_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('친구 일정은 작은 화면과 큰 글자에서 48px 월 이동을 유지한다', (tester) async {
    _setViewport(tester, const Size(320, 568));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: FriendScheduleScreen(initialDate: DateTime(2026, 7, 19)),
          ),
        ),
      ),
    );

    expect(find.byKey(AllRoundE2EKeys.friendScheduleScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byTooltip('이전 달')).width,
        greaterThanOrEqualTo(AppSizes.touchTarget));
    expect(tester.getSize(find.byTooltip('다음 달')).height,
        greaterThanOrEqualTo(AppSizes.touchTarget));
    expect(find.byTooltip('검색'), findsNothing);
    expect(find.byTooltip('알림'), findsNothing);
  });

  testWidgets('전체 메뉴는 390px 다크 화면에서 평면 목록 위계를 유지한다', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isAdminProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const MoreScreen(),
        ),
      ),
    );

    await tester.pump();
    expect(find.byKey(AllRoundE2EKeys.moreScreen), findsOneWidget);
    expect(find.text('내 메뉴'), findsOneWidget);
    expect(find.text('룰북'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MY 화면 설정은 작은 화면과 큰 글자에서 세 선택지를 유지한다', (tester) async {
    _setViewport(tester, const Size(320, 568));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: SingleChildScrollView(child: AppearanceSection()),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(AllRoundE2EKeys.profileAppearanceSection),
      findsOneWidget,
    );
    expect(find.text('자동'), findsOneWidget);
    expect(find.text('라이트'), findsOneWidget);
    expect(find.text('다크'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MY 종목과 대회 기록은 320px 200% 글자에서 넘치지 않는다', (tester) async {
    _setViewport(tester, const Size(320, 568));
    final tournament = Tournament(
      id: 'responsive-record',
      sport: 'tennis',
      title: '매우 긴 한글 대회명을 가진 전국 생활체육 테니스 챔피언십',
      organizer: 'QA',
      startDate: DateTime(2026, 7, 23),
      region: '광주',
      eligibleGrades: const ['y1to3'],
      status: 'published',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  children: [
                    SportCard(
                      sport: UserSport(
                        sport: 'tennis',
                        grade: 'y1to3',
                        isPrimary: true,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TournamentRecordsList(tournaments: [tournament]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('기본 종목'), findsOneWidget);
    expect(find.text(tournament.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('대회 달력은 320px 200% 글자에서 48px 조작을 유지한다', (tester) async {
    _setViewport(tester, const Size(320, 568));
    final tournament = Tournament(
      id: 'responsive-calendar',
      sport: 'tennis',
      title: '달력 반응형 검증 대회',
      organizer: 'QA',
      startDate: DateTime.now().add(const Duration(days: 2)),
      region: '서울',
      eligibleGrades: const ['y1to3'],
      status: 'published',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteIdsProvider.overrideWith((ref) async => <String>{}),
          userSportsProvider.overrideWith(
            (ref) async => [
              UserSport(
                sport: 'tennis',
                grade: 'y1to3',
                isPrimary: true,
              ),
            ],
          ),
          userTennisOrgsProvider.overrideWith((ref) async => const []),
          homeTournamentsProvider.overrideWith((ref) async => [tournament]),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: TournamentsScreen(previewTournaments: [tournament]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byTooltip('이전 달')).width,
      greaterThanOrEqualTo(AppSizes.touchTarget),
    );
    expect(
      tester.getSize(find.byTooltip('다음 달')).height,
      greaterThanOrEqualTo(AppSizes.touchTarget),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('대회 제보는 작은 화면에서도 섹션 입력과 제출 행동을 잇는다', (tester) async {
    _setViewport(tester, const Size(320, 568));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: TournamentSubmitScreen(),
          ),
        ),
      ),
    );

    expect(find.byKey(AllRoundE2EKeys.tournamentSubmitScreen), findsOneWidget);
    expect(find.text('기본 정보'), findsOneWidget);
    final submitButton = find.widgetWithText(FilledButton, '제보하기');
    expect(submitButton, findsOneWidget);
    expect(
      tester.getSize(submitButton).height,
      greaterThanOrEqualTo(AppSizes.touchTarget),
    );
    expect(tester.getBottomRight(submitButton).dy, lessThanOrEqualTo(568));
    expect(tester.takeException(), isNull);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
