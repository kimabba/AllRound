import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config.dart';
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
    if (AppConfig.userDesignPreview &&
        widget.tournamentId.startsWith('preview-')) {
      setState(() {
        _t = _previewTournamentById(widget.tournamentId);
        _loading = false;
        _error = _t == null ? '프리뷰 대회 정보를 찾을 수 없습니다.' : null;
      });
      return;
    }

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
    final isFav =
        (favorites.valueOrNull ?? const {}).contains(widget.tournamentId);
    final isPreview = AppConfig.userDesignPreview &&
        widget.tournamentId.startsWith('preview-');

    return Scaffold(
      appBar: AppBar(
        title: const Text('대회 상세'),
        actions: [
          if (_t != null && !isPreview)
            IconButton(
              icon: Icon(
                isFav ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                color: isFav ? cs.primary : null,
              ),
              onPressed: () async {
                HapticFeedback.lightImpact();
                await ref
                    .read(apiProvider)
                    .toggleFavorite(widget.tournamentId, !isFav);
                ref.invalidate(favoriteIdsProvider);
              },
            ),
        ],
      ),
      bottomNavigationBar: _t == null
          ? null
          : _TournamentApplyBar(
              tournament: _t!,
              isPreview: isPreview,
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _TournamentDetailError(message: _error!, onRetry: _load)
              : _t == null
                  ? const Center(child: Text('대회 정보 없음'))
                  : _DetailBody(t: _t!, df: _df, isPreview: isPreview),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Tournament t;
  final DateFormat df;
  final bool isPreview;
  const _DetailBody({
    required this.t,
    required this.df,
    required this.isPreview,
  });

  static final _feeFormat = NumberFormat.decimalPattern('ko');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = t.sport == 'tennis';
    final accentColor = isTennis ? cs.primary : cs.tertiary;
    final grades = _displayGrades(t);

    final hasDescription =
        t.description != null && t.description!.trim().isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.huge,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isPreview) ...[
                const _DetailPreviewBanner(),
                const SizedBox(height: AppSpacing.md),
              ],
              _TournamentHero(
                tournament: t,
                grades: grades,
                accentColor: accentColor,
                dateText: _dateText(),
              ),
              const SizedBox(height: AppSpacing.md),
              _QuickInfoGrid(
                rows: [
                  _QuickInfo(
                    icon: Icons.calendar_month_rounded,
                    label: '대회일',
                    value: _dateText(),
                  ),
                  _QuickInfo(
                    icon: Icons.event_busy_rounded,
                    label: '신청 마감',
                    value: t.applicationDeadline == null
                        ? '주최 문의'
                        : df.format(t.applicationDeadline!),
                    accent: t.applicationDeadline == null ? null : cs.error,
                  ),
                  _QuickInfo(
                    icon: Icons.place_rounded,
                    label: '장소',
                    value: t.location ?? t.region ?? '장소 확인 필요',
                  ),
                  _QuickInfo(
                    icon: Icons.payments_rounded,
                    label: '참가비',
                    value: t.entryFee == null
                        ? '주최 문의'
                        : '${t.entryFeeUnit == 'per_person' ? '인당' : '팀당'} ${_feeFormat.format(t.entryFee!)}원',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '출전 조건',
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        _InfoChip(
                          icon: Icons.sports_rounded,
                          label: sportLabelFromString(t.sport),
                          color: accentColor,
                        ),
                        _InfoChip(
                          icon: Icons.emoji_events_rounded,
                          label: grades,
                          color: accentColor,
                        ),
                        if (t.isJointEvent)
                          _InfoChip(
                            icon: Icons.groups_rounded,
                            label: '통합 대회',
                            color: cs.secondary,
                          ),
                        if (t.format != null)
                          _InfoChip(
                            icon: Icons.format_list_numbered_rounded,
                            label: t.format!,
                            color: cs.primary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // 1. 기본 정보 (기본 열림)
              _AccordionSection(
                icon: Icons.info_outline_rounded,
                title: '기본 정보',
                initiallyExpanded: true,
                children: [
                  _InfoRow(
                    icon: Icons.sports_rounded,
                    label: '종목',
                    value: sportLabelFromString(t.sport),
                  ),
                  _InfoRow(
                    icon: Icons.calendar_today_rounded,
                    label: '대회일',
                    value: _dateText(),
                  ),
                  if (t.region != null)
                    _InfoRow(
                      icon: Icons.place_rounded,
                      label: '지역',
                      value: t.region!,
                    ),
                  if (t.location != null)
                    _InfoRow(
                      icon: Icons.location_on_rounded,
                      label: '장소',
                      value: t.location!,
                    ),
                  if (t.organizer != null)
                    _InfoRow(
                      icon: Icons.business_rounded,
                      label: '주최',
                      value: t.organizer!,
                    ),
                ],
              ),

              // 2. 출전 등급
              _AccordionSection(
                icon: Icons.emoji_events_rounded,
                title: '출전 등급',
                initiallyExpanded: true,
                children: [
                  _InfoRow(
                    icon: Icons.emoji_events_rounded,
                    label: '부서',
                    value: grades,
                  ),
                  if (t.isJointEvent)
                    _InfoRow(
                      icon: Icons.groups_rounded,
                      label: '통합',
                      value: '통합 대회',
                    ),
                ],
              ),

              // 3. 참가 안내
              _AccordionSection(
                icon: Icons.how_to_reg_rounded,
                title: '참가 안내',
                initiallyExpanded: false,
                children: [
                  if (t.applicationDeadline != null)
                    _InfoRow(
                      icon: Icons.event_busy_rounded,
                      label: '신청 마감',
                      value: df.format(t.applicationDeadline!),
                      accent: cs.error,
                      showIcon: false,
                    ),
                  if (t.entryFee != null)
                    _InfoRow(
                      icon: Icons.payments_rounded,
                      label: '참가비',
                      value:
                          '${t.entryFeeUnit == 'per_person' ? '인당' : '팀당'} ${_feeFormat.format(t.entryFee!)}원',
                      showIcon: false,
                    ),
                  if (t.prize != null)
                    _InfoRow(
                      icon: Icons.workspace_premium_rounded,
                      label: '시상',
                      value: t.prize!,
                      showIcon: false,
                    ),
                  if (t.format != null)
                    _InfoRow(
                      icon: Icons.format_list_numbered_rounded,
                      label: '진행 방식',
                      value: t.format!,
                      showIcon: false,
                    ),
                  if (t.applicationDeadline == null &&
                      t.entryFee == null &&
                      t.prize == null &&
                      t.format == null)
                    _InfoRow(
                      icon: Icons.info_outline,
                      label: '안내',
                      value: '상세 참가 안내는 주최 측에 문의해 주세요.',
                      showIcon: false,
                    ),
                ],
              ),

              // 4. 대회 요강 (크롤된 상세 내용 → 정형화)
              _AccordionSection(
                icon: Icons.article_rounded,
                title: '대회 요강',
                initiallyExpanded: false,
                children: [
                  if (hasDescription && t.description!.length > 100)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final section in _parseDescription(
                          t.description!,
                          sportLabel: sportLabelFromString(t.sport),
                        ))
                          _DescriptionLine(section: section),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 18, color: cs.onSurfaceVariant),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              '상세 요강이 아직 공지되지 않았습니다.\n주최 측에서 공지하면 자동으로 업데이트됩니다.',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: AppSpacing.xxxl),
            ],
          ),
        ),
      ),
    );
  }

  String _dateText() {
    final start = df.format(t.startDate);
    final end = t.endDate;
    if (end == null || _isSameDay(t.startDate, end)) return start;
    return '$start ~ ${df.format(end)}';
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _TournamentHero extends StatelessWidget {
  const _TournamentHero({
    required this.tournament,
    required this.grades,
    required this.accentColor,
    required this.dateText,
  });

  final Tournament tournament;
  final String grades;
  final Color accentColor;
  final String dateText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = tournament.sport == 'tennis';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.18),
            cs.surfaceContainerLowest,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  isTennis
                      ? Icons.sports_tennis_rounded
                      : Icons.sports_soccer_rounded,
                  color: accentColor,
                  size: 30,
                ),
              ),
              const Spacer(),
              _StatusPill(status: tournament.status),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            tournament.title,
            style: tt.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.18,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            [
              if (tournament.organizer != null) tournament.organizer!,
              dateText,
            ].join(' · '),
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _InfoChip(
                icon: Icons.place_rounded,
                label: tournament.region ?? '지역 확인 필요',
                color: accentColor,
              ),
              _InfoChip(
                icon: Icons.emoji_events_rounded,
                label: grades,
                color: accentColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isClosed = status == 'closed' || status == 'cancelled';
    final label = isClosed ? '마감' : '모집중';
    final color = isClosed ? cs.outline : cs.primary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pill,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _QuickInfo {
  const _QuickInfo({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? accent;
}

class _QuickInfoGrid extends StatelessWidget {
  const _QuickInfoGrid({required this.rows});

  final List<_QuickInfo> rows;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.25,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemBuilder: (context, index) => _QuickInfoTile(info: rows[index]),
    );
  }
}

class _QuickInfoTile extends StatelessWidget {
  const _QuickInfoTile({required this.info});

  final _QuickInfo info;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = info.accent ?? cs.primary;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(info.icon, size: 18, color: color),
              const SizedBox(width: AppSpacing.xs),
              Text(
                info.label,
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            info.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPreviewBanner extends StatelessWidget {
  const _DetailPreviewBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '프리뷰 데이터로 대회 상세 화면을 확인 중입니다.',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TournamentApplyBar extends StatelessWidget {
  const _TournamentApplyBar({
    required this.tournament,
    required this.isPreview,
  });

  final Tournament tournament;
  final bool isPreview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isClosed = tournament.status == 'closed' ||
        tournament.status == 'cancelled' ||
        (tournament.applicationDeadline != null &&
            tournament.applicationDeadline!.isBefore(DateTime.now()));

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: FilledButton.icon(
          onPressed: isClosed
              ? null
              : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isPreview
                            ? '프리뷰에서는 신청 화면 연결 전입니다.'
                            : '대회 신청 기능은 준비 중입니다.',
                      ),
                    ),
                  );
                },
          icon: const Icon(Icons.how_to_reg_rounded),
          label: Text(isClosed ? '신청 마감' : '대회 신청하기'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
          ),
        ),
      ),
    );
  }
}

