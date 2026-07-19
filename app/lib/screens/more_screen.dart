import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/providers.dart';
import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;

    final personalItems = [
      _MenuItem(
        icon: Icons.person_rounded,
        label: 'MY',
        subtitle: '프로필, 종목 설정, 내 클럽, 대회 기록',
        onTap: () => context.push('/profile'),
      ),
      _MenuItem(
        icon: Icons.bookmark_rounded,
        label: '관심',
        subtitle: '관심 대회와 클럽 모아보기',
        onTap: () => context.push('/favorites'),
      ),
      _MenuItem(
        icon: Icons.person_off_rounded,
        label: '차단 관리',
        subtitle: '차단한 사용자 확인과 해제',
        onTap: () => context.push('/blocked-users'),
      ),
    ];

    final serviceItems = [
      _MenuItem(
        icon: Icons.menu_book_rounded,
        label: '룰북',
        subtitle: '테니스와 풋살 규칙 확인',
        onTap: () => context.push('/rules'),
      ),
      if (kIsWeb && isAdmin)
        _MenuItem(
          icon: Icons.admin_panel_settings_rounded,
          label: '어드민',
          subtitle: '관리자 메뉴',
          onTap: () => context.go('/admin'),
        ),
    ];

    final legalItems = [
      _MenuItem(
        icon: Icons.description_outlined,
        label: '이용약관',
        subtitle: '서비스 이용 조건',
        onTap: () => launchUrl(
          Uri.parse(
            'https://kimabba.github.io/AllRound/legal/terms-of-service.html',
          ),
          mode: LaunchMode.externalApplication,
        ),
      ),
      _MenuItem(
        icon: Icons.privacy_tip_outlined,
        label: '개인정보 처리방침',
        subtitle: '개인정보 수집 및 이용 안내',
        onTap: () => launchUrl(
          Uri.parse(
            'https://kimabba.github.io/AllRound/legal/privacy-policy.html',
          ),
          mode: LaunchMode.externalApplication,
        ),
      ),
    ];

    return Scaffold(
      key: AllRoundE2EKeys.moreScreen,
      appBar: AppBar(title: const Text('전체 메뉴')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
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
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          description,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        Divider(height: 1, color: cs.outlineVariant),
        Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              _MenuRow(item: items[i]),
              if (i < items.length - 1)
                Divider(
                  height: 1,
                  indent: 52,
                  color: cs.outlineVariant,
                ),
            ],
          ],
        ),
        Divider(height: 1, color: cs.outlineVariant),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Icon(
                  item.icon,
                  color: cs.onSurfaceVariant,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
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

    return Column(
      children: [
        Divider(height: 1, color: cs.outlineVariant),
        for (var i = 0; i < items.length; i++) ...[
          ListTile(
            onTap: items[i].onTap,
            contentPadding: EdgeInsets.zero,
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
              color: cs.outlineVariant,
            ),
        ],
        Divider(height: 1, color: cs.outlineVariant),
      ],
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
