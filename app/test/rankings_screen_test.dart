import 'package:allround/models/org_ranking.dart';
import 'package:allround/screens/rankings/rankings_screen.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

OrgRankingRow _row({
  required int rank,
  required String name,
  required int points,
  String? orgPlayerId,
}) {
  return OrgRankingRow(
    orgCode: 'gj',
    divisionCode: 'gj_m_gold',
    rank: rank,
    playerName: name,
    rankPoints: points,
    totalPoints: points,
    orgPlayerId: orgPlayerId,
    clubRaw: '어등산/',
  );
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('순위표 행이 렌더링된다', (tester) async {
    await _pump(
      tester,
      RankingList(
        rows: [
          _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'vudghk2116'),
          _row(rank: 2, name: '이기영', points: 2562, orgPlayerId: 'lkybks'),
        ],
        linkedOrgPlayerId: null,
      ),
    );

    expect(find.text('김평화'), findsOneWidget);
    expect(find.text('이기영'), findsOneWidget);
  });

  testWidgets('출처 표기가 항상 보인다', (tester) async {
    await _pump(tester, const RankingSourceNotice(orgLabel: '광주광역시테니스협회'));

    expect(find.textContaining('광주광역시테니스협회'), findsOneWidget);
    expect(find.textContaining('협회 공표가 우선'), findsOneWidget);
    // 미가입자도 자기 이름을 발견하는 유일한 자리라, 삭제·정정 요청 연락처가
    // 상시 노출돼야 한다(privacy-policy.html 7항과 같은 주소).
    expect(find.textContaining('삭제'), findsOneWidget);
    expect(find.textContaining('play@jyoungad.kr'), findsOneWidget);
    // fetchedAt 을 안 주면 기준일 줄은 생략된다(로드 전·행 없음 케이스).
    expect(find.textContaining('기준'), findsNothing);
  });

  testWidgets('기준일이 주어지면 표시된다', (tester) async {
    // 연초 협회 포인트 리셋 등으로 미러가 갱신을 건너뛰면 화면이 옛 데이터를
    // "현재"처럼 보여줄 위험이 있다 — fetched_at 표시가 그 방지책이다.
    await _pump(
      tester,
      RankingSourceNotice(
        orgLabel: '광주광역시테니스협회',
        fetchedAt: DateTime.utc(2026, 8, 3, 21),
      ),
    );

    expect(find.textContaining('기준'), findsOneWidget);
  });

  testWidgets('내 계정과 연결된 행은 강조된다', (tester) async {
    await _pump(
      tester,
      RankingList(
        rows: [
          _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'vudghk2116'),
          _row(rank: 2, name: '이기영', points: 2562, orgPlayerId: 'lkybks'),
        ],
        linkedOrgPlayerId: 'vudghk2116',
      ),
    );

    expect(find.byKey(const ValueKey('ranking-row-mine')), findsOneWidget);
  });

  test('검색어는 이름과 소속 둘 다에서 부분일치로 거른다', () {
    final rows = [
      _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'a'),
      _row(rank: 2, name: '이기영', points: 2562, orgPlayerId: 'b'),
    ];

    expect(filterRankingRows(rows, '').length, 2);
    expect(filterRankingRows(rows, '  ').length, 2);
    expect(filterRankingRows(rows, '평화').single.playerName, '김평화');
    // 소속(clubRaw) 도 검색 대상 — 같은 클럽 사람을 한 번에 본다.
    expect(filterRankingRows(rows, '어등산').length, 2);
    expect(filterRankingRows(rows, '없는이름'), isEmpty);
  });

  testWidgets('신청 가능한 행에만 본인 버튼이 붙는다', (tester) async {
    OrgRankingRow? claimed;
    await _pump(
      tester,
      RankingList(
        rows: [
          _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'a'),
          _row(rank: 2, name: '이기영', points: 2562, orgPlayerId: 'b'),
        ],
        linkedOrgPlayerId: null,
        claimableOrgPlayerIds: const {'a'},
        onClaim: (row) => claimed = row,
      ),
    );

    expect(find.text('본인'), findsOneWidget);
    await tester.tap(find.text('본인'));
    expect(claimed?.orgPlayerId, 'a');
  });

  testWidgets('신청 자격이 없으면(등록 부서 밖) 버튼이 하나도 안 뜬다', (tester) async {
    await _pump(
      tester,
      RankingList(
        rows: [_row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'a')],
        linkedOrgPlayerId: null,
        onClaim: (_) {},
      ),
    );

    expect(find.text('본인'), findsNothing);
  });

  testWidgets('후보가 있으면 클레임 카드가 뜬다', (tester) async {
    await _pump(
      tester,
      RankingClaimPrompt(
        candidate: _row(
          rank: 12,
          name: '김평화',
          points: 340,
          orgPlayerId: 'vudghk2116',
        ),
        onClaim: () {},
      ),
    );

    expect(find.textContaining('본인'), findsOneWidget);
  });
}
