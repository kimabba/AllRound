import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_card.dart';
import 'profile_settings_widgets.dart';

// ────────────────────────────────────────────────────────────
// 등록 종목·등급 섹션
// ────────────────────────────────────────────────────────────

class SportsSection extends ConsumerWidget {
  final AsyncValue<List<UserSport>> sports;
  const SportsSection({super.key, required this.sports});

  Future<void> _setPrimarySport(
    BuildContext context,
    WidgetRef ref,
    List<UserSport> sports,
    String sport,
  ) async {
    final updated = sports
        .map(
          (s) => UserSport(
            sport: s.sport,
            grade: s.grade,
            isPrimary: s.sport == sport,
          ),
        )
        .toList();

    try {
      await ref.read(apiProvider).saveUserSports(updated);
      ref.invalidate(userSportsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${sportLabelFromString(sport)} 기준으로 변경했습니다.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('주 종목을 변경하지 못했습니다. 다시 시도해 주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '등록 종목·등급',
          action: SectionActionButton(
            label: '수정',
            onTap: () => context.push('/onboarding'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        sports.when(
          loading: () => AppCard(
            child: const SizedBox(
              height: 60,
              child: Center(child: LinearProgressIndicator()),
            ),
          ),
          error: (_, __) => AppCard(
            child: Padding(
              padding: AppSpacing.screen,
              child: Text(
                '종목 정보를 불러오지 못했습니다.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
          data: (list) => list.isEmpty
              ? AppCard(
                  child: Padding(
                    padding: AppSpacing.screen,
                    child: Text(
                      '아직 등록된 종목이 없습니다.',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: list
                      .map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: SportCard(
                            sport: s,
                            onSetPrimary: s.isPrimary
                                ? null
                                : () => _setPrimarySport(
                                      context,
                                      ref,
                                      list,
                                      s.sport,
                                    ),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class SportCard extends StatelessWidget {
  final UserSport sport;
  final VoidCallback? onSetPrimary;
  const SportCard({super.key, required this.sport, this.onSetPrimary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = sport.sport == 'tennis';
    final accentColor = isTennis ? cs.tertiary : cs.secondary;

    return AppCard(
      variant: AppCardVariant.elevated,
      borderRadius: BorderRadius.circular(16),
      child: Row(
        children: [
          ProfileSportThumbnail(sport: sport.sport),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sportLabelFromString(sport.sport),
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  gradeLabel(sport.grade),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (sport.isPrimary)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: AppRadius.pill,
              ),
              child: Text(
                '활성 종목 (필터 기준)',
                style: tt.labelSmall?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (onSetPrimary != null)
            TextButton(
              onPressed: onSetPrimary,
              child: const Text('주 종목으로 설정'),
            ),
        ],
      ),
    );
  }
}

class ProfileSportThumbnail extends StatelessWidget {
  const ProfileSportThumbnail({super.key, required this.sport});

  final String sport;

  @override
  Widget build(BuildContext context) {
    final isTennis = sport == 'tennis';

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 54,
        height: 54,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              isTennis
                  ? 'assets/images/tournaments/tennis-cover.jpg'
                  : 'assets/images/tournaments/futsal-cover.jpg',
              fit: BoxFit.cover,
            ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
            Icon(
              isTennis
                  ? Icons.sports_tennis_rounded
                  : Icons.sports_soccer_rounded,
              color: Colors.white,
              size: 23,
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 테니스 소속 협회 섹션 (multi-org)
// ────────────────────────────────────────────────────────────

class TennisOrgsSection extends StatelessWidget {
  final List<UserTennisOrg> orgs;
  const TennisOrgsSection({super.key, required this.orgs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '소속 테니스 협회'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            children: orgs
                .map((org) => OrgRow(org: org, isLast: org == orgs.last))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class OrgRow extends StatelessWidget {
  final UserTennisOrg org;
  final bool isLast;
  const OrgRow({super.key, required this.org, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final label = tennisOrgLabel(org.org);
    final shortLabel = tennisOrgShortLabel(org.org);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Center(
                  child: Text(
                    shortLabel.length <= 4
                        ? shortLabel
                        : shortLabel.substring(0, 4),
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: tt.bodyMedium),
                    if (org.regionCode != null)
                      Text(
                        regionLabel(org.regionCode!),
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (org.isPrimary)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: AppRadius.pill,
                  ),
                  child: Text(
                    '주',
                    style: tt.labelSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
      ],
    );
  }
}
