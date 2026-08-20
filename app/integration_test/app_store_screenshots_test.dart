import 'package:allround/main.dart' as app;
import 'package:allround/main.dart' show MatchUpApp;
import 'package:allround/models/chat_ui.dart';
import 'package:allround/state/chat_state.dart';
import 'package:allround/testing/e2e_keys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      final exception = tester.takeException();
      if (exception != null) {
        throw TestFailure('스크린샷 화면 렌더링 실패: $exception');
      }
      if (finder.evaluate().isNotEmpty) return;
    }
    throw TestFailure('스크린샷 화면을 찾지 못했습니다: $finder');
  }

  Future<void> capture(
    WidgetTester tester,
    String name,
    Finder ready,
  ) async {
    await waitFor(tester, ready);
    await tester.pump(const Duration(milliseconds: 700));
    final exception = tester.takeException();
    if (exception != null) {
      throw TestFailure('스크린샷 직전 화면 오류: $exception');
    }
    await binding.takeScreenshot(name);
  }

  void goTo(WidgetTester tester, Finder current, String location) {
    GoRouter.of(tester.element(current)).go(location);
  }

  testWidgets('App Store용 주요 화면 7장을 개인정보 없이 캡처한다', (tester) async {
    await app.initializeAllRoundServices(
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(retry: (_, __) => null, child: const MatchUpApp()),
    );

    await capture(
      tester,
      '01-home',
      find.byKey(AllRoundE2EKeys.homeTournamentList),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(AllRoundE2EKeys.homeScreen)),
    );
    final chat = container.read(chatProvider);
    final previewStart = DateTime.now().add(const Duration(days: 14));
    final previewDeadline = DateTime.now().add(const Duration(days: 7));
    String dateOnly(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';

    chat.addUserMessage('가까운 서울 풋살 대회 있어?');
    chat.appendContent(
      chat.lastAssistantIndex,
      '이번 주 신청 가능한 서울 풋살 대회를 찾았어요.',
    );
    chat.addUiBlocks(chat.lastAssistantIndex, [
      ChatUiBlock(
        type: 'cards',
        entity: 'tournament',
        tournamentItems: [
          TournamentChatCardItem(
            id: 'app-store-futsal-cup',
            title: '서울 풋살 챔피언십',
            sport: 'futsal',
            region: '서울',
            location: '잠실 풋살장',
            startDate: dateOnly(previewStart),
            applicationDeadline: dateOnly(previewDeadline),
            eligible: true,
            eligibleGrades: const ['beginner', 'intermediate'],
            entryFee: 100000,
            format: '5대5 조별리그',
          ),
        ],
      ),
    ]);
    chat.finishStreaming();
    goTo(tester, find.byKey(AllRoundE2EKeys.homeScreen), '/chat');
    await capture(
      tester,
      '02-ballboy',
      find.byKey(AllRoundE2EKeys.fullChatScreen),
    );
    chat.hideMiniBar();

    goTo(tester, find.byKey(AllRoundE2EKeys.fullChatScreen), '/tournaments');
    await capture(
      tester,
      '03-tournaments',
      find.byKey(AllRoundE2EKeys.tournamentsScreen),
    );

    goTo(
      tester,
      find.byKey(AllRoundE2EKeys.tournamentsScreen),
      '/tournaments/preview-futsal-1',
    );
    await capture(
      tester,
      '04-tournament-detail',
      find.byKey(AllRoundE2EKeys.tournamentDetailScreen),
    );

    goTo(tester, find.byKey(AllRoundE2EKeys.tournamentDetailScreen), '/clubs');
    await capture(
      tester,
      '05-clubs',
      find.byKey(AllRoundE2EKeys.clubsScreen),
    );

    goTo(
        tester, find.byKey(AllRoundE2EKeys.clubsScreen), '/rules?sport=futsal');
    await capture(
      tester,
      '06-rules',
      find.byKey(AllRoundE2EKeys.rulesReady),
    );

    goTo(tester, find.byKey(AllRoundE2EKeys.rulesScreen), '/profile');
    await capture(
      tester,
      '07-profile',
      find.byKey(AllRoundE2EKeys.profileScreen),
    );
  });
}
