import 'package:flutter/material.dart';

import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';

/// 볼보이 원이 냅 상단 경계선 위로 떠오르는 높이.
/// 냅 전체 높이에 포함시켜 돌출부까지 hit-test 되게 한다(보이는 곳 = 눌리는 곳).
const double bottomNavDialProtrusion = 14;
const double _dialSlotWidth = AppSizes.touchTarget + 16;

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;

  /// 가운데 볼보이 버튼 탭 콜백. null이면 버튼 숨김(스피드건 등 채팅 미지원 화면).
  final VoidCallback? onChatTap;

  /// 볼보이 버튼 접근성 hint (예: '대회 화면에서 채팅 열기').
  final String? chatHint;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    this.onChatTap,
    this.chatHint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const labels = ['오늘', '대회', '클럽', 'MY'];
    const keys = [
      AllRoundE2EKeys.navToday,
      AllRoundE2EKeys.navTournaments,
      AllRoundE2EKeys.navClubs,
      AllRoundE2EKeys.navProfile,
    ];

    Widget tab(int index) {
      return Expanded(
        child: SizedBox(
          height: AppSizes.bottomNavigation,
          child: Semantics(
            key: keys[index],
            selected: currentIndex == index,
            button: true,
            label: '${labels[index]} 탭',
            onTap: () => onChanged(index),
            child: ExcludeSemantics(
              child: InkWell(
                onTap: () => onChanged(index),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 7,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        width: currentIndex == index ? 20 : 0,
                        height: 2,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        labels[index],
                        style: tt.labelSmall?.copyWith(
                          color: currentIndex == index
                              ? cs.onSurface
                              : cs.onSurfaceVariant,
                          fontWeight: currentIndex == index
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final bar = DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.98),
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppSizes.bottomNavigation,
          child: Row(
            children: [
              tab(0),
              tab(1),
              // 가운데 자리는 오버레이 버튼이 차지 — 폭만 비워둔다.
              if (onChatTap != null) const SizedBox(width: _dialSlotWidth),
              tab(2),
              tab(3),
            ],
          ),
        ),
      ),
    );

    if (onChatTap == null) return bar;

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: bottomNavDialProtrusion),
          child: bar,
        ),
        _ChatDialButton(onTap: onChatTap!, hint: chatHint),
      ],
    );
  }
}

/// 냅 중앙의 원형 볼보이 진입 버튼 — 메인 기능 강조.
/// ponytail: 실제 회전 다이얼 대신 눌림 스케일만. 반응 좋으면 모션 확장.
class _ChatDialButton extends StatefulWidget {
  const _ChatDialButton({required this.onTap, this.hint});

  final VoidCallback onTap;
  final String? hint;

  @override
  State<_ChatDialButton> createState() => _ChatDialButtonState();
}

class _ChatDialButtonState extends State<_ChatDialButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: _dialSlotWidth,
      height: bottomNavDialProtrusion + AppSizes.bottomNavigation,
      child: Semantics(
        key: AllRoundE2EKeys.globalChatDock,
        button: true,
        label: 'BB',
        hint: widget.hint,
        onTap: widget.onTap,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) {
              setState(() => _pressed = false);
              widget.onTap();
            },
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                AnimatedScale(
                  scale: _pressed ? 0.9 : 1,
                  duration: const Duration(milliseconds: 110),
                  curve: Curves.easeOut,
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.surface, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.45),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 24,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 9,
                  child: Text(
                    'BB',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
