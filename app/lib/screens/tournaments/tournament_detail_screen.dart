import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/regulation_body_lines.dart';
import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../testing/e2e_keys.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import '../../utils/recent_tournaments.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_skeleton_card.dart';
import '../../widgets/app_toast.dart';

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

  bool get _isPreviewTournament =>
      !kReleaseMode && widget.tournamentId.startsWith('preview-');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _rememberTournament(Tournament tournament) async {
    try {
      final userId = ref.read(currentUserProvider)?.id ?? 'guest';
      final store = await RecentTournamentStore.create();
      await store.record(userId, tournament);
    } catch (error) {
      debugPrint('recent tournament save error: $error');
    }
  }

  Future<void> _load() async {
    if (_isPreviewTournament) {
      setState(() {
        _t = _previewTournamentById(widget.tournamentId);
        _loading = false;
        _error = _t == null ? '프리뷰 대회 정보를 찾을 수 없습니다.' : null;
      });
      if (_t != null) await _rememberTournament(_t!);
      return;
    }

    try {
      final supa = ref.read(supabaseProvider);
      final row = await supa
          .from('tournaments')
          .select(
            '*, tennis_tournament_details(*), futsal_tournament_details(*)',
          )
          .eq('id', widget.tournamentId)
          .maybeSingle();
      if (row == null) {
        setState(() {
          _error = '대회 정보를 찾을 수 없습니다.';
          _loading = false;
        });
        return;
      }
      setState(() {
        _t = Tournament.fromJson(row);
        _loading = false;
      });
      await _rememberTournament(_t!);
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
    final isFav = (favorites.valueOrNull ?? const {}).contains(
      widget.tournamentId,
    );
    final isPreview = _isPreviewTournament;

    return Scaffold(
      key: AllRoundE2EKeys.tournamentDetailScreen,
      appBar: AppBar(
        title: const Text('대회'),
        actions: [
          if (_t != null && !isPreview)
            IconButton(
              key: isFav
                  ? AllRoundE2EKeys.tournamentFavoriteSaved
                  : AllRoundE2EKeys.tournamentFavoriteUnsaved,
              icon: Icon(
                isFav ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                color: isFav ? cs.primary : null,
              ),
              onPressed: () async {
                HapticFeedback.lightImpact();
                try {
                  await ref
                      .read(apiProvider)
                      .toggleFavorite(widget.tournamentId, !isFav);
                  ref.invalidate(favoriteIdsProvider);
                  ref.invalidate(myFavoriteTournamentsProvider);
                  ref.invalidate(myTournamentRecordsProvider);
                  if (!isFav && context.mounted) {
                    AppToast.show(
                      context,
                      '관심 대회로 저장했어요. 신청 마감일과 대회 3일 전에 알려드려요.',
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    AppToast.show(
                      context,
                      '관심 저장에 실패했어요. 잠시 후 다시 시도해 주세요.',
                      kind: AppToastKind.error,
                    );
                  }
                }
              },
            ),
        ],
      ),
      bottomNavigationBar: _t == null
          ? null
          : _TournamentApplyBar(tournament: _t!, isPreview: isPreview),
      body: _loading
          ? const _TournamentDetailLoadingState()
          : _error != null
              ? _TournamentDetailError(message: _error!, onRetry: _load)
              : _t == null
                  ? const AppEmptyState(
                      icon: Icons.event_busy_outlined,
                      title: '대회 정보가 없습니다',
                      description: '대회 목록에서 다른 대회를 확인해 주세요.',
                    )
                  : _DetailBody(t: _t!, df: _df, isPreview: isPreview),
    );
  }
}

class _TournamentDetailLoadingState extends StatelessWidget {
  const _TournamentDetailLoadingState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSkeletonCard(
      loading: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xxxl,
        ),
        children: [
          Container(height: 28, color: cs.surfaceContainerHighest),
          const SizedBox(height: AppSpacing.sm),
          FractionallySizedBox(
            widthFactor: 0.68,
            alignment: Alignment.centerLeft,
            child: Container(height: 16, color: cs.surfaceContainerHighest),
          ),
          const SizedBox(height: AppSpacing.xxl),
          for (var index = 0; index < 5; index++) ...[
            Container(
              height: AppSizes.listRow,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: cs.outlineVariant),
                ),
              ),
            ),
          ],
        ],
      ),
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
    final futsalCategory = t.sport == 'futsal'
        ? futsalEventCategoryLabel(t.futsalEventCategory)
        : '';

    final hasDescription =
        t.description != null && t.description!.trim().isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
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

              Text(
                sportLabelFromString(t.sport),
                style: tt.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                t.title,
                style: tt.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                ),
              ),
              if (t.organizer != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  t.organizer!,
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Text(
                    t.isRegistrationClosed ? '접수 마감' : '접수 중',
                    style: tt.labelMedium?.copyWith(
                      color: t.isRegistrationClosed
                          ? cs.onSurfaceVariant
                          : cs.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (t.applicationDeadline != null) ...[
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      '${df.format(t.applicationDeadline!)} 마감',
                      style: tt.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              if (t.posterUrl != null && t.posterUrl!.trim().isNotEmpty) ...[
                _TournamentPosterCard(url: t.posterUrl!.trim()),
                const SizedBox(height: AppSpacing.xl),
              ],

              _DetailFacts(
                date: _dateText(),
                location: t.location ?? t.region ?? '장소 확인 필요',
                division: t.format ??
                    (t.eligibleGrades.isEmpty
                        ? '부문 확인 필요'
                        : divisionLabel(t.eligibleGrades.first)),
                fee: t.entryFee == null
                    ? '주최 문의'
                    : '${t.entryFeeUnit == 'per_person' ? '인당' : '팀당'} ${_feeFormat.format(t.entryFee!)}원',
              ),
              if (futsalCategory.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  futsalCategory,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],

              const SizedBox(height: AppSpacing.lg),
              Divider(color: cs.outlineVariant),
              const SizedBox(height: AppSpacing.lg),

              // ── 출전 부서 ──
              Text(
                '출전 부서',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final g in t.eligibleGrades)
                    Chip(
                      label: Text(
                        divisionLabel(g) != g
                            ? divisionLabel(g)
                            : gradeLabel(g),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (t.isJointEvent)
                    Chip(
                      label: const Text('통합 대회'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── 대회 요강 (구조화 요강 → 폴백: 평문 description) ──
              _AccordionSection(
                icon: Icons.article_rounded,
                title: '대회 요강',
                initiallyExpanded: false,
                children: _buildRegulationChildren(
                  context,
                  hasDescription: hasDescription,
                ),
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

  /// 대회 요강 아코디언 본문.
  /// fields / body / notes 를 모두 표시(누락 0). 셋 다 비면 description 폴백 →
  /// 그것도 없으면 "아직 공지되지 않았습니다".
  List<Widget> _buildRegulationChildren(
    BuildContext context, {
    required bool hasDescription,
  }) {
    // 1) 구조화 요강 필드. prize/format 가 필드에 없으면 보강한다.
    //    단, body 가 동일 내용을 포함하면 과한 중복이 되므로 body 가 있을 땐 보강하지 않는다.
    final fields = <RegulationField>[...t.regulationFields];
    final hasBody =
        t.regulationBody != null && t.regulationBody!.trim().isNotEmpty;
    bool hasLabel(String label) =>
        fields.any((f) => f.label.replaceAll(' ', '') == label);

    if (!hasBody) {
      if (t.prize != null && t.prize!.trim().isNotEmpty && !hasLabel('시상')) {
        fields.add(RegulationField(label: '시상', value: t.prize!.trim()));
      }
      if (t.format != null &&
          t.format!.trim().isNotEmpty &&
          !hasLabel('경기방식')) {
        fields.add(RegulationField(label: '경기방식', value: t.format!.trim()));
      }
    }

    final notes = t.regulationNotes;

    if (fields.isNotEmpty || hasBody || notes.isNotEmpty) {
      final children = <Widget>[];

      // (a) 라벨/값 행
      if (fields.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final f in fields)
                  _RegulationFieldRow(label: f.label, value: f.value),
              ],
            ),
          ),
        );
      }

      // (b) 전체 요강 본문 ("\n" 보존)
      if (hasBody) {
        children.add(
          _RegulationBody(
            body: t.regulationBody!,
            withDivider: fields.isNotEmpty,
          ),
        );
      }

      // (c) 안내(※) 불릿
      if (notes.isNotEmpty) {
        children.add(_RegulationNotes(notes: notes));
      }

      children.add(const SizedBox(height: AppSpacing.sm));
      return children;
    }

    // 2) 폴백: 평문 description 을 그대로 줄바꿈 렌더 (라벨 분리 금지).
    if (hasDescription) {
      return [_RegulationPlainText(description: t.description!)];
    }

    // 3) 비어 있음.
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return [
      Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
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
    ];
  }
}

class _TournamentPosterCard extends StatelessWidget {
  const _TournamentPosterCard({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: AppRadius.card,
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              color: cs.surfaceContainerLow,
              child: const Center(child: CircularProgressIndicator()),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: cs.surfaceContainerLow,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    size: 36,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '포스터 이미지를 불러오지 못했습니다.',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DetailFacts extends StatelessWidget {
  const _DetailFacts({
    required this.date,
    required this.location,
    required this.division,
    required this.fee,
  });

  final String date;
  final String location;
  final String division;
  final String fee;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outline),
          bottom: BorderSide(color: cs.outline),
        ),
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _DetailFact(label: '일정', value: date)),
                VerticalDivider(width: 1, color: cs.outlineVariant),
                Expanded(
                  child: _DetailFact(label: '장소', value: location),
                ),
              ],
            ),
          ),
          Divider(color: cs.outlineVariant),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _DetailFact(label: '부문', value: division),
                ),
                VerticalDivider(width: 1, color: cs.outlineVariant),
                Expanded(child: _DetailFact(label: '참가비', value: fee)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailFact extends StatelessWidget {
  const _DetailFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 86),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
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
          Icon(Icons.visibility_outlined, size: 18, color: cs.onSurfaceVariant),
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
    final isClosed = tournament.isRegistrationClosed;
    final sourceUrl = tournament.sourceUrl?.trim();
    final hasSourceUrl =
        !isPreview && sourceUrl != null && sourceUrl.isNotEmpty;

    // 앱 내 신청은 아직 준비 중. 원본 공고 URL이 있으면 실제 접수 경로로 연결하고,
    // 없으면 준비 중임을 명확히 안내한다.
    final (IconData icon, String label, VoidCallback? onPressed) = isClosed
        ? (Icons.how_to_reg_rounded, '신청 마감', null)
        : hasSourceUrl
            ? (
                Icons.open_in_new_rounded,
                '원본 공고 보기',
                () async {
                  var ok = false;
                  try {
                    ok = await launchUrl(
                      Uri.parse(sourceUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (_) {
                    ok = false;
                  }
                  if (!ok && context.mounted) {
                    AppToast.show(
                      context,
                      '공고 페이지를 열 수 없어요. 대회 요강의 접수처를 확인해 주세요.',
                      kind: AppToastKind.error,
                    );
                  }
                },
              )
            : (
                Icons.how_to_reg_rounded,
                '대회 신청 (준비 중)',
                () => AppToast.show(
                      context,
                      isPreview
                          ? '프리뷰에서는 신청 화면 연결 전입니다.'
                          : '앱 내 신청 기능은 준비 중이에요. 대회 요강의 접수처로 신청해 주세요.',
                    ),
              );

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
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
        ),
      ),
    );
  }
}

