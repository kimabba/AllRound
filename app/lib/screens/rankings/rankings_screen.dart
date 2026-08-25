import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/org_ranking.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_card.dart';
import '../../widgets/tournament_section_bar.dart';
import 'player_history_sheet.dart';

// ── 순위표 ────────────────────────────────────────────────────────────────

/// 지금 보는 부서에서 "본인" 신청을 걸 수 있는 선수들.
///
/// [links] 는 `orgPlayerLinks()` 결과(내 것 전부 + 남의 confirmed).
/// [registeredHere] 는 이 협회·부서를 내가 등록했는지 — 아니면 아무 행도 못 건다
/// (자격 강제의 정본은 RLS `org_player_links_claim`, 여기는 표시 규칙).
///
/// 내 링크는 status 를 가리지 않고 전부 뺀다. rejected 도 마찬가지다 —
/// unique(org_code, org_player_id, user_id) 가 상태와 무관해서 재신청 INSERT 가
/// 반드시 실패하는데, 버튼만 다시 떠 있으면 사용자는 이유 모를 에러만 본다.
///
/// 이 협회에 내 확정 연결이 이미 있으면 아무 행도 신청할 수 없다. 협회당
/// 유저 1명 1선수(org_player_links_confirmed_user_key)라 승인 시점에 막히므로,
/// 신청을 받아두면 관리자가 승인할 수 없는 대기 건만 쌓인다.
///
/// [myName] 과 이름이 같은 행만 신청할 수 있다. 한 협회 안에서 동명이인이
/// 0건이라(2026-08-05 실측, 3,540명 전원 유일) 이름 하나로 사람이 특정된다.
Set<String> computeClaimableIds({
  required List<OrgRankingRow> rows,
  required List<Map<String, dynamic>> links,
  required String? myUserId,
  required String? myName,
  required bool registeredHere,
}) {
  if (!registeredHere) return const {};
  // 로그인 전에는 어떤 신청도 통과하지 못한다(정책이 user_id = auth.uid()).
  // 이게 없으면 내 링크를 하나도 못 알아봐 남의 것처럼 취급하고 버튼을 띄운다.
  if (myUserId == null) return const {};
  // 정책이 users.name 을 글자 그대로 비교하므로 여기서도 trim 하지 않는다 —
  // 앞뒤 여백을 앱만 관대하게 다루면 버튼은 보이는데 서버가 거부한다.
  final name = myName;
  if (name == null || name.isEmpty) return const {};
  final blocked = <String>{};
  for (final link in links) {
    final orgPlayerId = link['org_player_id'] as String;
    final isMine = link['user_id'] == myUserId;
    if (isMine && link['status'] == 'confirmed') return const {};
    if (isMine || link['status'] == 'confirmed') {
      blocked.add(orgPlayerId);
    }
  }
  return {
    for (final r in rows)
      if (r.orgPlayerId != null &&
          r.playerName == name &&
          !blocked.contains(r.orgPlayerId))
        r.orgPlayerId!,
  };
}

/// 지금 보는 부서에서 "이의신청"을 걸 수 있는 선수들.
///
/// [computeClaimableIds] 의 정확한 여집합이다 — 조건이 전부 같고 마지막 하나만
/// 뒤집힌다: 그 선수가 **남과 이미 확정 연결**돼 있을 것. 신청 버튼이 사라지는
/// 자리에 이의신청 버튼이 대신 붙는다.
///
/// 서버는 이 INSERT 를 이미 허용한다. `org_player_links_claim` 정책은 대상
/// 선수가 남과 확정됐는지 보지 않고(20260805010000 주석), confirmed 1:1 은
/// 승인 시점에 `org_player_links_confirmed_player_key` 가 강제한다. 즉 경합하는
/// pending 이 쌓이는 것이 설계된 동작이고, 관리자가 큐에서 고른다.
///
/// 내 링크가 이미 있는 선수는 뺀다 — unique(org_code, org_player_id, user_id)
/// 가 상태와 무관해서 재신청이 반드시 실패한다([computeClaimableIds] 와 같은 이유).
/// 이 협회에 내 확정 연결이 있으면 아무 행도 걸 수 없다(`has_confirmed_org_link`).
Set<String> computeDisputableIds({
  required List<OrgRankingRow> rows,
  required List<Map<String, dynamic>> links,
  required String? myUserId,
  required String? myName,
  required bool registeredHere,
}) {
  if (!registeredHere) return const {};
  // [computeClaimableIds] 와 같은 이유 — 로그인 전에는 서버가 전부 거부한다.
  if (myUserId == null) return const {};
  final name = myName;
  if (name == null || name.isEmpty) return const {};
  final othersConfirmed = <String>{};
  final mine = <String>{};
  for (final link in links) {
    final orgPlayerId = link['org_player_id'] as String;
    if (link['user_id'] == myUserId) {
      if (link['status'] == 'confirmed') return const {};
      mine.add(orgPlayerId);
    } else if (link['status'] == 'confirmed') {
      othersConfirmed.add(orgPlayerId);
    }
  }
  return {
    for (final r in rows)
      if (r.orgPlayerId != null &&
          r.playerName == name &&
          othersConfirmed.contains(r.orgPlayerId) &&
          !mine.contains(r.orgPlayerId))
        r.orgPlayerId!,
  };
}