class _TournamentDetailError extends StatelessWidget {
  const _TournamentDetailError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 44, color: cs.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              '대회 정보를 불러오지 못했어요',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DescSection {
  const _DescSection(this.text, {this.value, this.isHeader = false});

  final String text;
  final String? value;
  final bool isHeader;
}

/// 크롤된 대회 요강 텍스트를 키워드 기반으로 섹션 분리 + 자동 줄바꿈
List<_DescSection> _parseDescription(String raw, {required String sportLabel}) {
  // 0단계: 하단 보일러플레이트 제거 (협회 사이트 공통 푸터)
  var text = raw;
  for (final marker in ['개인정보 취급방침', 'COPYRIGHT', '홈페이지바로가기']) {
    final idx = text.indexOf(marker);
    if (idx > 0) text = text.substring(0, idx);
  }

  // 0.1단계: 신청 폼 잔해 제거
  text = text
      .replaceAll(RegExp(r'이점 참고하여 신중하게 신청 바랍니다'), '')
      .replaceAll(RegExp(r'입금대기중을 클릭하여 입금계좌로 입금후로 입금일 입금자를 등록해주시기 바랍니다\.?'), '')
      .replaceAll(
          RegExp(r'참가부서\s+신청기간\s+경기일시\s+현재신청팀\s+신청목록\s+신청하기\s+입금내역'), '')
      .replaceAll(RegExp(r'참가비\s+입금\s*×\s*팀?참가비\s+입금\s*×\s*\.?'), '')
      .replaceAll(RegExp(r'참가비\s+입금\s*×\s*\.?'), '')
      .replaceAll(RegExp(r'\[신청대기\]|\[신청마감\]|\[신청중\]'), '')
      .replaceAll(RegExp(r'부서추후공지'), '');

  text = text.trim();
  if (text.isEmpty) return [];

  // 0.5단계: 파이프 구분 메타데이터 (참가부서: ... | 신청마감: ...) → 줄바꿈
  text = text.replaceAll(' | ', '\n');

  // 1단계: 핵심 키워드 앞에 줄바꿈 삽입
  text = text
      .replaceAllMapped(RegExp(r'(참가부서\s*:?\s*)'), (m) => '\n참가부서: ')
      .replaceAllMapped(RegExp(r'(신청마감\s*:?\s*)'), (m) => '\n신청마감: ')
      .replaceAllMapped(RegExp(r'(대회일\s*:?\s*)'), (m) => '\n대회일: ')
      .replaceAllMapped(RegExp(r'(지역\s*:?\s*)'), (m) => '\n지역: ')
      .replaceAllMapped(RegExp(r'(장\s*소\s*:?\s*)'), (m) => '\n장소: ')
      .replaceAllMapped(RegExp(r'(주\s*최\s*:?\s*)'), (m) => '\n주최: ')
      .replaceAllMapped(RegExp(r'(주\s*관\s*:?\s*)'), (m) => '\n주관: ')
      .replaceAllMapped(RegExp(r'(후\s*원\s*:?\s*)'), (m) => '\n후원: ')
      .replaceAllMapped(RegExp(r'(협\s*찬\s*:?\s*)'), (m) => '\n협찬: ')
      .replaceAllMapped(
          RegExp(r'(참가비\s*:?\s*|참\s*가\s*비\s*:?\s*)'), (m) => '\n참가비: ')
      .replaceAllMapped(
          RegExp(r'(입금계좌\s*:?\s*|입금\s*계좌\s*:?\s*)'), (m) => '\n입금계좌: ')
      .replaceAllMapped(RegExp(r'(접수\s*마감)'), (m) => '\n접수마감: ')
      .replaceAllMapped(
          RegExp(r'(사\s*용\s*구\s*:?\s*|공\s*인\s*구\s*:?\s*)'), (m) => '\n사용구: ')
      .replaceAllMapped(RegExp(r'(경기\s*종목\s*:?\s*)'), (m) => '\n경기종목: ')
      .replaceAllMapped(RegExp(r'(경기\s*방식\s*:?\s*)'), (m) => '\n경기방식: ')
      .replaceAllMapped(RegExp(r'(일\s*시\s*:?\s*)'), (m) => '\n일시: ')
      .replaceAllMapped(RegExp(r'(안\s*내\s*:?\s*)'), (m) => '\n안내: ')
      .replaceAllMapped(RegExp(r'(참가\s*접수\s*:?\s*)'), (m) => '\n참가접수: ');

  // 2단계: 특수 마커 줄바꿈
  text = text
      .replaceAll(RegExp(r'[◈◇★●▶]\s*'), '\n• ')
      .replaceAll(RegExp(r'※\s*'), '\n※ ');

  // 3단계: 자동 줄바꿈 — 문장 끝(. 다) 뒤 + 부서별 정보 분리
  text = text
      .replaceAllMapped(RegExp(r'(\.\s+)(?=[가-힣])'), (m) => '.\n') // 마침표 뒤
      .replaceAllMapped(
          RegExp(r'(다\.\s*)(?=[가-힣A-Z])'), (m) => '다.\n') // "~합니다." 뒤
      .replaceAllMapped(
          RegExp(r'(요\.\s*)(?=[가-힣A-Z])'), (m) => '요.\n') // "~세요." 뒤
      .replaceAllMapped(
          RegExp(r'(\)\s*)(?=[가-힣]{2,}부\s)'), (m) => ')\n') // ") 골드부" → 줄바꿈
      .replaceAllMapped(
          RegExp(r'(08시\d+분\s*)(?=[가-힣])'), (m) => '${m[1]}\n'); // 시간 뒤 부서 분리

  final lines =
      text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  final sections = <_DescSection>[];
  final headerPattern = RegExp(
    r'^(참가부서|신청마감|대회일|지역|장소|주최|주관|후원|협찬|참가비|입금계좌|접수마감|사용구|경기종목|경기방식|일시|안내|참가접수):\s*(.*)$',
  );
  const duplicateLabels = {
    '참가부서',
    '신청마감',
    '대회일',
    '지역',
    '장소',
    '참가비',
    '접수마감',
    '일시',
  };

  for (final line in lines) {
    final match = headerPattern.firstMatch(line);
    if (match != null) {
      final label = match.group(1) ?? line;
      if (duplicateLabels.contains(label)) continue;
      final rawValue = (match.group(2) ?? '').trim();
      sections.add(
        _DescSection(
          label,
          value: label == '경기종목' ? sportLabel : rawValue,
          isHeader: true,
        ),
      );
    } else {
      if (sections.isNotEmpty && sections.last.text == '안내') {
        final previous = sections.removeLast();
        final previousValue = previous.value?.trim();
        sections.add(
          _DescSection(
            '안내',
            value: [
              if (previousValue != null && previousValue.isNotEmpty)
                previousValue,
              line,
            ].join('\n'),
            isHeader: true,
          ),
        );
        continue;
      }
      sections.add(_DescSection(line));
    }
  }

  return sections;
}

String _displayGrades(Tournament t) {
  final local = t.divisionLabelLocal?.trim();
  if (local == null || local.isEmpty) {
    return formatEligibleGrades(t.eligibleGrades);
  }

  return local
      .split(RegExp(r'\s*(?:·|,|/)\s*'))
      .where((part) => part.trim().isNotEmpty)
      .map((part) => divisionLabel(part.trim()))
      .join(' · ');
}

class _DescriptionLine extends StatelessWidget {
  const _DescriptionLine({required this.section});

