import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/session_security.dart';
import '../../state/providers.dart';
import '../../state/theme_provider.dart';
import '../../testing/e2e_keys.dart';
import '../../theme/tokens.dart';

class ProfileServiceSection extends StatelessWidget {
  const ProfileServiceSection({super.key, required this.onRulesTap});

  final VoidCallback onRulesTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '도움말'),
        const SizedBox(height: AppSpacing.sm),
        const Divider(height: 1),
        ActionRow(
          icon: Icons.menu_book_outlined,
          label: '룰북',
          subtitle: '테니스와 풋살 규칙 확인',
          onTap: onRulesTap,
        ),
        const Divider(height: 1),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 화면 설정 섹션 (다크모드 토글)
// ────────────────────────────────────────────────────────────

class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final mode = ref.watch(themeModeProvider);

    return Column(
      key: AllRoundE2EKeys.profileAppearanceSection,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '화면 설정'),
        const SizedBox(height: AppSpacing.sm),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
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
        const Divider(height: 1),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 계정 섹션 (알림 + 로그아웃)
// ────────────────────────────────────────────────────────────

class AccountSection extends StatelessWidget {
  final WidgetRef ref;
  final int unreadNotificationCount;
  final bool tournamentNotificationsEnabled;
  final bool clubNotificationsEnabled;
  final bool coachNotificationsEnabled;
  final VoidCallback onNotificationInboxTap;
  final VoidCallback onNotificationTap;

  const AccountSection({
    super.key,
    required this.ref,
    required this.unreadNotificationCount,
    required this.tournamentNotificationsEnabled,
    required this.clubNotificationsEnabled,
    required this.coachNotificationsEnabled,
    required this.onNotificationInboxTap,
    required this.onNotificationTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeCount = [
      tournamentNotificationsEnabled,
      clubNotificationsEnabled,
      coachNotificationsEnabled,
    ].where((enabled) => enabled).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '계정'),
        const SizedBox(height: AppSpacing.sm),
        Divider(height: 1, color: cs.outlineVariant),
        Column(
          children: [
            ActionRow(
              icon: Icons.notifications_active_outlined,
              label: '알림함',
              subtitle: unreadNotificationCount == 0
                  ? '새 알림 없음'
                  : '읽지 않은 알림 $unreadNotificationCount개',
              onTap: onNotificationInboxTap,
            ),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
            ActionRow(
              icon: Icons.notifications_outlined,
              label: '알림 설정',
              subtitle: activeCount == 0 ? '모든 알림 꺼짐' : '$activeCount개 알림 켜짐',
              onTap: onNotificationTap,
            ),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
            ActionRow(
              icon: Icons.logout_rounded,
              label: '로그아웃',
              accentColor: cs.error,
              onTap: () async {
                // 서버 세션·리프레시 토큰까지 폐기 (JY-113 세션 잔존 버그).
                await signOutSecurely(ref.read(supabaseProvider));
              },
            ),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
            ActionRow(
              icon: Icons.person_remove_outlined,
              label: '회원 탈퇴',
              accentColor: cs.error,
              onTap: () => _confirmDeleteAccount(context, ref),
            ),
          ],
        ),
        Divider(height: 1, color: cs.outlineVariant),
      ],
    );
  }
}

/// 회원 탈퇴 확인 → delete-account 호출 → 로그아웃(→ 로그인 화면 라우팅).
Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text(
          '탈퇴하면 계정과 개인정보가 삭제되며 되돌릴 수 없습니다.\n'
          '작성한 글·댓글은 "탈퇴한 사용자"로 익명 처리되어 남을 수 있습니다.\n\n'
          '정말 탈퇴하시겠어요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('탈퇴', style: TextStyle(color: cs.error)),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return;

  try {
    await ref.read(apiProvider).deleteAccount();
    // 완료 안내 후 로그아웃(→ 로그인 화면). signOut 하면 화면이 전환되므로
    // 안내는 signOut 전에 보여준다.
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('탈퇴 완료'),
          content: const Text('회원 탈퇴가 완료되었습니다.\n그동안 이용해 주셔서 감사합니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    }
    await signOutSecurely(ref.read(supabaseProvider));
    // signOut 이 authState 변경 → 앱이 로그인 화면으로 라우팅.
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('탈퇴에 실패했습니다. 잠시 후 다시 시도해주세요.')),
    );
  }
}

class ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? accentColor;
  final VoidCallback? onTap;

  const ActionRow({
    super.key,
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.listRow),
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
                      Text(label, style: tt.bodyLarge?.copyWith(color: color)),
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
      ),
    );
  }
}

class NotificationSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const NotificationSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: value
                  ? cs.primaryContainer
                  : cs.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: value ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class SheetActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? accentColor;
  final VoidCallback onTap;

  const SheetActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor,
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
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: AppSpacing.md),
              Text(
                label,
                style: tt.bodyLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
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
// 공통 헬퍼 위젯
// ────────────────────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;

  const SectionHeader({super.key, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(title, style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
        if (action != null) ...[const Spacer(), action!],
      ],
    );
  }
}

class SectionActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const SectionActionButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Text(label, style: tt.labelMedium?.copyWith(color: cs.primary)),
    );
  }
}