class _TournamentDetailError extends StatelessWidget {
  const _TournamentDetailError({required this.message, required this.onRetry});

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
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: cs.outlineVariant),
            bottom: BorderSide(color: cs.outlineVariant),
          ),
        ),
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

/// 구조화 요강 한 줄 (라벨 + 값). 아코디언 내부 들여쓰기 스타일은
/// 기존 _InfoRow 와 동일하게 유지한다.
class _RegulationFieldRow extends StatelessWidget {
  const _RegulationFieldRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      // 카드 패딩(lg)에 맞춰 본문 폭 확보 — 56px 들여쓰기는 좁은 화면에서
      // 요강 텍스트를 과도하게 압축한다(가독성).
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
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
              value.isNotEmpty ? value : '-',
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

/// 요강 안내문(※) 블록: 구분선 + "안내" 소제목 + 불릿 리스트.
class _RegulationNotes extends StatelessWidget {
  const _RegulationNotes({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '안내',
            style: tt.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: tt.bodyMedium?.copyWith(
                      height: 1.45,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      note,
                      style: tt.bodyMedium?.copyWith(
                        height: 1.45,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 전체 요강 본문: 구분선 + "전체 요강" 소제목 + 마커 기반 계층 렌더.
///
/// 폰트 패밀리는 전부 tt.bodyMedium 으로 동일하게 두고, weight·color·
/// 들여쓰기·세로간격으로만 위계를 표현한다(_RegulationFieldRow/_RegulationNotes
/// 와 동일 톤). 줄 분류 규칙은 parseRegulationBody() 에 분리되어 테스트된다.
class _RegulationBody extends StatelessWidget {
  const _RegulationBody({required this.body, this.withDivider = true});

  final String body;
  final bool withDivider;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final base = tt.bodyMedium ?? const TextStyle();
    final lines = parseRegulationBody(body);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          if (withDivider) ...[
            Divider(color: cs.outlineVariant),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            '전체 요강',
            style: tt.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final line in lines) _line(context, line, base, cs),
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context,
    RegulationLine line,
    TextStyle base,
    ColorScheme cs,
  ) {
    switch (line.kind) {
      case RegulationLineKind.header:
        return Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.lg,
            bottom: AppSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 5, right: AppSpacing.sm),
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Text(
                  line.text,
                  style: base.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );

      case RegulationLineKind.item:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ', style: base.copyWith(color: cs.primary, height: 1.5)),
              Expanded(
                child: Text(
                  line.text,
                  style: base.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        );

      case RegulationLineKind.numbered:
        return Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.xs,
            left: AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  line.label ?? '',
                  style: base.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                ),
              ),
              Expanded(
                child: Text(
                  line.text,
                  style: base.copyWith(color: cs.onSurface, height: 1.5),
                ),
              ),
            ],
          ),
        );

      case RegulationLineKind.dash:
        return Padding(
          padding: const EdgeInsets.only(top: 2, left: AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '– ',
                style: base.copyWith(color: cs.onSurfaceVariant, height: 1.5),
              ),
              Expanded(
                child: Text(
                  line.text,
                  style: base.copyWith(color: cs.onSurface, height: 1.5),
                ),
              ),
            ],
          ),
        );

