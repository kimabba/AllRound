import 'package:allround/models/moderation.dart';
import 'package:allround/models/tournament.dart';
import 'package:allround/screens/admin/moderation_screen.dart';
import 'package:allround/screens/tournaments/tournaments_screen.dart';
import 'package:allround/services/api.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeModerationApi extends ApiService {
  _FakeModerationApi(this.reports)
      : super(
          SupabaseClient(
            'http://127.0.0.1:54321',
            'qa-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final List<UgcReport> reports;

  @override
  Future<List<UgcReport>> adminUgcReports({String? status}) async => reports;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
  });

  testWidgets('대회 상세검색은 작은 화면의 키보드 위에서 필터 선택 후 키보드를 닫는다', (tester) async {
    _useSmallPhone(tester);

    final tournament = Tournament(
      id: 'keyboard-search-test',
      sport: 'tennis',
      title: '키보드 검색 테스트 대회',
      organizer: 'QA',
      startDate: DateTime(2026, 8, 20),
      region: '서울',
      eligibleGrades: const ['y1to3'],
      status: 'published',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteIdsProvider.overrideWith((ref) async => <String>{}),
          unreadNotificationCountProvider.overrideWith((ref) async => 0),
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
          theme: AppTheme.light(),
          home: TournamentsScreen(previewTournaments: [tournament]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('상세검색'));
    await tester.pumpAndSettle();

    final queryField = find.byType(TextField);
    await tester.enterText(queryField, '여름 대회');
    await tester.showKeyboard(queryField);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();

    expect(find.text('검색'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.testTextInput.isVisible, isTrue);

    final regionChip = find.widgetWithText(FilterChip, '서울');
    await tester.ensureVisible(regionChip);
    await tester.tap(regionChip);
    await tester.pump();

    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('관리자 처리 다이얼로그는 작은 화면의 키보드 위에서도 넘치지 않는다', (tester) async {
    _useSmallPhone(tester);
    final report = UgcReport(
      id: 'keyboard-moderation-test',
      targetType: 'club_post',
      targetId: 'post-1',
      reason: UgcReportReason.spam,
      status: 'pending',
      details: '반복 광고 게시물',
      evidencePaths: const [],
      snapshot: const {'content': '광고 게시물'},
      createdAt: DateTime(2026, 8, 6),
      reporterName: '신고자',
      reportedUserName: '작성자',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(_FakeModerationApi([report])),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ModerationScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('광고·도배'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제 · 제재 처리'));
    await tester.pumpAndSettle();

    final noteField = find.byType(TextField);
    await tester.enterText(noteField, '운영 정책 위반');
    await tester.showKeyboard(noteField);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();

    expect(find.text('처리 확정'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _useSmallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}
