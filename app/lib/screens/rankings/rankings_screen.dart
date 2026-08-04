import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/org_ranking.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';

/// 협회 랭킹표가 실제로 공표하는 부서 7개(광주·전남 동일, gnuboard_ranking 파서와
/// 일치). 부서 카탈로그 전체(rankingGradesForOrg)와 다르다 — 오픈부·베테랑부 등은
/// 대회 자격에는 쓰이지만 협회가 별도 랭킹표로 공표하지 않는다.
const _kRankingDivisions = <String, List<String>>{
  'gj': [
    'gj_m_gold',
    'gj_m_general',
    'gj_m_rookie',
    'gj_m_instructor',
    'gj_w_rookie',
    'gj_w_gukhwa',
    'gj_w_geumbae',
  ],
  'jn': [
    'jn_m_gold',
    'jn_m_general',
    'jn_m_rookie',
    'jn_m_instructor',
    'jn_w_rookie',
    'jn_w_gukhwa',
    'jn_w_geumbae',
  ],
};

// ── 순위표 ────────────────────────────────────────────────────────────────

/// 순위·성명·소속·포인트 한 줄. 데이터 주입형(네트워크 호출 없음) — 조회는
/// [RankingsScreen] 이 담당한다.
///
/// 저장은 rank_points/total_points 둘이지만(협회 규정상 다른 집계여야 함),
/// 현재 협회 화면이 전 행에서 같은 값을 내보내 화면엔 totalPoints 하나만 보여준다.
class RankingList extends StatelessWidget {
  const RankingList({
    super.key,
    required this.rows,
    required this.linkedOrgPlayerId,
  });

  final List<OrgRankingRow> rows;
  final String? linkedOrgPlayerId;

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
          ),
          if (i < rows.length - 1)
            Divider(height: 1, color: cs.outlineVariant),
        ],
      ],
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.row, required this.isMine});

  final OrgRankingRow row;
  final bool isMine;

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
        ],
      ),
    );
  }
}

// ── 출처 표기 ─────────────────────────────────────────────────────────────

/// 개인정보 보호책임자 연락처(privacy-policy.html 7항과 동일해야 한다).
/// 이 화면은 앱 미가입자의 실명도 표시하므로, 본인이 발견하고 삭제·정정을
/// 요청할 수 있는 유일한 창구가 여기다.
const _kPrivacyContactEmail = 'ssfak@jyoungad.kr';

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
  });

  final List<OrgRankingRow> rows;
  final String? linkedOrgPlayerId;
  final OrgRankingRow? candidate;
  final bool hasPendingClaim;
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
    final links = await api.myOrgPlayerLinks(_orgCode);
    final candidates = await api.myRankingCandidates();

    String? linkedOrgPlayerId;
    final pendingIds = <String>{};
    for (final link in links) {
      final status = link['status'] as String;
      final orgPlayerId = link['org_player_id'] as String;
      if (status == 'confirmed') linkedOrgPlayerId = orgPlayerId;
      if (status == 'pending') pendingIds.add(orgPlayerId);
    }

    OrgRankingRow? candidate;
    for (final c in candidates) {
      if (c.orgCode == _orgCode &&
          c.orgPlayerId != null &&
          !pendingIds.contains(c.orgPlayerId)) {
        candidate = c;
        break;
      }
    }

    return _RankingScreenData(
      rows: rows,
      linkedOrgPlayerId: linkedOrgPlayerId,
      candidate: candidate,
      hasPendingClaim: pendingIds.isNotEmpty,
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
    try {
      await ref.read(apiProvider).claimRanking(candidate);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('신청 실패: $e')));
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
                      ),
                    if (data.rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.xxl),
                        child: Center(child: Text('공표된 랭킹이 없습니다')),
                      )
                    else
                      RankingList(
                        rows: data.rows,
                        linkedOrgPlayerId: data.linkedOrgPlayerId,
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