  final _DescSection section;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (!section.isHeader) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(
          section.text,
          style: tt.bodySmall?.copyWith(
            height: 1.6,
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 56,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              section.text,
              style: tt.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(
              section.value?.isNotEmpty == true ? section.value! : '-',
              style: tt.bodyMedium?.copyWith(
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccordionSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool initiallyExpanded;
  final List<Widget> children;

  const _AccordionSection({
    required this.icon,
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(icon, size: 20, color: cs.primary),
          title: Text(
            title,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          children: children,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? accent;
  final bool showIcon;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 56,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: tt.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(
              value,
              style: tt.bodyMedium?.copyWith(
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Tournament? _previewTournamentById(String id) {
  final now = DateTime.now();
  final tournaments = [
    Tournament(
      id: 'preview-futsal-sleague-2026',
      sport: 'futsal',
      title: '2026 생활체육 서울시민리그 풋살리그',
      organizer: '서울특별시풋살연맹',
      description: '''
참가부서: 초급 · 중급 · 고급
신청기간: 2026년 5월 1일 ~ 2026년 6월 7일
대회일: 2026년 6월 20일 ~ 2026년 10월 11일
지역: 서울
장소: 서울시민리그 풋살 공식 경기장소
경기종목: 5인제 풋살 리그전
안내: A조, B조, C조, D조 경기일정 및 결과와 지역·권역·결선 경기장소는 서울시민리그 공식 페이지에서 확인할 수 있습니다. 대표 연락처는 02-415-8711입니다.
''',
      startDate: DateTime(2026, 6, 20),
      endDate: DateTime(2026, 10, 11),
      applicationDeadline: DateTime(2026, 6, 7),
      region: '서울',
      location: '서울시민리그 풋살 공식 경기장소',
      eligibleGrades: const ['beginner', 'intermediate', 'advanced'],
      prize: null,
      format: '서울시민리그 풋살 리그전',
      sourceUrl: 'https://www.sleague.or.kr/2026/futsal/',
      status: 'published',
    ),
    Tournament(
      id: 'preview-futsal-1',
      sport: 'futsal',
      title: '수도권 풋살 슈퍼컵',
      organizer: '서울 풋살 협회',
      description: '''
참가부서: 초급·중급
신청마감: 대회 7일 전
대회일: 주말 양일 진행
장소: 서울 송파 풋살파크
참가비: 팀당 80,000원
경기방식: 5대5 조별리그 후 토너먼트
안내: 팀 대표자는 경기 시작 30분 전까지 접수 데스크에서 선수 명단을 확인해 주세요.
''',
      startDate: now.add(const Duration(days: 10)),
      endDate: now.add(const Duration(days: 11)),
      applicationDeadline: now.add(const Duration(days: 4)),
      region: '수도권',
      location: '서울 송파 풋살파크',
      eligibleGrades: const ['beginner', 'intermediate'],
      entryFee: 80000,
      prize: '우승팀 구장 이용권',
      format: '5대5 조별리그',
      status: 'published',
    ),
    Tournament(
      id: 'preview-futsal-2',
      sport: 'futsal',
      title: '부산 야간 풋살 리그',
      organizer: '부산 풋살 연합',
      description: '''
참가부서: 고급
일시: 평일 야간 리그
장소: 부산 사직 풋살장
참가비: 팀당 100,000원
경기방식: 풀리그 후 순위 결정전
안내: 유니폼 색상은 접수 후 운영진 안내에 따라 조정됩니다.
''',
      startDate: now.add(const Duration(days: 18)),
      endDate: now.add(const Duration(days: 18)),
      applicationDeadline: now.add(const Duration(days: 11)),
      region: '부산·울산·경남',
      location: '부산 사직 풋살장',
      eligibleGrades: const ['advanced'],
      entryFee: 100000,
      prize: '우승 트로피',
      format: '토너먼트',
      status: 'published',
    ),
    Tournament(
      id: 'preview-tennis-1',
      sport: 'tennis',
      title: '광주 오픈 테니스 챌린지',
      organizer: '광주테니스협회',
      description: '''
참가부서: 1년 미만 · 1~3년
신청마감: 대회 5일 전
대회일: 토·일 양일
지역: 광주
장소: 염주실내테니스장
참가비: 인당 40,000원
경기종목: 복식 조별리그
안내: 참가자는 신분 확인 후 코트 배정을 받습니다. 우천 시 실내 코트 배정 상황에 따라 경기 시간이 조정될 수 있습니다.
''',
      startDate: now.add(const Duration(days: 12)),
      endDate: now.add(const Duration(days: 13)),
      applicationDeadline: now.add(const Duration(days: 5)),
      region: '광주',
      location: '염주실내테니스장',
      eligibleGrades: const ['under1y', 'y1to3'],
      entryFee: 40000,
      entryFeeUnit: 'per_person',
      prize: '우승 상품권',
      format: '복식 조별리그',
      status: 'published',
    ),
    Tournament(
      id: 'preview-tennis-2',
      sport: 'tennis',
      title: '수도권 동호인 랭킹전',
      organizer: 'KATA 수도권 지부',
      description: '''
참가부서: 중급·고급
신청마감: 대회 14일 전
장소: 분당 테니스파크
참가비: 인당 50,000원
시상: 랭킹 포인트 및 부상
경기방식: 복식 토너먼트
안내: 파트너 변경은 신청 마감 전까지만 가능합니다.
''',
      startDate: now.add(const Duration(days: 21)),
      endDate: now.add(const Duration(days: 21)),
      applicationDeadline: now.add(const Duration(days: 14)),
      region: '수도권',
      location: '분당 테니스파크',
      eligibleGrades: const ['intermediate', 'advanced'],
      entryFee: 50000,
      entryFeeUnit: 'per_person',
      prize: '랭킹 포인트',
      format: '복식 토너먼트',
      status: 'published',
    ),
  ];

  for (final tournament in tournaments) {
    if (tournament.id == id) return tournament;
  }
  return null;
}
