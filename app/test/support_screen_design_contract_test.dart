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
import 'package:allround/widgets/profile/profile_hero_widgets.dart';
import 'package:allround/widgets/profile/profile_quick_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
  });

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

  testWidgets('MY 앱 설정은 알림과 세 화면 모드를 함께 보여준다', (tester) async {
    _setViewport(tester, const Size(320, 568));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: SingleChildScrollView(
                  child: AppSettingsSection(
                    tournamentNotificationsEnabled: true,
                    clubNotificationsEnabled: true,
                    coachNotificationsEnabled: false,
                    onNotificationTap: () {},
                  ),
                ),
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
    expect(find.text('앱 설정'), findsOneWidget);
    expect(find.text('알림 설정'), findsOneWidget);
    expect(find.text('2개 알림 켜짐'), findsOneWidget);
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

  testWidgets('MY 스포츠와 활동 목록은 320px 200% 글자에서 넘치지 않는다', (tester) async {
    _setViewport(tester, const Size(320, 568));
    final sports = [
      UserSport(sport: 'futsal', grade: 'beginner', isPrimary: true),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myTournamentRecordsProvider.overrideWith((ref) async => const []),
          myClubsProvider.overrideWith((ref) async => const []),
          userSportsProvider.overrideWith((ref) async => sports),
          userTennisOrgsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: CustomScrollView(
                slivers: [
                  ProfileHeroSliver(
                    initial: '올',
                    title: '매우 긴 이름을 사용하는 올라운드 사용자',
                    subtitle: 'long-profile-address@example.com',
                    infoLine: '실명 사용자 · 만 30세',
                    sports: AsyncData(sports),
                    tennisOrgs: const AsyncData([]),
                    avatarBytes: null,
                    avatarUrl: null,
                    onAvatarTap: () {},
                    onNotificationsTap: () {},
                    unreadNotificationCount: 3,
                    onMoreTap: () {},
                  ),
                  const SliverPadding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    sliver: SliverToBoxAdapter(child: ProfileQuickActions()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('내 스포츠'), findsOneWidget);
    expect(find.text('풋살 · 기본 종목'), findsOneWidget);
    expect(find.text('내 활동'), findsOneWidget);
    expect(find.text('관심 대회'), findsOneWidget);
    expect(find.text('내 클럽'), findsOneWidget);
    expect(find.text('룰북'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('기본 MY 프로필 카드는 불필요한 상단 공백을 줄인다', (tester) async {
    _setViewport(tester, const Size(390, 844));
    final theme = AppTheme.light();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                ProfileHeroSliver(
                  initial: '올',
                  title: '올라운드',
                  subtitle: 'allround@example.com',
                  infoLine: null,
                  sports: const AsyncData([]),
                  tennisOrgs: const AsyncData([]),
                  avatarBytes: null,
                  avatarUrl: null,
                  onAvatarTap: () {},
                  onNotificationsTap: () {},
                  unreadNotificationCount: 0,
                  onMoreTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final heroCard = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.color == theme.colorScheme.primary &&
          decoration.borderRadius == AppRadius.hero;
    });

    expect(heroCard, findsOneWidget);
    expect(tester.getSize(heroCard).height, lessThanOrEqualTo(204));
    expect(tester.takeException(), isNull);
  });

  testWidgets('MY 프로필 헤더는 본문과 함께 스크롤되어 화면을 덮지 않는다', (tester) async {
    _setViewport(tester, const Size(390, 844));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                ProfileHeroSliver(
                  initial: '올',
                  title: '올라운드',
                  subtitle: 'allround@example.com',
                  infoLine: null,
                  sports: const AsyncData([]),
                  tennisOrgs: const AsyncData([]),
                  avatarBytes: null,
                  avatarUrl: null,
                  onAvatarTap: () {},
                  onNotificationsTap: () {},
                  unreadNotificationCount: 0,
                  onMoreTap: () {},
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 1400)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('MY'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MY 도움말은 고객센터와 대회 등록 문의만 제공한다', (tester) async {
    var customerSupportTapped = false;
    var tournamentInquiryTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ProfileServiceSection(
            onCustomerSupportTap: () => customerSupportTapped = true,
            onTournamentInquiryTap: () => tournamentInquiryTapped = true,
          ),
        ),
      ),
    );

    expect(find.text('도움말'), findsOneWidget);
    expect(find.text('고객센터'), findsOneWidget);
    expect(find.text('대회 등록 문의'), findsOneWidget);
    expect(find.text('룰북'), findsNothing);

    await tester.tap(find.text('고객센터'));
    await tester.tap(find.text('대회 등록 문의'));

    expect(customerSupportTapped, isTrue);
    expect(tournamentInquiryTapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iPhone 안전영역에서 MY 상단 버튼과 프로필 카드가 겹치지 않는다', (tester) async {
    _setViewport(tester, const Size(390, 844));
    final theme = AppTheme.light();
    final sports = [
      UserSport(sport: 'tennis', grade: 'local_beginner', isPrimary: true),
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(top: 47)),
            child: Scaffold(
              body: CustomScrollView(
                slivers: [
                  ProfileHeroSliver(
                    initial: '올',
                    title: '올라운드',
                    subtitle: 'allround@example.com',
                    infoLine: '만 30세',
                    sports: AsyncData(sports),
                    tennisOrgs: const AsyncData([]),
                    avatarBytes: null,
                    avatarUrl: null,
                    onAvatarTap: () {},
                    onNotificationsTap: () {},
                    unreadNotificationCount: 1,
                    onMoreTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final notificationButton = find.widgetWithIcon(
      IconButton,
      Icons.notifications_none_rounded,
    );
    final heroCard = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.color == theme.colorScheme.primary &&
          decoration.borderRadius == AppRadius.hero;
    });

    expect(notificationButton, findsOneWidget);
    expect(heroCard, findsOneWidget);
    expect(
      tester.getBottomLeft(notificationButton).dy,
      lessThan(tester.getTopLeft(heroCard).dy),
    );
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

    await tester.scrollUntilVisible(
      find.text('담당자 정보'),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('담당자 정보'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