      case RegulationLineKind.tableRow:
        final cells = line.cells;
        return Container(
          margin: const EdgeInsets.only(top: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cells.isNotEmpty)
                Text(
                  cells.first,
                  style: base.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    height: 1.4,
                  ),
                ),
              for (final cell in cells.skip(1))
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    cell,
                    style: base.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        );

      case RegulationLineKind.labelValue:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${line.label}: ',
                  style: base.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                TextSpan(
                  text: line.value ?? '',
                  style: base.copyWith(color: cs.onSurface),
                ),
              ],
            ),
            style: base.copyWith(height: 1.5),
          ),
        );

      case RegulationLineKind.note:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            line.text,
            style: base.copyWith(color: cs.onSurfaceVariant, height: 1.5),
          ),
        );

      case RegulationLineKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            line.text,
            style: base.copyWith(color: cs.onSurface, height: 1.5),
          ),
        );
    }
  }
}

/// 폴백: 구조화 요강이 비어 있을 때 description 평문을 그대로 줄바꿈 렌더.
/// 라벨 분리/문장 쪼개기 금지 — 원문을 보존한다.
class _RegulationPlainText extends StatelessWidget {
  const _RegulationPlainText({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final style = tt.bodySmall?.copyWith(
      height: 1.6,
      color: cs.onSurfaceVariant,
    );
    // 카드와 중복되는 메타라인 제거 + 부서 접수 항목 줄바꿈.
    final lines = cleanPlainRegulationLines(description);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lines.isEmpty)
            Text(description.trim(), style: style)
          else
            for (var i = 0; i < lines.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.xs),
                child: Text(lines[i], style: style),
              ),
        ],
      ),
    );
  }
}

