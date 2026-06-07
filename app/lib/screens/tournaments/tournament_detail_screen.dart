import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_card.dart';


class TournamentDetailScreen extends ConsumerStatefulWidget {
  const TournamentDetailScreen({super.key, required this.tournamentId});
  final String tournamentId;

  @override
  ConsumerState<TournamentDetailScreen> createState() =>
      _TournamentDetailScreenState();
}

class _TournamentDetailScreenState
    extends ConsumerState<TournamentDetailScreen> {
  Tournament? _t;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final supa = ref.read(supabaseProvider);
      final row = await supa
          .from('tournaments')
          .select()
          .eq('id', widget.tournamentId)
          .single();
      setState(() {
        _t = Tournament.fromJson(row);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  static final _df = DateFormat('yyyy년 M월 d일 (E)', 'ko');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final favorites = ref.watch(favoriteIdsProvider);
    final isFav = (favorites.valueOrNull ?? const {}).contains(widget.tournamentId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('대회 상세'),
        actions: [
          if (_t != null)
            IconButton(
              icon: Icon(
                isFav ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                color: isFav ? cs.primary : null,
              ),
              onPressed: () async {
                HapticFeedback.lightImpact();
                await ref.read(apiProvider).toggleFavorite(widget.tournamentId, !isFav);
                ref.invalidate(favoriteIdsProvider);
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _t == null
                  ? const Center(child: Text('대회 정보 없음'))
                  : _DetailBody(t: _t!, df: _df),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Tournament t;
  final DateFormat df;
  const _DetailBody({required this.t, required this.df});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = t.sport == 'tennis';
    final accentColor = isTennis ? cs.primary : cs.tertiary;
    // division_label_local이 있으면 우선 사용, 없으면 eligible_grades 코드에서 생성
    final grades = (t.divisionLabelLocal?.isNotEmpty == true)
        ? t.divisionLabelLocal!
        : formatEligibleGrades(t.eligibleGrades);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타이틀 + 종목 배지
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  isTennis
                      ? Icons.sports_tennis_rounded
                      : Icons.sports_soccer_rounded,
                  color: accentColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  t.title,
                  style: tt.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // 기본 정보 카드
          AppCard(
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.sports_rounded,
                  label: '종목',
                  value: sportLabelFromString(t.sport),
                  accent: accentColor,
                ),
                _Divider(),
                _InfoRow(
                  icon: Icons.calendar_today_rounded,
                  label: '시작일',
                  value: df.format(t.startDate),
                ),
                if (t.applicationDeadline != null) ...[
                  _Divider(),
                  _InfoRow(
                    icon: Icons.event_busy_rounded,
                    label: '신청 마감',
                    value: df.format(t.applicationDeadline!),
                    accent: cs.error,
                  ),
                ],
                if (t.region != null) ...[
                  _Divider(),
                  _InfoRow(
                    icon: Icons.place_rounded,
                    label: '지역',
                    value: t.region!,
                  ),
                ],
                if (t.location != null) ...[
                  _Divider(),
                  _InfoRow(
                    icon: Icons.location_on_rounded,
                    label: '상세 장소',
                    value: t.location!,
                  ),
                ],
                _Divider(),
                _InfoRow(
                  icon: Icons.emoji_events_rounded,
                  label: '출전 등급',
                  value: grades,
                  accent: accentColor,
                ),
                if (t.entryFee != null) ...[
                  _Divider(),
                  _InfoRow(
                    icon: Icons.payments_rounded,
                    label: '참가비',
                    value: '${t.entryFee}원',
                  ),
                ],
                if (t.prize != null) ...[
                  _Divider(),
                  _InfoRow(
                    icon: Icons.workspace_premium_rounded,
                    label: '시상',
                    value: t.prize!,
                  ),
                ],
                if (t.format != null) ...[
                  _Divider(),
                  _InfoRow(
                    icon: Icons.format_list_numbered_rounded,
                    label: '진행 방식',
                    value: t.format!,
                  ),
                ],
                if (t.organizer != null) ...[
                  _Divider(),
                  _InfoRow(
                    icon: Icons.business_rounded,
                    label: '주최',
                    value: t.organizer!,
                  ),
                ],
              ],
            ),
          ),

          // 대회 안내 문구 (수기 입력된 경우만 표시, 크롤 보일러플레이트 제외)
          if (t.description != null &&
              t.description!.trim().isNotEmpty &&
              !t.description!.startsWith('참가부서:') &&
              t.description!.length < 500) ...[
            const SizedBox(height: AppSpacing.xl),
            Text('대회 안내', style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Text(
                t.description!,
                style: tt.bodyMedium?.copyWith(height: 1.7),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? accent;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = accent ?? cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value, style: tt.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      color: cs.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

