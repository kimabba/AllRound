import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/matchup_logo.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    final colorScheme = Theme.of(context).colorScheme;

    final items = [
      _MenuItem(
        icon: Icons.menu_book_outlined,
        label: '룰북',
        subtitle: '종목별 규칙 안내',
        onTap: () => context.go('/rules'),
      ),
      if (!kIsWeb)
        _MenuItem(
          icon: Icons.speed_rounded,
          label: '스피드건',
          subtitle: '공 속도 측정',
          onTap: () => context.go('/speed-gun'),
        ),
      _MenuItem(
        icon: Icons.person_outline,
        label: 'MY',
        subtitle: '프로필 및 설정',
        onTap: () => context.go('/profile'),
      ),
      _MenuItem(
        icon: Icons.tune_rounded,
        label: '맞춤 설정',
        subtitle: '닉네임, 활동 지역, 종목·등급 수정',
        onTap: () => context.go('/onboarding'),
      ),
      if (isAdmin)
        _MenuItem(
          icon: Icons.admin_panel_settings_outlined,
          label: '어드민',
          subtitle: '관리자 메뉴',
          onTap: () => context.go('/admin'),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const BrandedAppBarTitle(title: '더보기')),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) {
          final item = items[i];
          return AppCard(
            variant: AppCardVariant.elevated,
            borderRadius: BorderRadius.circular(16),
            onTap: item.onTap,
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(item.icon, color: colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        item.subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
}
