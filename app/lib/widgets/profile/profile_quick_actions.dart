import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import '../app_card.dart';
import 'profile_settings_widgets.dart';

class ProfileQuickActions extends ConsumerWidget {
  const ProfileQuickActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sports = ref.watch(userSportsProvider);
    final orgs = ref.watch(userTennisOrgsProvider);
    final favorites = ref.watch(myTournamentRecordsProvider).value;
    final clubs = ref.watch(myClubsProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '내 스포츠',
          action: SectionActionButton(
            label: '수정',
            onTap: () => context.push('/onboarding'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _SportsSummary(sports: sports),
              orgs.maybeWhen(
                data: (items) => items.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          const _ProfileDivider(),
                          for (var index = 0;
                              index < items.length;
                              index++) ...[
                            _OrgSummary(org: items[index]),
                            if (index < items.length - 1)
                              const _ProfileDivider(),
                          ],
                        ],
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(title: '내 활동'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _ActivityRow(
                icon: Icons.favorite_border_rounded,
                title: '관심 대회',
                value: favorites == null ? '불러오는 중' : '${favorites.length}개',
                onTap: () => context.push('/favorites'),
              ),
              const _ProfileDivider(),
              _ActivityRow(
                icon: Icons.groups_2_outlined,
                title: '내 클럽',
                value: clubs == null ? '불러오는 중' : '${clubs.length}개',
                onTap: () => context.push('/clubs'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SportsSummary extends StatelessWidget {
  const _SportsSummary({required this.sports});
  final AsyncValue<List<UserSport>> sports;

  @override
  Widget build(BuildContext context) {
    return sports.when(
      loading: () =>
          const _InfoRow(icon: Icons.sports_rounded, title: '종목 정보를 불러오는 중'),
      error: (_, __) => const _InfoRow(
          icon: Icons.error_outline_rounded, title: '종목 정보를 불러오지 못했습니다'),
      data: (items) {
        if (items.isEmpty) {
          return const _InfoRow(
              icon: Icons.add_circle_outline_rounded,
              title: '등록된 종목이 없습니다',
              subtitle: '수정을 눌러 종목을 등록해 주세요');
        }
        final primary =
            items.where((item) => item.isPrimary).firstOrNull ?? items.first;
        final extraCount = items.length - 1;
        return _InfoRow(
          icon: primary.sport == 'tennis'
              ? Icons.sports_tennis_rounded
              : Icons.sports_soccer_rounded,
          title: '${sportLabelFromString(primary.sport)} · 기본 종목',
          subtitle: [
            gradeLabel(primary.grade),
            if (extraCount > 0) '외 $extraCount개 종목'
          ].join(' · '),
        );
      },
    );
  }
}

class _OrgSummary extends StatelessWidget {
  const _OrgSummary({required this.org});
  final UserTennisOrg org;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (org.division.trim().isNotEmpty) org.division,
      if (org.regionCode != null) regionLabel(org.regionCode!),
    ];
    return _InfoRow(
      icon: Icons.workspace_premium_outlined,
      title: tennisOrgLabel(org.org),
      subtitle: details.isEmpty ? null : details.join(' · '),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(
      {required this.icon,
      required this.title,
      required this.value,
      required this.onTap});
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: cs.primary),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _ProfileDivider extends StatelessWidget {
  const _ProfileDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: AppSpacing.xl,
      endIndent: AppSpacing.md,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
