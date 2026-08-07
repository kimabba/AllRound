import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import '../app_card.dart';
import 'profile_settings_widgets.dart';

class ProfileQuickActions extends ConsumerWidget {
  const ProfileQuickActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(myTournamentRecordsProvider).value;
    final clubs = ref.watch(myClubsProvider).value;
    final sports = ref.watch(userSportsProvider).value;
    final primarySport =
        sports?.where((item) => item.isPrimary).firstOrNull?.sport;
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    final actions = [
      _QuickActionData(
        icon: Icons.manage_accounts_outlined,
        title: '프로필 수정',
        subtitle: primarySport == null
            ? '종목과 내 정보 등록'
            : '${sportLabelFromString(primarySport)} · 내 정보',
        onTap: () => context.push('/onboarding'),
      ),
      _QuickActionData(
        icon: Icons.favorite_border_rounded,
        title: '관심 대회',
        subtitle: favorites == null ? '불러오는 중' : '${favorites.length}개 저장',
        onTap: () => context.push('/favorites'),
      ),
      _QuickActionData(
        icon: Icons.groups_2_outlined,
        title: '내 클럽',
        subtitle: clubs == null ? '불러오는 중' : '${clubs.length}개 가입',
        onTap: () => context.push('/clubs'),
      ),
      _QuickActionData(
        icon: Icons.menu_book_outlined,
        title: '룰북',
        subtitle: primarySport == null
            ? '종목별 규칙 확인'
            : '${sportLabelFromString(primarySport)} 규칙',
        onTap: () => context.push(
          primarySport == null ? '/rules' : '/rules?sport=$primarySport',
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'MY 바로가기'),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final singleColumn = constraints.maxWidth < 340 || textScale > 1.5;
            final itemWidth = singleColumn
                ? constraints.maxWidth
                : (constraints.maxWidth - AppSpacing.sm) / 2;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: itemWidth,
                    child: _ProfileQuickAction(action: action),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _QuickActionData {
  const _QuickActionData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _ProfileQuickAction extends StatelessWidget {
  const _ProfileQuickAction({required this.action});

  final _QuickActionData action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AppCard(
      onTap: action.onTap,
      variant: AppCardVariant.filled,
      backgroundColor: cs.surfaceContainerLow,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: AppSizes.touchTarget,
            height: AppSizes.touchTarget,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: AppRadius.hero,
            ),
            alignment: Alignment.center,
            child: Icon(action.icon, color: cs.primary, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                Text(
                  action.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: cs.onSurfaceVariant,
            size: 20,
          ),
        ],
      ),
    );
  }
}