/// 이름·소속 부분일치 필터. 표가 부서 하나에 수백 행(광주 남자일반부 871행)이라
/// 스크롤만으로는 자기 이름을 찾을 수 없다. 서버 재조회 없이 받아둔 행에서 거른다.
List<OrgRankingRow> filterRankingRows(List<OrgRankingRow> rows, String query) {
  final q = query.trim();
  if (q.isEmpty) return rows;
  return rows
      .where(
        (r) => r.playerName.contains(q) || (r.clubRaw?.contains(q) ?? false),
      )
      .toList();
}

/// 순위·성명·소속·포인트 한 줄. 데이터 주입형(네트워크 호출 없음) — 조회는
/// [RankingsScreen] 이 담당한다.
///
/// 저장은 rank_points/total_points 둘이지만(협회 규정상 다른 집계여야 함),
/// 현재 협회 화면이 전 행에서 같은 값을 내보내 화면엔 totalPoints 하나만 보여준다.
///
/// [onClaim] 이 있으면 신청 가능한 행에 "본인" 버튼이 붙는다. 어떤 행이 신청
/// 가능한지는 화면이 판단해 [claimableOrgPlayerIds] 로 준다(자격 강제의 정본은
/// RLS `org_player_links_claim` 이고, 이건 표시 규칙일 뿐이다).
///
/// [onDispute] / [disputableOrgPlayerIds] 는 같은 구조의 이의신청 경로다 —
/// 이미 남과 연결된 선수 줄에 붙는다. 두 집합은 서로 겹치지 않는다.
class RankingList extends StatelessWidget {
  const RankingList({
    super.key,
    required this.rows,
    required this.linkedOrgPlayerId,
    this.claimableOrgPlayerIds = const {},
    this.disputableOrgPlayerIds = const {},
    this.onClaim,
    this.onDispute,
    this.onPlayerTap,
  });

  final List<OrgRankingRow> rows;
  final String? linkedOrgPlayerId;
  final Set<String> claimableOrgPlayerIds;
  final Set<String> disputableOrgPlayerIds;
  final void Function(OrgRankingRow row)? onClaim;
  final void Function(OrgRankingRow row)? onDispute;
  final void Function(OrgRankingRow row)? onPlayerTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _RankingRow(
            row: rows[i],
            isMine: rows[i].orgPlayerId != null &&
                rows[i].orgPlayerId == linkedOrgPlayerId,
            onTap: rows[i].orgPlayerId == null || onPlayerTap == null
                ? null
                : () => onPlayerTap!(rows[i]),
            onClaim: onClaim != null &&
                    rows[i].orgPlayerId != null &&
                    claimableOrgPlayerIds.contains(rows[i].orgPlayerId)
                ? () => onClaim!(rows[i])
                : null,
            onDispute: onDispute != null &&
                    rows[i].orgPlayerId != null &&
                    disputableOrgPlayerIds.contains(rows[i].orgPlayerId)
                ? () => onDispute!(rows[i])
                : null,
          ),
        ],
      ],
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.row,
    required this.isMine,
    this.onClaim,
    this.onDispute,
    this.onTap,
  });

  final OrgRankingRow row;
  final bool isMine;
  final VoidCallback? onClaim;
  final VoidCallback? onDispute;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // 랭킹표는 협회 크롤 데이터라 프로필 사진이 없다 — 클럽 멤버 리스트와 같은
    // 이니셜 폴백을 쓴다(app/lib/screens/clubs/club_detail_screen.dart 의
    // CircleAvatar 패턴과 동일).
    final trimmedName = row.playerName.trim();
    final initial =
        trimmedName.characters.isEmpty ? '?' : trimmedName.characters.first;
    return AppCard(
      key: isMine ? const ValueKey('ranking-row-mine') : null,
      variant: AppCardVariant.outlined,
      backgroundColor: isMine ? cs.primaryContainer : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
              width: 32, child: Text('${row.rank}', style: tt.bodyLarge)),
          const SizedBox(width: AppSpacing.sm),
          CircleAvatar(
            // 내 행은 카드 배경 자체가 primaryContainer 라, 아바타도 같은 색이면
            // 원이 배경에 묻혀 안 보인다 — 내 행일 때는 surface 로 대비를 준다.
            backgroundColor: isMine ? cs.surface : cs.primaryContainer,
            child: Text(
              initial,
              style: TextStyle(
                color: isMine ? cs.primary : cs.onPrimaryContainer,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.playerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      tt.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (row.clubRaw != null && row.clubRaw!.isNotEmpty)
                  Text(
                    row.clubRaw!,
                    style:
                        tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Text('${row.totalPoints}', style: tt.bodyLarge),
          if (onClaim != null) ...[
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton(
              // 테마 기본 minimumSize 가 Size.fromHeight(폭 무한)라 Row 안에서는
              // 명시로 덮어써야 한다(theme-infinite-width-button-landmine).
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, AppSizes.control),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                ),
              ),
              onPressed: onClaim,
              child: const Text('본인'),
            ),
          ],
          // 신청 버튼이 사라지는 자리(이미 남과 연결된 줄)에 대신 붙는다.
          // 둘이 같이 뜨는 경우는 없다 — 두 집합이 배타적이다.
          if (onDispute != null) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AppSizes.control),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                ),
              ),
              onPressed: onDispute,
              child: const Text('이의신청'),
            ),
          ],
        ],
      ),
    );
  }
}

