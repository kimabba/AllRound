import 'package:allround/models/club_event.dart';
import 'package:allround/models/tournament.dart';
import 'package:allround/screens/clubs/club_detail_screen.dart';
import 'package:allround/services/api.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:allround/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RejectedClubApi extends ApiService {
  _RejectedClubApi(this.club)
      : super(
          SupabaseClient(
            'http://127.0.0.1:54321',
            'rejected-club-test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final Club club;

  @override
  Future<Club> getClub(String clubId) async => club;

  @override
  Future<List<ClubMember>> clubMembers(String clubId) async => const [];

  @override
  Future<List<ClubEvent>> clubEvents(String clubId) async => const [];
}

Widget _testApp(Club club, {double textScale = 1}) {
  return ProviderScope(
    overrides: [
      apiProvider.overrideWithValue(_RejectedClubApi(club)),
      clubFavoriteIdsProvider.overrideWith((ref) async => const {}),
      currentUserProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      key: ValueKey(textScale),
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: ClubDetailScreen(club: club),
    ),
  );
}

void main() {
  testWidgets('반려 사유 팝업은 작은 화면에서 닫히지 않고 필수 행동을 제공한다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final club = Club(
      id: 'rejected-club',
      sport: 'tennis',
      name: '라켓 클럽',
      status: 'rejected',
      statusReason:
          '활동 지역과 정기 모임 장소를 조금 더 자세히 적어주세요. 확인 가능한 내용을 보완하면 다시 심사를 요청할 수 있습니다.',
      myRole: 'owner',
    );

    await tester.pumpWidget(_testApp(club));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('반려 사유'), findsOneWidget);
    expect(find.textContaining('활동 지역과 정기 모임 장소'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('club-rejected-status-card')), findsNothing);

    final dialog = find.byKey(const ValueKey('club-rejected-review-dialog'));
    expect(dialog, findsOneWidget);

    final actions = [
      find.widgetWithText(TextButton, '삭제'),
      find.widgetWithText(OutlinedButton, '수정'),
      find.widgetWithText(FilledButton, '재심사'),
    ];
    for (final action in actions) {
      expect(action, findsOneWidget);
      expect(
        tester.getSize(action).height,
        greaterThanOrEqualTo(AppSizes.touchTarget),
      );
    }
    final editBottom = tester.getBottomLeft(actions[1]).dy;
    final resubmitTop = tester.getTopLeft(actions[2]).dy;
    expect(resubmitTop - editBottom, greaterThanOrEqualTo(AppSpacing.sm));

    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    expect(dialog, findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '수정'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller?.index, 4);

    await tester.pumpWidget(_testApp(club, textScale: 1.3));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(dialog, findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();
    expect(find.text('반려 클럽 삭제'), findsOneWidget);
  });
}