Tournament? _previewTournamentById(String id) {
  final now = DateTime.now();
  // 목록(_previewTournaments)과 동일하게 프리뷰 날짜를 이번 달 안에 고정해
  // 목록 카드와 상세의 일정이 어긋나지 않도록 한다.
  final lastDay = DateTime(now.year, now.month + 1, 0).day;
  DateTime inMonth(int offsetDays) =>
      DateTime(now.year, now.month, (now.day + offsetDays).clamp(1, lastDay));
  final tournaments = [
    Tournament(
      id: 'preview-futsal-sleague-2026',
      sport: 'futsal',
      title: '2026 생활체육 서울시민리그 풋살리그',
      organizer: '서울특별시풋살연맹',
      description: '''
참가부서: 입문 · 초급 · 중급 · 고급 · 선출
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
      eligibleGrades: const [
        'intro',
        'beginner',
        'intermediate',
        'advanced',
        'elite',
      ],
      prize: null,
      format: '서울시민리그 풋살 리그전',
      sourceUrl: 'https://www.sleague.or.kr/2026/futsal/',
      status: 'published',
      futsalEventCategory: 'sports_for_all',
    ),
    Tournament(
      id: 'preview-futsal-1',
      sport: 'futsal',
      title: '수도권 풋살 슈퍼컵',
      organizer: '서울 풋살 협회',
      description: '''
참가부서: 입문·초급·중급
신청마감: 대회 7일 전
대회일: 주말 양일 진행
장소: 서울 송파 풋살파크
참가비: 팀당 80,000원
경기방식: 5대5 조별리그 후 토너먼트
안내: 팀 대표자는 경기 시작 30분 전까지 접수 데스크에서 선수 명단을 확인해 주세요.
''',
      startDate: inMonth(4),
      endDate: inMonth(5),
      applicationDeadline: inMonth(1),
      region: '수도권',
      location: '서울 송파 풋살파크',
      eligibleGrades: const ['intro', 'beginner', 'intermediate'],
      entryFee: 80000,
      prize: '우승팀 구장 이용권',
      format: '5대5 조별리그',
      status: 'published',
      futsalEventCategory: 'private',
    ),
    Tournament(
      id: 'preview-futsal-2',
      sport: 'futsal',
      title: '부산 야간 풋살 리그',
      organizer: '부산 풋살 연합',
      description: '''
참가부서: 고급·선출
일시: 평일 야간 리그
장소: 부산 사직 풋살장
참가비: 팀당 100,000원
경기방식: 풀리그 후 순위 결정전
안내: 유니폼 색상은 접수 후 운영진 안내에 따라 조정됩니다.
''',
      startDate: inMonth(7),
      endDate: inMonth(7),
      applicationDeadline: inMonth(3),
      region: '부산·울산·경남',
      location: '부산 사직 풋살장',
      eligibleGrades: const ['advanced', 'elite'],
      entryFee: 100000,
      prize: '우승 트로피',
      format: '토너먼트',
      status: 'published',
      futsalEventCategory: 'regional_federation',
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
      startDate: inMonth(3),
      endDate: inMonth(4),
      applicationDeadline: inMonth(1),
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
참가부서: 3~5년 · 5년 이상
신청마감: 대회 14일 전
장소: 분당 테니스파크
참가비: 인당 50,000원
시상: 랭킹 포인트 및 부상
경기방식: 복식 토너먼트
안내: 파트너 변경은 신청 마감 전까지만 가능합니다.
''',
      startDate: inMonth(6),
      endDate: inMonth(6),
      applicationDeadline: inMonth(3),
      region: '수도권',
      location: '분당 테니스파크',
      eligibleGrades: const ['y3to5', 'over5y'],
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
