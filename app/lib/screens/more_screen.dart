import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/allround_logo.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    final cs = Theme.of(context).colorScheme;

    final personalItems = [
      _MenuItem(
        icon: Icons.person_rounded,
        label: 'MY',
        subtitle: '프로필, 내 클럽, 대회 기록 확인',
        color: const Color(0xFF2563EB),
        onTap: () => context.go('/profile'),
      ),
      _MenuItem(
        icon: Icons.tune_rounded,
        label: '맞춤 설정',
        subtitle: '활동 지역, 종목, 등급 수정',
        color: AppSportColors.futsal,
        onTap: () => context.push('/onboarding'),
      ),
      _MenuItem(
        icon: Icons.calendar_month_rounded,
        label: '친구 일정',
        subtitle: '내 일정과 참여 기록 확인',
        color: const Color(0xFF7C3AED),
        onTap: () => context.go('/friend-schedule'),
      ),
      _MenuItem(
        icon: Icons.bookmark_rounded,
        label: '관심',
        subtitle: '관심 대회와 클럽 모아보기',
        color: const Color(0xFFF59E0B),
        onTap: () => context.go('/favorites'),
      ),
    ];

    final serviceItems = [
      _MenuItem(
        icon: Icons.menu_book_rounded,
        label: '룰북',
        subtitle: '테니스와 풋살 규칙 확인',
        color: AppSportColors.tennis,
        onTap: () => context.go('/rules'),
      ),
      if (!kIsWeb)
        _MenuItem(
          icon: Icons.speed_rounded,
          label: '스피드건',
          subtitle: '공 속도 측정',
          color: const Color(0xFFEF4444),
          onTap: () => context.go('/speed-gun'),
        ),
      if (kIsWeb && isAdmin)
        _MenuItem(
          icon: Icons.admin_panel_settings_rounded,
          label: '어드민',
          subtitle: '관리자 메뉴',
          color: const Color(0xFF64748B),
          onTap: () => context.go('/admin'),
        ),
    ];

    final legalItems = [
      _MenuItem(
        icon: Icons.description_outlined,
        label: '이용약관',
        subtitle: '서비스 이용 조건',
        color: cs.onSurfaceVariant,
        onTap: () => launchUrl(
          Uri.parse(
            'https://bsjdgwmveokanclqwtvx.supabase.co/storage/v1/object/public/legal/terms-of-service.html',
          ),
          mode: LaunchMode.externalApplication,
        ),
      ),
      _MenuItem(
        icon: Icons.privacy_tip_outlined,
        label: '개인정보 처리방침',
        subtitle: '개인정보 수집 및 이용 안내',
        color: cs.onSurfaceVariant,
        onTap: () => launchUrl(
          Uri.parse(
            'https://bsjdgwmveokanclqwtvx.supabase.co/storage/v1/object/public/legal/privacy-policy.html',
          ),
          mode: LaunchMode.externalApplication,
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const BrandedAppBarTitle(title: '더보기')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.huge,
        ),
        children: [
          _MenuSection(
            title: '내 메뉴',
            description: '내 정보와 설정값으로 움직이는 메뉴',
            items: personalItems,
          ),
          const SizedBox(height: AppSpacing.xxl),
          _MenuSection(
            title: '서비스',
            description: '전체 사용자가 함께 볼 수 있는 메뉴',
            items: serviceItems,
          ),
          const SizedBox(height: AppSpacing.xxl),
          _LegalSection(items: legalItems),
        ],
      ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  final String title;
  final String description;
  final List<_MenuItem> items;

  const _MenuSection({
    required this.title,
    required this.description,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          description,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _MenuRow(item: items[i]),
                if (i < items.length - 1)
                  Divider(
                    height: 1,
                    indent: 74,
                    endIndent: AppSpacing.lg,
                    color: cs.outlineVariant.withValues(alpha: 0.55),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final _MenuItem item;

  const _MenuRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(item.icon, color: item.color, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  final List<_MenuItem> items;

  const _LegalSection({required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              ListTile(
                onTap: items[i].onTap,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                title: Text(
                  items[i].label,
                  style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                trailing: Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (i < items.length - 1)
                Divider(
                  height: 1,
                  indent: AppSpacing.lg,
                  endIndent: AppSpacing.lg,
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}
