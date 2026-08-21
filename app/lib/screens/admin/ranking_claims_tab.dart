import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../config.dart';
import '../../models/org_ranking.dart';
import '../../state/providers.dart';
import '../../utils/grade_labels.dart';

/// pending 클레임을 협회 선수 단위로 묶는다. 경합을 관리자가 보게 하는 것이
/// 이 화면의 존재 이유이므로, 묶기는 순수 함수로 두어 테스트로 고정한다.
List<ClaimGroup> groupClaimsByPlayer(List<RankingClaim> claims) {
  final byPlayer = <String, List<RankingClaim>>{};
  for (final c in claims) {
    byPlayer.putIfAbsent('${c.orgCode}/${c.orgPlayerId}', () => []).add(c);
  }
  return byPlayer.values.map((group) {
    final first = group.first;
    return ClaimGroup(
      orgCode: first.orgCode,
      orgPlayerId: first.orgPlayerId,
      playerName: first.playerName,
      divisionCode: first.divisionCode,
      rank: first.rank,
      clubRaw: first.clubRaw,
      // 선수 단위 정보라 묶음 안에서 전부 같다 — 대표값 하나만 올린다.
      confirmedHolderName: first.confirmedHolderName,
      confirmedHolderId: first.confirmedHolderId,
      claimants: group,
    );
  }).toList();
}

String _fmtTs(DateTime dt) {
  final l = dt.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} '
      '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

// ── 경합 묶음 카드 ────────────────────────────────────────────────────────────

class ClaimGroupCard extends StatelessWidget {
  const ClaimGroupCard({
    super.key,
    required this.group,
    required this.onApprove,
    required this.onReject,
    required this.onRelease,
  });

  final ClaimGroup group;
  final void Function(RankingClaim claim) onApprove;
  final void Function(RankingClaim claim) onReject;

