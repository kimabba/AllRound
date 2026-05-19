import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/tournament.dart';
import '../state/providers.dart';
import '../state/theme_provider.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import '../widgets/app_card.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final sports = ref.watch(userSportsProvider);
    final tennisOrgs = ref.watch(userTennisOrgsProvider);

    final email = user?.email ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _ProfileHeroSliver(initial: initial, email: email, sports: sports),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _SportsSection(sports: sports),
                const SizedBox(height: AppSpacing.xl),
                tennisOrgs.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (orgs) =>
                      orgs.isEmpty ? const SizedBox.shrink() : _TennisOrgsSection(orgs: orgs),
                ),
                const SizedBox(height: AppSpacing.xl),
                _AppearanceSection(),
                const SizedBox(height: AppSpacing.xl),
                _AccountSection(ref: ref),
                const SizedBox(height: AppSpacing.xxxl),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// Hero SliverAppBar
// ────────────────────────────────────────────────────────────

class _ProfileHeroSliver extends StatelessWidget {
  final String initial;
  final String email;
  final AsyncValue<List<UserSport>> sports;

  const _ProfileHeroSliver({
    required this.initial,
    required this.email,
    required this.sports,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final sportCount = sports.maybeWhen(data: (l) => l.length, orElse: () => 0);

    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      title: const Text('내 정보'),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary, cs.primaryContainer],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            kToolbarHeight + AppSpacing.xxl,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 아바타
              CircleAvatar(
                radius: 36,
                backgroundColor: cs.onPrimary.withValues(alpha: 0.2),
                child: Text(
                  initial,
                  style: tt.headlineMedium?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      email,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onPrimary.withValues(alpha: 0.85),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$sportCount',
                          style: tt.displayMedium?.copyWith(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '개 종목 등록됨',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onPrimary.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 등록 종목·등급 섹션
// ────────────────────────────────────────────────────────────

class _SportsSection extends StatelessWidget {
  final AsyncValue<List<UserSport>> sports;
  const _SportsSection({required this.sports});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: '등록 종목·등급',
          action: _SectionActionButton(
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
          error: (e, _) => AppCard(
            child: Padding(
              padding: AppSpacing.screen,
              child: Text('$e', style: TextStyle(color: cs.error)),
            ),
          ),
          data: (list) => list.isEmpty
              ? AppCard(
                  child: Padding(
                    padding: AppSpacing.screen,
                    child: Text(
                      '아직 등록된 종목이 없습니다.',
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                )
              : Column(
                  children: list
                      .map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: _SportCard(sport: s),
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _SportCard extends StatelessWidget {
  final UserSport sport;
  const _SportCard({required this.sport});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = sport.sport == 'tennis';
    final accentColor = isTennis ? cs.primary : cs.tertiary;

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              isTennis ? Icons.sports_tennis_rounded : Icons.sports_soccer_rounded,
              color: accentColor,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sportLabelFromString(sport.sport),
                  style: tt.titleMedium,
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
            ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 테니스 소속 협회 섹션 (multi-org)
// ────────────────────────────────────────────────────────────

class _TennisOrgsSection extends StatelessWidget {
  final List<UserTennisOrg> orgs;
  const _TennisOrgsSection({required this.orgs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: '소속 테니스 협회'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            children: orgs
                .map((org) => _OrgRow(org: org, isLast: org == orgs.last))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _OrgRow extends StatelessWidget {
  final UserTennisOrg org;
  final bool isLast;
  const _OrgRow({required this.org, required this.isLast});

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
                    shortLabel.length <= 4 ? shortLabel : shortLabel.substring(0, 4),
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

// ────────────────────────────────────────────────────────────
// 화면 설정 섹션 (다크모드 토글)
// ────────────────────────────────────────────────────────────

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final mode = ref.watch(themeModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: '화면 설정'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '다크 모드',
                style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_rounded),
                    label: Text('자동'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_rounded),
                    label: Text('라이트'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_rounded),
                    label: Text('다크'),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (s) =>
                    ref.read(themeModeProvider.notifier).set(s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: cs.primaryContainer,
                  selectedForegroundColor: cs.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 계정 섹션 (알림 + 로그아웃)
// ────────────────────────────────────────────────────────────

class _AccountSection extends StatelessWidget {
  final WidgetRef ref;
  const _AccountSection({required this.ref});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: '계정'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            children: [
              _ActionRow(
                icon: Icons.notifications_outlined,
                label: '알림 설정',
                subtitle: '대회 D-3·신청 마감 알림',
                onTap: () {},
              ),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
              _ActionRow(
                icon: Icons.logout_rounded,
                label: '로그아웃',
                accentColor: cs.error,
                onTap: () async {
                  await ref.read(supabaseProvider).auth.signOut();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? accentColor;
  final VoidCallback? onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    this.subtitle,
    this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = accentColor ?? cs.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: tt.bodyLarge?.copyWith(color: color),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (accentColor == null)
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 공통 헬퍼 위젯
// ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;

  const _SectionHeader({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          title,
          style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        if (action != null) ...[
          const Spacer(),
          action!,
        ],
      ],
    );
  }
}

class _SectionActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SectionActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: tt.labelMedium?.copyWith(color: cs.primary),
      ),
    );
  }
}
