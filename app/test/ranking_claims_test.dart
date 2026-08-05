import 'package:allround/models/org_ranking.dart';
import 'package:allround/screens/admin/ranking_claims_tab.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

RankingClaim _claim({
  required String orgPlayerId,
  required String claimantName,
  required String claimantId,
}) {
  return RankingClaim(
    orgCode: 'gj',
    orgPlayerId: orgPlayerId,
    playerName: '김평화',
    divisionCode: 'gj_m_gold',
    rank: 1,
    clubRaw: '어등산/',
    claimantName: claimantName,
    claimantId: claimantId,
    claimedAt: DateTime(2026, 8, 3),
  );
}

void main() {
  test('같은 협회 선수에 대한 클레임은 한 묶음이 된다', () {
    final groups = groupClaimsByPlayer([
      _claim(orgPlayerId: 'vudghk2116', claimantName: '김평화', claimantId: 'u1'),
      _claim(orgPlayerId: 'vudghk2116', claimantName: '동명이인', claimantId: 'u2'),
      _claim(orgPlayerId: 'lkybks', claimantName: '이기영', claimantId: 'u3'),
    ]);

    expect(groups.length, 2);
    final contested = groups.firstWhere((g) => g.orgPlayerId == 'vudghk2116');
    expect(contested.claimants.length, 2);
    expect(contested.isContested, isTrue);
  });

  test('신청자가 하나면 경합이 아니다', () {
    final groups = groupClaimsByPlayer([
      _claim(orgPlayerId: 'lkybks', claimantName: '이기영', claimantId: 'u3'),
    ]);

    expect(groups.single.isContested, isFalse);
  });

  testWidgets('경합 묶음은 신청자를 모두 보여준다', (tester) async {
    final group = groupClaimsByPlayer([
      _claim(orgPlayerId: 'vudghk2116', claimantName: '김평화', claimantId: 'u1'),
      _claim(orgPlayerId: 'vudghk2116', claimantName: '동명이인', claimantId: 'u2'),
    ]).single;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ClaimGroupCard(
              group: group,
              onApprove: (_) {},
              onReject: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('김평화'), findsWidgets);
    expect(find.text('동명이인'), findsOneWidget);
  });
}
