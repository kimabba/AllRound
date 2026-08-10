import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/org_ranking.dart';
import '../../models/player_result.dart';
import '../../models/org_ranking_snapshot.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import '../profile/my_record_widgets.dart';

/// 랭킹 표 행을 눌렀을 때 여는 그 선수의 전적 시트.
///
/// org_player_results_read RLS(2026-08-10)가 로그인 사용자 전체에게 열려
/// 있지만, 크롤러는 아직 "본인 연결 승인자"만 전적을 적재한다 — 연결 안
/// 된 대부분의 선수는 빈 목록이 정상이고, [RecordContent] 가 그 경우를
/// "아직 협회에 등록된 전적이 없습니다"로 이미 처리한다.
Future<void> openPlayerDetailSheet(BuildContext context, OrgRankingRow row) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PlayerDetailSheet(row: row),
  );
}

class _PlayerDetailSheet extends ConsumerWidget {
  const _PlayerDetailSheet({required this.row});

  final OrgRankingRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final orgPlayerId = row.orgPlayerId;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(row.playerName, style: tt.headlineSmall),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Text(
                '${tennisOrgShortLabel(row.orgCode)} · ${divisionLabel(row.divisionCode)}'
                '${row.clubRaw != null && row.clubRaw!.isNotEmpty ? ' · ${row.clubRaw}' : ''}',
                style: tt.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (orgPlayerId == null)
                Text('전적을 조회할 수 없는 행입니다.', style: tt.bodyMedium)
              else
                FutureBuilder<
                    ({List<PlayerResult> results, List<OrgRankingSnapshot> snapshots})>(
                  future: _loadRecord(ref, row, orgPlayerId),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (snap.hasError) {
                      return Text('전적을 불러오지 못했습니다.', style: tt.bodyMedium);
                    }
                    final data = snap.data;
                    return RecordContent(
                      results: data?.results ?? const [],
                      rankings: [row],
                      snapshots: data?.snapshots ?? const [],
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

Future<({List<PlayerResult> results, List<OrgRankingSnapshot> snapshots})>
    _loadRecord(WidgetRef ref, OrgRankingRow row, String orgPlayerId) async {
  final api = ref.read(apiProvider);
  final results = await api.playerResults(
    orgCode: row.orgCode,
    orgPlayerId: orgPlayerId,
  );
  final snapshots = await api.playerRankingHistory(
    orgCode: row.orgCode,
    divisionCode: row.divisionCode,
    orgPlayerId: orgPlayerId,
  );
  return (results: results, snapshots: snapshots);
}