  /// 기존 확정 연결 해제. 이의신청 묶음에서만 쓰인다.
  final void Function(RankingClaim claim) onRelease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tagStyle = theme.textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.playerName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (group.isContested)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '경합 ${group.claimants.length}건',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${divisionLabel(group.divisionCode)} · ${group.rank}위'
              '${group.clubRaw != null && group.clubRaw!.isNotEmpty ? ' · ${group.clubRaw}' : ''}',
              style: tagStyle,
            ),
            // 이미 주인이 있는 선수 — 풀기 전에는 승인이 DB 에서 막힌다.
            // 관리자가 먼저 알아야 "승인 실패"만 보고 끝나지 않는다.
            if (group.isDisputed) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '이의신청 — 지금은 ${group.confirmedHolderName ?? '알 수 없음'}님과 연결돼 있습니다',
                      style: tagStyle?.copyWith(color: Colors.deepOrange),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '기존 연결을 먼저 풀어야 아래 승인이 됩니다.',
                      style: tagStyle?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                      ),
                      onPressed: () => onRelease(group.claimants.first),
                      child: const Text('기존 연결 해제'),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(height: 20),
            for (final claimant in group.claimants) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          claimant.claimantName,
                          style: theme.textTheme.bodyLarge,
                        ),
                        Text(
                          '신청: ${_fmtTs(claimant.claimedAt)}',
                          style: tagStyle?.copyWith(color: Colors.grey),
                        ),
                        // 이의신청 사유. 이름이 같은 두 사람을 가릴 유일한 재료다.
                        if (claimant.note != null &&
                            claimant.note!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(claimant.note!, style: tagStyle),
                        ],
                      ],
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                    ),
                    // 기존 확정이 살아 있으면 승인은 23505 로 실패한다 —
                    // 눌리게 두면 관리자가 원인 모를 에러만 본다.
                    onPressed:
                        group.isDisputed ? null : () => onApprove(claimant),
                    child: const Text('승인'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                    ),
                    onPressed: () => onReject(claimant),
                    child: const Text('반려'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 반려된 클레임 (취소 = 삭제) ───────────────────────────────────────────────

class RejectedClaimTile extends StatelessWidget {
  const RejectedClaimTile({
    super.key,
    required this.claim,
    required this.onUndo,
  });

  final RankingClaim claim;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tagStyle = theme.textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${claim.claimantName} → ${claim.playerName}',
                    style: theme.textTheme.bodyLarge,
                  ),
                  Text(
                    '${divisionLabel(claim.divisionCode)} · ${claim.rank}위',
                    style: tagStyle?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
              onPressed: onUndo,
              child: const Text('취소(재검토)'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 상위 위젯: pending 조회 + 승인/반려 처리 ──────────────────────────────────

class _ClaimsData {
  const _ClaimsData({required this.groups, required this.rejected});
  final List<ClaimGroup> groups;
  final List<RankingClaim> rejected;
}

/// 관리자 대시보드 "랭킹 클레임" 탭. pending 을 협회 선수 단위로 묶어 경합을
/// 한눈에 보여준다. 자체 로드(KnowledgeBaseTab/GeminiUsageTab 과 같은 패턴).
class RankingClaimsTab extends ConsumerStatefulWidget {
  const RankingClaimsTab({super.key});

  @override
  ConsumerState<RankingClaimsTab> createState() => _RankingClaimsTabState();
}

class _RankingClaimsTabState extends ConsumerState<RankingClaimsTab> {
  late Future<_ClaimsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ClaimsData> _load() async {
    if (AppConfig.adminDesignPreview) {
      return const _ClaimsData(groups: [], rejected: []);
    }
    final api = ref.read(apiProvider);
    final pending = await api.pendingRankingClaims();
    final rejected = await api.rejectedRankingClaims();
    return _ClaimsData(groups: groupClaimsByPlayer(pending), rejected: rejected);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _approve(RankingClaim claim) async {
    try {
      await ref.read(apiProvider).approveRankingClaim(claim);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      final message = e is PostgrestException && e.code == '23505'
          ? '이미 다른 사람에게 연결된 선수입니다'
          : '승인 실패: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _reject(RankingClaim claim) async {
    try {
      await ref.read(apiProvider).rejectRankingClaim(claim);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('반려 실패: $e')));
    }
  }

  /// 이의신청 처리 1단계 — 기존 확정 연결을 푼다. 되돌리기 어려운 조작이라
  /// (풀린 사람은 개인 기록장 접근을 잃는다) 누구를 푸는지 보여주고 확인받는다.
  ///
  /// 해제와 새 신청 승인은 원자적이지 않다. 중간에 멈추면 이 선수는 주인이
  /// 없는 상태로 남고, 이의신청은 큐에 그대로 있어 다시 승인하면 된다 —
  /// 관리자에게 보이는 상태라 조용히 깨지지 않는다.
  Future<void> _release(RankingClaim claim) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('기존 연결 해제'),
        content: Text(
          '${claim.playerName} 선수와 ${claim.confirmedHolderName ?? '알 수 없음'}님의 '
          '연결을 풉니다. 그분은 개인 기록장을 볼 수 없게 됩니다.\n\n'
          '자동 복구는 안 됩니다. 되돌리려면 아래 "반려됨" 목록에서 '
          '「취소(재검토)」로 기록을 지운 뒤, 그분이 다시 신청해야 합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('해제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(apiProvider).releaseConfirmedLink(claim);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('해제 실패: $e')));
    }
  }

  Future<void> _undo(RankingClaim claim) async {
    try {
      await ref.read(apiProvider).undoRejectedRankingClaim(claim);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('취소 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_ClaimsData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text('로드 실패: ${snap.error}')),
                ),
              ],
            );
          }
          final data = snap.data ?? const _ClaimsData(groups: [], rejected: []);
          if (data.groups.isEmpty && data.rejected.isEmpty) {
            return ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: Text('처리할 클레임이 없습니다')),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final g in data.groups) ...[
                ClaimGroupCard(
                  group: g,
                  onApprove: _approve,
                  onReject: _reject,
                  onRelease: _release,
                ),
                const SizedBox(height: 8),
              ],
              if (data.rejected.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('반려됨', style: Theme.of(context).textTheme.titleMedium),
                ),
                for (final c in data.rejected) ...[
                  RejectedClaimTile(claim: c, onUndo: () => _undo(c)),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}