class _RankingTableHeader extends StatelessWidget {
  const _RankingTableHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          SizedBox(width: 32, child: Text('순위', style: style)),
          const SizedBox(width: AppSpacing.sm),
          // 행의 아바타(지름 40) + 이름 앞 간격(md)과 정렬을 맞춘다.
          const SizedBox(width: 40 + AppSpacing.md),
          Expanded(child: Text('선수 · 소속', style: style)),
          Text('누적 포인트', style: style),
        ],
      ),
    );
  }
}

// ── 이의신청 사유 입력 ────────────────────────────────────────────────────

/// 이의신청 사유를 받는다. 취소하면 null.
///
/// 사유를 필수로 받는 이유: 정책이 `users.name = player_name` 을 요구해 경합하는
/// 두 사람의 이름은 **반드시 같다**. 관리자가 가릴 재료가 이것뿐이다.
Future<String?> askDisputeNote(BuildContext context, String playerName) =>
    showDialog<String>(
      context: context,
      builder: (_) => _DisputeNoteDialog(playerName: playerName),
    );

/// 컨트롤러를 StatefulWidget 이 소유한다. `showDialog(...).whenComplete(dispose)`
/// 는 pop 시점에 돌아 퇴장 애니메이션·IME 콜백이 아직 살아 있는 동안 컨트롤러를
/// 버린다 — State.dispose 가 올바른 수명이다.
class _DisputeNoteDialog extends StatefulWidget {
  const _DisputeNoteDialog({required this.playerName});

  final String playerName;

  @override
  State<_DisputeNoteDialog> createState() => _DisputeNoteDialogState();
}

class _DisputeNoteDialogState extends State<_DisputeNoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.playerName} — 이의신청'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '이 선수는 이미 다른 계정과 연결돼 있습니다. '
            '본인이 맞다면 관리자가 확인할 수 있게 소속 클럽과 연락처를 적어주세요.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            // DB CHECK(org_player_links_note_len)와 같은 상한.
            maxLength: 300,
            decoration: const InputDecoration(
              hintText: '예) 어등산클럽 소속입니다. 010-1234-5678',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          // 사유 없는 이의신청은 관리자가 판단할 수 없다.
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('신청'),
        ),
      ],
    );
  }
}

// ── 등록 안 한 부서 안내 ──────────────────────────────────────────────────

/// 지금 보는 협회·부서를 등록하지 않았을 때의 안내.
///
/// 등록이 아예 없으면 등록을 권하고 버튼을 준다. 등록은 했는데 다른 부서를
/// 보고 있으면 **버튼을 주지 않는다** — "등록하러 가라"가 여기서는 틀린 조언이다.
/// 그 협회 랭커가 아닌 사람이 자기 부서가 아닌 것을 등록하게 만든다.
class _NotMyDivisionNotice extends StatelessWidget {
  const _NotMyDivisionNotice({required this.hasNoOrgRegistered});

