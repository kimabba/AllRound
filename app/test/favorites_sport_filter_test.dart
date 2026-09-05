import 'package:allround/models/tournament.dart';
import 'package:allround/screens/favorites_screen.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Tournament _tournament(String id, String sport, String title) {
  return Tournament.fromJson({
    'id': id,
    'title': title,
    'sport': sport,
    'region': '광주',
    'start_date': '2026-10-01',
    'end_date': '2026-10-01',
    'status': 'published',
  });
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
  });

  Future<void> pumpFavorites(
    WidgetTester tester, {
    required String activeSport,
    required List<Tournament> tournaments,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeSportProvider.overrideWithValue(activeSport),
          myFavoriteTournamentsProvider.overrideWith(
            (ref) async => tournaments,
          ),
          myFavoriteClubsProvider.overrideWith((ref) async => []),
          favoriteIdsProvider.overrideWith(
            (ref) async => tournaments.map((t) => t.id).toSet(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const FavoritesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final mixed = [
    _tournament('t-1', 'tennis', '광주 테니스 오픈'),
    _tournament('t-2', 'futsal', '광주 풋살 리그'),
  ];

  testWidgets('관심 대회는 현재 종목만 보인다', (tester) async {
    await pumpFavorites(tester, activeSport: 'tennis', tournaments: mixed);

    expect(find.text('광주 테니스 오픈'), findsOneWidget);
    expect(find.text('광주 풋살 리그'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('현재 종목에 스크랩이 없으면 다른 종목에 있다고 안내한다', (tester) async {
    await pumpFavorites(
      tester,
      activeSport: 'futsal',
      tournaments: [_tournament('t-1', 'tennis', '광주 테니스 오픈')],
    );

    expect(find.text('광주 테니스 오픈'), findsNothing);
    expect(find.textContaining('다른 종목에 관심 대회 1개'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
