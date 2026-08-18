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
  String? note,
  String? confirmedHolderName,
  String? confirmedHolderId,
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
    note: note,
    confirmedHolderName: confirmedHolderName,
    confirmedHolderId: confirmedHolderId,
  );
}

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );

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
      _wrap(
        ClaimGroupCard(
          group: group,
          onApprove: (_) {},
          onReject: (_) {},
          onRelease: (_) {},
        ),
      ),
    );

    expect(find.text('김평화'), findsWidgets);
    expect(find.text('동명이인'), findsOneWidget);
  });

  // ── 이의신청 ──────────────────────────────────────────────────────────

  test('확정 보유자가 있으면 이의신청 묶음이다', () {
    final group = groupClaimsByPlayer([
      _claim(
        orgPlayerId: 'vudghk2116',
        claimantName: '김평화',
        claimantId: 'u2',
        note: '어등산클럽입니다',
        confirmedHolderName: '먼저김평화',
        confirmedHolderId: 'u1',
      ),
    ]).single;

    expect(group.isDisputed, isTrue);
    expect(group.confirmedHolderName, '먼저김평화');
  });

  test('확정 보유자가 없으면 일반 신청이다', () {
    final group = groupClaimsByPlayer([
      _claim(orgPlayerId: 'lkybks', claimantName: '이기영', claimantId: 'u3'),
    ]).single;

    expect(group.isDisputed, isFalse);
  });

  testWidgets('이의신청 묶음은 기존 보유자를 알리고 승인을 막는다', (tester) async {
    final group = groupClaimsByPlayer([
      _claim(
        orgPlayerId: 'vudghk2116',
        claimantName: '김평화',
        claimantId: 'u2',
        note: '어등산클럽 소속입니다. 010-1234-5678',
        confirmedHolderName: '먼저김평화',
        confirmedHolderId: 'u1',
      ),
    ]).single;
    RankingClaim? released;

    await tester.pumpWidget(
      _wrap(
        ClaimGroupCard(
          group: group,
          onApprove: (_) {},
          onReject: (_) {},
          onRelease: (c) => released = c,
        ),
      ),
    );

    // 관리자가 이름만 보면 못 가린다 — 사유가 화면에 있어야 한다.
    expect(find.text('어등산클럽 소속입니다. 010-1234-5678'), findsOneWidget);
    expect(
      find.textContaining('먼저김평화님과 연결돼 있습니다'),
      findsOneWidget,
    );

    // 기존 확정이 살아 있는 동안 승인은 눌리면 안 된다(23505 로 죽는다).
    final approve = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '승인'),
    );
    expect(approve.onPressed, isNull);

    await tester.tap(find.widgetWithText(OutlinedButton, '기존 연결 해제'));
    expect(released?.confirmedHolderId, 'u1');
  });
}