  final bool hasNoOrgRegistered;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasNoOrgRegistered
                ? '소속 협회·부서를 등록하면 랭킹표에서 「본인」을 찾을 수 있어요.'
                : '내가 등록한 부서가 아니라 여기선 본인 연결을 신청할 수 없어요.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (hasNoOrgRegistered)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                // 테마 기본 minimumSize 가 폭 무한이다
                // (theme-infinite-width-button-landmine).
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.control),
                ),
                // 협회·부서 편집 화면은 온보딩이다 — profile_quick_actions 등
                // 기존 4곳이 쓰는 것과 같은 경로.
                onPressed: () => context.push('/onboarding'),
                child: const Text('등록하러 가기'),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 출처 표기 ─────────────────────────────────────────────────────────────

/// 개인정보 보호책임자 연락처(privacy-policy.html 7항과 동일해야 한다).
/// 이 화면은 앱 미가입자의 실명도 표시하므로, 본인이 발견하고 삭제·정정을
/// 요청할 수 있는 유일한 창구가 여기다.
const _kPrivacyContactEmail = 'play@jyoungad.kr';

final _kFetchedAtFormat = DateFormat('yyyy-MM-dd');

/// 앱이 계산한 값이 아니라는 것과, 삭제·정정 요청 창구를 화면이 스스로
/// 말한다. 조건 없이 상시 노출(가입 여부 무관 — 랭킹 명단의 미가입자도 봐야 한다).
///
/// [fetchedAt] 은 이 표가 마지막으로 협회 원본에서 수집된 시각(org_rankings.fetched_at).
/// 연초 협회 포인트 리셋 등으로 크롤이 빈 배열 가드에 걸려 저장을 건너뛰면 미러가
/// 옛 상태로 남는데, 이 값이 없으면 화면이 그걸 "현재"인 것처럼 보여준다 — null 이면
/// (아직 로드 전이거나 행이 없으면) 이 줄만 생략한다.
class RankingSourceNotice extends StatelessWidget {
  const RankingSourceNotice(
      {super.key, required this.orgLabel, this.fetchedAt});

