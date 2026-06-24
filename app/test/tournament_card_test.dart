import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/models/tournament.dart';
import 'package:matchup/widgets/tournament_card.dart';

void main() {
  // 카드가 DateFormat('M/d (E)','ko') 를 쓰므로 ko 로케일 데이터를 준비한다.
  setUpAll(() async {
    await initializeDateFormatting('ko');
  });

  Tournament makeTournament({
    DateTime? endDate,
    DateTime? applicationDeadline,
    String? location,
    String? region,
  }) {
    return Tournament(
      id: 't1',
      sport: 'tennis',
      title: '광주 테니스 오픈',
      organizer: '광주광역시테니스협회',
      startDate: DateTime(2026, 6, 13),
      endDate: endDate,
      applicationDeadline: applicationDeadline,
      location: location,
      region: region,
      eligibleGrades: const ['gj_m_gold'],
      status: 'published',
    );
  }

  Widget wrap(Tournament t) => MaterialApp(
        home: Scaffold(
          body: TournamentCard(tournament: t),
        ),
      );

  testWidgets('대회일 라벨과 날짜를 렌더한다', (tester) async {
    await tester.pumpWidget(wrap(makeTournament()));
    expect(find.text('대회'), findsOneWidget);
    expect(find.textContaining('6/13'), findsWidgets);
  });

  testWidgets('신청 마감 라벨과 "~M/D 마감" 텍스트를 렌더한다', (tester) async {
    await tester.pumpWidget(
      wrap(makeTournament(applicationDeadline: DateTime(2026, 6, 20))),
    );
    expect(find.text('신청'), findsOneWidget);
    // 포맷이 'M/d (E)' 라 "~6/20 (토) 마감" 형태가 된다.
    expect(find.textContaining('6/20'), findsOneWidget);
    expect(find.textContaining('마감'), findsWidgets);
  });

  testWidgets('location 을 region 과 함께 노출한다', (tester) async {
    await tester.pumpWidget(
      wrap(makeTournament(location: '진월국제테니스장', region: '광주')),
    );
    expect(find.text('진월국제테니스장 · 광주'), findsOneWidget);
  });

  testWidgets('location 이 null 이면 region 으로 폴백한다', (tester) async {
    await tester.pumpWidget(
      wrap(makeTournament(location: null, region: '전남')),
    );
    expect(find.text('전남'), findsOneWidget);
  });

  testWidgets('마감 미정이면 신청 줄을 그리지 않는다', (tester) async {
    await tester.pumpWidget(wrap(makeTournament(applicationDeadline: null)));
    expect(find.text('신청'), findsNothing);
  });
}
