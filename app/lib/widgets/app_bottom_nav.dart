import 'package:flutter/material.dart';

import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';

/// 볼보이 원이 탭바 위에 떠 있는 영역의 높이(원 + 라벨).
/// 탭이 3개(짝수가 아님)라 다이얼을 탭바 안에 넣으면 가운데 탭 라벨을 덮는다.
/// → 탭바 위로 완전히 띄우고, 그 높이를 냅 전체 높이에 포함시켜 hit-test 되게 한다.
/// 원(54) + 간격(2) + 라벨 1줄. 라벨은 아래에서 배율을 1.3배로 제한하므로
/// 최대 높이가 정해진다(11px × 1.3 × 줄높이 ≈ 20). 넘치면 RenderFlex overflow 로
/// 디자인 계약 테스트가 잡는다 — 값을 줄일 때는 그 테스트를 함께 볼 것.
const double bottomNavDialProtrusion = 80;
const double _dialDiameter = 54;
const double _dialSlotWidth = AppSizes.touchTarget + 16;

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;

  /// 가운데 볼보이 버튼 탭 콜백. null이면 버튼 숨김(채팅 미지원 화면).
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
    const labels = ['일정', '클럽', '룰북'];
    const keys = [
      AllRoundE2EKeys.navToday,
      AllRoundE2EKeys.navClubs,
      AllRoundE2EKeys.navRules,
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
          child: Row(children: [tab(0), tab(1), tab(2)]),
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

  /// 라벨 정본. 챗 화면 카피("여러분의 도우미 볼보이(BB)")와 같은 이름을 쓴다.
  /// `BB` 두 글자는 누르기 전에는 뜻을 알 수 없어 탭바 라벨로 부적합하다.
  static const label = '볼보이';

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
      height: bottomNavDialProtrusion,
      child: Semantics(
        key: AllRoundE2EKeys.globalChatDock,
        button: true,
        label: _ChatDialButton.label,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: _pressed ? 0.9 : 1,
                  duration: const Duration(milliseconds: 110),
                  curve: Curves.easeOut,
                  child: Container(
                    width: _dialDiameter,
                    height: _dialDiameter,
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
                const SizedBox(height: 2),
                // 냅은 높이가 고정된 영역이라 라벨 배율을 제한한다. 원형 버튼의
                // Semantics label('볼보이')은 배율과 무관하므로 낭독에는 영향 없다.
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Text(
                    _ChatDialButton.label,
                    maxLines: 1,
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