  final String orgLabel;
  final DateTime? fetchedAt;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$orgLabel 공표 데이터 · 참고용이며 협회 공표가 우선합니다',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (fetchedAt != null)
            Text(
              '${_kFetchedAtFormat.format(fetchedAt!.toLocal())} 기준',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          const SizedBox(height: 2),
          InkWell(
            onTap: () => launchUrl(
              Uri.parse('mailto:$_kPrivacyContactEmail'),
            ),
            child: Text(
              '정보 삭제·정정 요청: $_kPrivacyContactEmail',
              style: tt.bodySmall?.copyWith(
                color: cs.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          // 이 앱은 협회 공표 자료를 미러링한다. 우리 쪽에서 지워도 협회가 계속
          // 공표하면 원본이 남는다 — 요청자가 그걸 모르면 헛수고를 한다.
          // (우리 쪽 삭제는 억제 목록으로 유지되므로 다시 살아나지는 않는다.)
          Text(
            '협회 공표 자료를 옮긴 것이라, 원본까지 지우려면 협회에도 함께 요청해야 합니다',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── 내 기록 요약 카드 ─────────────────────────────────────────────────────

/// 드롭다운 바로 아래 "내 기록 요약". 어느 협회에서든 항상 뜬다 — "이 화면도
/// 너무하지 않아?" 피드백(미연결 협회에선 안내문만 뜨던 것)에 대한 대응이다.
///
/// [linked] 가 지금 보는 협회에 confirmed 연결이 있는지를 가른다.
/// - true: 기존과 동일 — 부서·순위·포인트를 보여주고 탭하면 /rankings/me.
///   [ranking] 이 null 이어도 카드는 뜬다 — "내 기록 보기" 링크를 없앤 자리라
///   이 카드가 /rankings/me 로 가는 유일한 진입점이다. 연결은 있는데 공표
///   표에 행이 없는 경우(연초 협회 포인트 리셋 등)에 사라지면 기록 화면이
///   고아가 된다.
/// - false: 라벨은 같지만 본문은 고정 안내문. [onTap] 없이 렌더돼(AppCard 는
///   onTap null 이면 InkWell 자체를 안 만든다) 탭이 안 되고, 화살표도 뺀다 —
///   탭 안 되는데 화살표가 있으면 거짓 어포던스다.
class MyRankingSummaryCard extends StatelessWidget {
  const MyRankingSummaryCard({
    super.key,
    required this.orgCode,
    required this.ranking,
    required this.linked,
    this.onTap,
  });

  final String orgCode;
  final OrgRankingRow? ranking;
  final bool linked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final r = ranking;
    // 내 랭킹 행과 같은 강조색(primaryContainer) — "내 것"의 색을 화면 안에서
    // 하나로 유지한다.
    return AppCard(
      key: const ValueKey('my-ranking-summary-card'),
      variant: AppCardVariant.outlined,
      backgroundColor: cs.primaryContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tennisOrgShortLabel(orgCode)} 내 기록',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  !linked
                      ? '전적이 없거나 확인되지 않았습니다'
                      : r == null
                          ? '공표된 순위 없음'
                          : '${divisionLabel(r.divisionCode)} ${r.rank}위 · '
                              '${NumberFormat('#,###').format(r.totalPoints)}P',
                  style: tt.titleMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          if (linked) Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
        ],
      ),
    );
  }
}

// ── 본인 확인 카드 ────────────────────────────────────────────────────────

/// my_ranking_candidates() 후보 1건에 대한 본인 확인 유도 카드.
class RankingClaimPrompt extends StatelessWidget {
  const RankingClaimPrompt({
    super.key,
    required this.candidate,
    required this.onClaim,
  });

  final OrgRankingRow candidate;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final club = candidate.clubRaw?.replaceAll('/', '').trim();
    final clubSuffix = (club != null && club.isNotEmpty) ? '($club)' : '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${divisionLabel(candidate.divisionCode)} ${candidate.rank}위 '
                '${candidate.playerName}$clubSuffix — 본인인가요?',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              // 테마 기본 minimumSize 가 Size.fromHeight(폭 무한)라, Row 안에서는
              // 명시로 덮어써야 한다(theme-infinite-width-button-landmine).
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: onClaim,
              child: const Text('신청'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 화면 본체: 협회·부서 선택 + 조회 ──────────────────────────────────────

class _RankingScreenData {
  const _RankingScreenData({
    required this.rows,
    required this.linkedOrgPlayerId,
    required this.candidate,
    required this.hasPendingClaim,
    required this.claimableOrgPlayerIds,
    required this.disputableOrgPlayerIds,
    required this.registeredHere,
    required this.hasNoOrgRegistered,
    required this.myRanking,
  });

  final List<OrgRankingRow> rows;
  final String? linkedOrgPlayerId;
  final OrgRankingRow? candidate;
  final bool hasPendingClaim;

  /// 지금 보고 있는 부서에서 "본인" 신청을 걸 수 있는 선수들.
  /// 비어 있으면 어느 행에도 버튼이 안 붙는다.
  final Set<String> claimableOrgPlayerIds;

  /// 이미 남과 연결돼 있어 "이의신청"만 걸 수 있는 선수들.
  final Set<String> disputableOrgPlayerIds;

  /// 이 협회·부서를 내 프로필에 등록해 뒀는지. 등록했는데도 신청할 행이
  /// 하나도 없으면 이유(이름 불일치)를 화면이 말해 줘야 한다.
  final bool registeredHere;

  /// 협회를 하나도 등록하지 않았는지. [registeredHere] 가 false 인 이유가
  /// "아직 아무것도 등록 안 함"인지 "등록했지만 다른 부서"인지 가른다 —
  /// 안내 문구와 버튼이 달라진다. 등록 0개일 때만 등록을 권한다. 남의 부서를
  /// 보고 있는 사람에게 "등록하러 가라"고 하면 자기 부서가 아닌 것을 등록하게
  /// 만든다(실측: gj_m_instructor 를 등록했지만 그 21명 명단에 없는 사례).
  final bool hasNoOrgRegistered;

  /// 지금 보는 **협회**에서의 내 대표 부서 순위(confirmed 연결 기준).
  /// 보는 부서와 내 부서가 달라도 채워진다 — 부서 조회(rows)와 별도로
  /// playerRankings 로 얻는다. 연결이 없거나, 연결은 있는데 공표 표에
  /// 행이 없으면(연초 리셋 등) null.
  final OrgRankingRow? myRanking;
}

/// 협회 랭킹 화면. 협회(광주/전남)와 부서를 고르면 그 부서의 공표 순위표를 보여준다.
/// 협회별로 랭킹이 분리 운영이라 통합 뷰는 없다.
class RankingsScreen extends ConsumerStatefulWidget {
  const RankingsScreen({super.key});

  @override
  ConsumerState<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends ConsumerState<RankingsScreen> {
  String _orgCode = 'gj';
  String _divisionCode = kRankingDivisions['gj']!.first;
  String _query = '';
  bool _claiming = false;
  late Future<_RankingScreenData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RankingScreenData> _load() async {
    final api = ref.read(apiProvider);
    final rows = await api.orgRankings(
      orgCode: _orgCode,
      divisionCode: _divisionCode,
    );
    final links = await api.orgPlayerLinks(_orgCode);
    final candidates = await api.myRankingCandidates();
    final myOrgs = await api.myTennisOrgs();
    final myProfile = await api.myProfile();
    final myUserId = ref.read(currentUserProvider)?.id;

    String? linkedOrgPlayerId;
    final pendingIds = <String>{};
    for (final link in links) {
      final status = link['status'] as String;
      final orgPlayerId = link['org_player_id'] as String;
      final isMine = link['user_id'] == myUserId;
      if (isMine && status == 'confirmed') linkedOrgPlayerId = orgPlayerId;
      if (isMine && status == 'pending') pendingIds.add(orgPlayerId);
    }

    // 내 기록 요약용 — 지금 보는 부서의 rows 에는 내 행이 없을 수 있어
    // (내 부서 ≠ 보는 부서) 협회+선수로 따로 조회한다. 대표 부서는 홈 등급
    // 카드와 같은 기준(topDivisionRanking, 협회 공표 순서 = 상위 부서 우선).
    // 요약 카드는 부가 기능이다 — 이 조회가 실패해도 순위표는 떠야 하므로
    // 삼킨다. 카드는 '공표된 순위 없음'으로 강등된다.
    var myRows = const <OrgRankingRow>[];
    if (linkedOrgPlayerId != null) {
      try {
        myRows = await api.playerRankings(
          orgCode: _orgCode,
          orgPlayerId: linkedOrgPlayerId,
        );
      } catch (_) {
        myRows = const <OrgRankingRow>[];
      }
    }

    // 신청 자격: 지금 보는 협회·부서를 내가 등록했고, 이름이 같은 행인가.
    // 정본은 RLS(org_player_links_claim) 이고 여기서는 같은 조건을 화면에 반영만 한다.
    final registeredHere = myOrgs.any(
      (o) => o.org == _orgCode && o.divisionCodes.contains(_divisionCode),
    );
    final claimable = computeClaimableIds(
      rows: rows,
      links: links,
      myUserId: myUserId,
      myName: myProfile?.name,
      registeredHere: registeredHere,
    );
    final disputable = computeDisputableIds(
      rows: rows,
      links: links,
      myUserId: myUserId,
      myName: myProfile?.name,
      registeredHere: registeredHere,
    );

    // 후보 카드는 행별 버튼과 별개 경로다. 이 협회에 이미 확정 연결이 있으면
    // my_ranking_candidates() 가 (같은 이름의 다른 선수를) 후보로 낼 수 있는데,
    // 그 신청은 정책이 거부한다 — 카드 자체를 띄우지 않는다.
    OrgRankingRow? candidate;
    if (linkedOrgPlayerId == null) {
      for (final c in candidates) {
        if (c.orgCode == _orgCode &&
            c.orgPlayerId != null &&
            !pendingIds.contains(c.orgPlayerId)) {
          candidate = c;
          break;
        }
      }
    }

    return _RankingScreenData(
      rows: rows,
      linkedOrgPlayerId: linkedOrgPlayerId,
      candidate: candidate,
      hasPendingClaim: pendingIds.isNotEmpty,
      claimableOrgPlayerIds: claimable,
      disputableOrgPlayerIds: disputable,
      registeredHere: registeredHere,
      hasNoOrgRegistered: myOrgs.isEmpty,
      myRanking: topDivisionRanking(myRows),
    );
  }

  /// 표의 대표 기준일 — 행마다 미세하게 다를 수 있어(부서 교체 RPC 가 순차 실행)
  /// 최신값(가장 늦은 fetched_at)을 쓴다.
  DateTime? _latestFetchedAt(List<OrgRankingRow>? rows) {
    if (rows == null || rows.isEmpty) return null;
    return rows.map((r) => r.fetchedAt).whereType<DateTime>().fold<DateTime?>(
          null,
          (latest, d) => latest == null || d.isAfter(latest) ? d : latest,
        );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  void _changeOrg(String orgCode) {
    setState(() {
      _orgCode = orgCode;
      _divisionCode = kRankingDivisions[orgCode]!.first;
      _future = _load();
    });
  }

  void _changeDivision(String divisionCode) {
    setState(() {
      _divisionCode = divisionCode;
      _future = _load();
    });
  }

  Future<void> _claim(
    OrgRankingRow candidate, {
    String? note,
    String successMessage = '신청했습니다. 관리자 확인 후 연결됩니다',
  }) async {
    // 연타 방어. 같은 선수로 INSERT 가 둘 나가면 하나는
    // unique(org_code, org_player_id, user_id) 로 23505 를 받는다.
    if (_claiming) return;
    _claiming = true;
    try {
      await ref.read(apiProvider).claimRanking(candidate, note: note);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('신청 실패: $e')));
    } finally {
      _claiming = false;
    }
  }

  /// 이의신청 — 이미 남과 연결된 선수를 두고 "그건 나다"라고 알린다.
  /// INSERT 는 일반 신청과 완전히 같고(pending), 사유만 함께 넣는다.
  Future<void> _dispute(OrgRankingRow row) async {
    if (_claiming) return;
    final note = await askDisputeNote(context, row.playerName);
    if (note == null || !mounted) return;
    await _claim(
      row,
      note: note,
      successMessage: '이의신청했습니다. 관리자가 확인 후 연락드립니다',
    );
  }

  /// 랭킹표 행을 탭했을 때 — 연결 승인 여부와 무관하게 그 선수의 전적을 보여준다.
  /// 협회 원본 조회·캐시는 Edge Function(ranking-player-history)이 맡는다.
  Future<void> _openPlayerHistory(OrgRankingRow player) {
    return showPlayerHistorySheet(
      context,
      player: player,
      load: () => ref.read(apiProvider).playerHistory(player),
      loadSnapshots: player.orgPlayerId == null
          ? null
          : () => ref.read(apiProvider).playerRankingHistory(
                orgCode: player.orgCode,
                divisionCode: player.divisionCode,
                orgPlayerId: player.orgPlayerId!,
              ),
    );
  }

  /// 드롭다운 아래 고정 슬롯. 내 기록 요약 카드는 어느 협회에서든 항상 뜬다
  /// ("이 화면도 너무하지 않아?" 피드백 — 미연결 협회라고 카드를 숨기지
  /// 않는다). confirmed 연결이 없으면 카드 아래에 기존 연결 유도/후보 카드
  /// 체인이 그대로 이어진다.
  ///
  /// 연결이 있으면 pending 이 남아 있어도 카드가 이긴다 — 연결이 끝난 사람에게
  /// '확인 중입니다'는 틀린 정보다(협회당 1명 1선수라 남은 pending 은 승인될 수
  /// 없는 잔재다).
  Widget _buildStatusSlot(_RankingScreenData data) {
    final linked = data.linkedOrgPlayerId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MyRankingSummaryCard(
          orgCode: _orgCode,
          ranking: data.myRanking,
          linked: linked,
          onTap: linked ? () => context.push('/rankings/me?org=$_orgCode') : null,
        ),
        if (!linked) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildLinkGuidance(data),
        ],
      ],
    );
  }

  /// 미연결 협회에서 카드 아래에 붙는 기존 연결 유도/후보 카드 체인.
  /// [_buildStatusSlot] 이 confirmed 연결이 있으면 아예 부르지 않는다.
  Widget _buildLinkGuidance(_RankingScreenData data) {
    // 협회를 하나도 등록하지 않았으면 이게 최우선이다.
    // 등록을 지워도 pending 신청은 남으므로(org_player_links 는
    // user_tennis_orgs 와 별개 테이블), 이 분기가 뒤에 있으면
    // '확인 중입니다'가 등록 안내를 영구히 가린다
    // (codex 리뷰 2026-08-18). 등록이 0개면 후보도 0개다 —
    // my_ranking_candidates() 가 user_tennis_orgs 를 조인한다.
    if (data.hasNoOrgRegistered) {
      return const _NotMyDivisionNotice(hasNoOrgRegistered: true);
    }
    if (data.candidate != null) {
      return RankingClaimPrompt(
        candidate: data.candidate!,
        onClaim: () => _claim(data.candidate!),
      );
    }
    if (data.hasPendingClaim) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text('확인 중입니다', style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    // 등록한 부서인데 신청할 행이 하나도 없는 경우. 이유를 안 알려
    // 주면 "버튼이 왜 없지"로 끝난다. 원인은 여러 가지(이름 불일치가
    // 가장 흔하고, 이미 신청·연결된 선수도 제외된다)라 단정하지 않는다.
    if (data.registeredHere &&
        data.claimableOrgPlayerIds.isEmpty &&
        data.disputableOrgPlayerIds.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          '이 표에서 신청할 수 있는 줄이 없습니다. '
          '가입할 때 넣은 이름이 협회 명단과 같아야 하고, '
          '이미 신청했거나 연결된 선수는 제외됩니다.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    // 등록하지 않은 협회·부서를 보는 중. 지금까지는 버튼만 조용히
    // 사라져 이유를 알 길이 없었다 — 본인 연결 진입이 0건인
    // 이유 중 하나다(2026-08-18 실측: 27명 중 20명이 협회 미등록).
    //
    // 여기까지 왔으면 "등록은 했는데 다른 부서를 보는 중"이다
    // (등록 0개는 위에서 이미 걸렀다). 맨 뒤인 것은 의도다 —
    // 후보 카드와 '확인 중입니다'는 부서가 아니라 **협회 단위**로
    // 뜬다. 화면 기본 부서가 gj_m_gold 라 부서로 좁히면
    // 남자일반부 후보를 가진 사람은 탭을 옮기기 전엔 카드를
    // 영영 못 본다. 진행 중인 신청이 있으면 그 소식이 먼저다.
    if (!data.registeredHere) {
      return const _NotMyDivisionNotice(hasNoOrgRegistered: false);
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final orgCodes = kRankingDivisions.keys.toList();
    final divisions = kRankingDivisions[_orgCode]!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('협회 랭킹'),
        bottom: TournamentSectionBar(
          selected: TournamentSection.rankings,
          showRankings: ref.watch(activeSportProvider) == 'tennis',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              0,
            ),
            // 협회·부서를 한 줄 두 칸으로. 협회는 계속 추가될 예정이라
            // (kRankingDivisions 에 미러 협회를 넣으면 자동 반영) 세그먼트로는
            // 폭이 감당이 안 된다 — 부서와 같은 드롭다운 스타일로 맞춘다.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _orgCode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '협회'),
                    items: [
                      for (final org in orgCodes)
                        DropdownMenuItem(
                          value: org,
                          child: Text(
                            tennisOrgShortLabel(org),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) _changeOrg(v);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    // 협회가 바뀌면 부서 items 가 통째로 바뀐다. initialValue 는
                    // 최초 빌드에만 적용돼(tournament_submit_screen 의 회귀 주석
                    // 참조) 옛 부서 값이 남으면 assert 가 터진다 — 키로 필드를
                    // 재생성해 새 협회의 첫 부서로 리셋한다.
                    key: ValueKey('division-$_orgCode'),
                    initialValue: _divisionCode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '부서'),
                    items: [
                      for (final code in divisions)
                        DropdownMenuItem(
                          value: code,
                          child: Text(
                            divisionLabel(code),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) _changeDivision(v);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              0,
            ),
            child: FutureBuilder<_RankingScreenData>(
              future: _future,
              builder: (context, snap) {
                final data = snap.data;
                // 로드 전·실패 시 빈 슬롯 — 로딩 표시는 목록 영역이 담당한다.
                if (data == null) return const SizedBox.shrink();
                return _buildStatusSlot(data);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              0,
            ),
            child: TextField(
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: '이름·소속 검색',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: FutureBuilder<_RankingScreenData>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('로드 실패: ${snap.error}'));
                }
                final data = snap.data!;
                final visibleRows = filterRankingRows(data.rows, _query);
                return ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.md,
                  ),
                  children: [
                    if (visibleRows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: Center(
                          child: Text(
                            data.rows.isEmpty ? '공표된 랭킹이 없습니다' : '검색 결과가 없습니다',
                          ),
                        ),
                      )
                    else
                      Column(
                        children: [
                          const _RankingTableHeader(),
                          RankingList(
                            rows: visibleRows,
                            linkedOrgPlayerId: data.linkedOrgPlayerId,
                            claimableOrgPlayerIds: data.claimableOrgPlayerIds,
                            disputableOrgPlayerIds: data.disputableOrgPlayerIds,
                            onClaim: _claim,
                            onDispute: _dispute,
                            onPlayerTap: _openPlayerHistory,
                          ),
                        ],
                      ),
                    // 목록 아래 최하단 — 검색창 아래에 있던 것을 여기로 옮겼다
                    // (위치만 변경, 문구·조건은 그대로: 법적 고지라 내용 무수정).
                    const SizedBox(height: AppSpacing.md),
                    RankingSourceNotice(
                      orgLabel: tennisOrgLabel(_orgCode),
                      fetchedAt: _latestFetchedAt(data.rows),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
