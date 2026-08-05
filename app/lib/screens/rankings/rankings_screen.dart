import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/org_ranking.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';

/// 협회 랭킹표가 실제로 공표하는 부서(광주·전남 동일, gnuboard_ranking 파서와
/// 일치). 부서 카탈로그 전체(rankingGradesForOrg)와 다르다 — 오픈부·베테랑부 등은
/// 대회 자격에는 쓰이지만 협회가 별도 랭킹표로 공표하지 않는다.
/// 남자신인부는 2026-08 남자일반부로 통합돼 빠졌다(카탈로그에는 is_active=false 로 남아
/// 옛 대회 라벨 해석은 계속 된다). 여자신인부는 살아 있다.
const _kRankingDivisions = <String, List<String>>{
  'gj': [
    'gj_m_gold',
    'gj_m_general',
    'gj_m_instructor',
    'gj_w_rookie',
    'gj_w_gukhwa',
    'gj_w_geumbae',
  ],
  'jn': [
    'jn_m_gold',
    'jn_m_general',
    'jn_m_instructor',
    'jn_w_rookie',
    'jn_w_gukhwa',
    'jn_w_geumbae',
  ],
};

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
  final name = myName?.trim();
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

/// 이름·소속 부분일치 필터. 표가 부서 하나에 수백 행(광주 남자일반부 871행)이라
/// 스크롤만으로는 자기 이름을 찾을 수 없다. 서버 재조회 없이 받아둔 행에서 거른다.
List<OrgRankingRow> filterRankingRows(List<OrgRankingRow> rows, String query) {
  final q = query.trim();
  if (q.isEmpty) return rows;
  return rows
      .where(
        (r) =>
            r.playerName.contains(q) || (r.clubRaw?.contains(q) ?? false),
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
class RankingList extends StatelessWidget {
  const RankingList({
    super.key,
    required this.rows,
    required this.linkedOrgPlayerId,
    this.claimableOrgPlayerIds = const {},
    this.onClaim,
  });

  final List<OrgRankingRow> rows;
  final String? linkedOrgPlayerId;
  final Set<String> claimableOrgPlayerIds;
  final void Function(OrgRankingRow row)? onClaim;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _RankingRow(
            row: rows[i],
            isMine: rows[i].orgPlayerId != null &&
                rows[i].orgPlayerId == linkedOrgPlayerId,
            onClaim: onClaim != null &&
                    rows[i].orgPlayerId != null &&
                    claimableOrgPlayerIds.contains(rows[i].orgPlayerId)
                ? () => onClaim!(rows[i])
                : null,
          ),
          if (i < rows.length - 1)
            Divider(height: 1, color: cs.outlineVariant),
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
  });

  final OrgRankingRow row;
  final bool isMine;
  final VoidCallback? onClaim;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      key: isMine ? const ValueKey('ranking-row-mine') : null,
      color: isMine ? cs.primaryContainer : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(width: 32, child: Text('${row.rank}', style: tt.bodyLarge)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.playerName,
                  style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (row.clubRaw != null && row.clubRaw!.isNotEmpty)
                  Text(
                    row.clubRaw!,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
                // 높이는 최소 터치 영역 48px 을 지킨다(pureform-sports-system.md).
                // 폭만 내용에 맞게 줄인다.
                minimumSize: const Size(0, AppSizes.control),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                ),
              ),
              onPressed: onClaim,
              child: const Text('본인'),
            ),
          ],
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
  const RankingSourceNotice({super.key, required this.orgLabel, this.fetchedAt});

  final String orgLabel;
  final DateTime? fetchedAt;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
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
    required this.registeredHere,
  });

  final List<OrgRankingRow> rows;
  final String? linkedOrgPlayerId;
  final OrgRankingRow? candidate;
  final bool hasPendingClaim;

  /// 지금 보고 있는 부서에서 "본인" 신청을 걸 수 있는 선수들.
  /// 비어 있으면 어느 행에도 버튼이 안 붙는다.
  final Set<String> claimableOrgPlayerIds;

  /// 이 협회·부서를 내 프로필에 등록해 뒀는지. 등록했는데도 신청할 행이
  /// 하나도 없으면 이유(이름 불일치)를 화면이 말해 줘야 한다.
  final bool registeredHere;
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
  String _divisionCode = _kRankingDivisions['gj']!.first;
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
      registeredHere: registeredHere,
    );
  }

  /// 표의 대표 기준일 — 행마다 미세하게 다를 수 있어(부서 교체 RPC 가 순차 실행)
  /// 최신값(가장 늦은 fetched_at)을 쓴다.
  DateTime? _latestFetchedAt(List<OrgRankingRow>? rows) {
    if (rows == null || rows.isEmpty) return null;
    return rows
        .map((r) => r.fetchedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
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
      _divisionCode = _kRankingDivisions[orgCode]!.first;
      _future = _load();
    });
  }

  void _changeDivision(String divisionCode) {
    setState(() {
      _divisionCode = divisionCode;
      _future = _load();
    });
  }

  Future<void> _claim(OrgRankingRow candidate) async {
    // 연타 방어. 같은 선수로 INSERT 가 둘 나가면 하나는
    // unique(org_code, org_player_id, user_id) 로 23505 를 받는다.
    if (_claiming) return;
    _claiming = true;
    try {
      await ref.read(apiProvider).claimRanking(candidate);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('신청했습니다. 관리자 확인 후 연결됩니다')),
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

  @override
  Widget build(BuildContext context) {
    final orgCodes = _kRankingDivisions.keys.toList();
    final divisions = _kRankingDivisions[_orgCode]!;

    return Scaffold(
      appBar: AppBar(title: const Text('협회 랭킹')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SegmentedButton<String>(
              segments: [
                for (final org in orgCodes)
                  ButtonSegment(value: org, label: Text(tennisOrgShortLabel(org))),
              ],
              selected: {_orgCode},
              onSelectionChanged: (s) => _changeOrg(s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: DropdownButtonFormField<String>(
              initialValue: _divisionCode,
              decoration: const InputDecoration(labelText: '부서'),
              items: [
                for (final code in divisions)
                  DropdownMenuItem(value: code, child: Text(divisionLabel(code))),
              ],
              onChanged: (v) {
                if (v != null) _changeDivision(v);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              0,
            ),
            child: TextField(
              decoration: const InputDecoration(
                labelText: '이름·소속 검색',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FutureBuilder<_RankingScreenData>(
            future: _future,
            builder: (context, snap) => RankingSourceNotice(
              orgLabel: tennisOrgLabel(_orgCode),
              fetchedAt: _latestFetchedAt(snap.data?.rows),
            ),
          ),
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
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    if (data.candidate != null)
                      RankingClaimPrompt(
                        candidate: data.candidate!,
                        onClaim: () => _claim(data.candidate!),
                      )
                    else if (data.hasPendingClaim)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: Text(
                          '확인 중입니다',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    // 등록한 부서인데 신청할 행이 하나도 없는 경우. 이유를 안 알려
                    // 주면 "버튼이 왜 없지"로 끝난다 — 대개 가입할 때 넣은 이름이
                    // 협회 명단 표기와 달라서다.
                    else if (data.registeredHere &&
                        data.claimableOrgPlayerIds.isEmpty &&
                        data.linkedOrgPlayerId == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: Text(
                          '내 이름과 같은 선수가 이 표에 없습니다. '
                          '가입할 때 넣은 이름이 협회 명단과 같아야 신청할 수 있습니다.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    if (visibleRows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: Center(
                          child: Text(
                            data.rows.isEmpty
                                ? '공표된 랭킹이 없습니다'
                                : '검색 결과가 없습니다',
                          ),
                        ),
                      )
                    else
                      RankingList(
                        rows: visibleRows,
                        linkedOrgPlayerId: data.linkedOrgPlayerId,
                        claimableOrgPlayerIds: data.claimableOrgPlayerIds,
                        onClaim: _claim,
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
