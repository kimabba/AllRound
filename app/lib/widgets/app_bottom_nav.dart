import 'package:flutter/material.dart';

import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';

/// 하단 냅. 대회·클럽 탭 뒤 가장 오른쪽에 볼보이를 놓는다.
/// 랭킹과 룰북은 대회 메뉴 안의 2차 탭으로 연다.
/// 볼보이는 탭 인덱스를 점유하지 않고
/// 별도 콜백(onChatTap)으로 현재 화면 맥락의 채팅 시트를 연다.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;

  /// 가장 오른쪽 볼보이 탭 콜백. null이면 볼보이 탭 숨김(채팅 미지원 화면).
  final VoidCallback? onChatTap;

  /// 볼보이 탭 접근성 hint (예: '대회 화면에서 채팅 열기').
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
    const labels = ['대회', '클럽'];
    const keys = [
      AllRoundE2EKeys.navToday,
      AllRoundE2EKeys.navClubs,
    ];

    Widget tab(int index) {
      return Expanded(
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
      );
    }

    // 볼보이 진입 탭 — 메인 기능 강조(아이콘 + primary 라벨). 탭 인덱스를
    // 점유하지 않고 onChatTap 으로 현재 화면 맥락의 채팅을 연다.
    Widget chatTab() {
      return Expanded(
        child: Semantics(
          key: AllRoundE2EKeys.globalChatDock,
          button: true,
          label: _chatLabel,
          hint: chatHint,
          onTap: onChatTap,
          child: ExcludeSemantics(
            child: InkWell(
              onTap: onChatTap,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 22,
                    color: cs.primary,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _chatLabel,
                    maxLines: 1,
                    style: tt.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.98),
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        // 냅은 높이가 고정된 영역이라 라벨 배율을 제한한다. Semantics label 은
        // 배율과 무관하므로 낭독에는 영향 없다.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: SizedBox(
            height: AppSizes.bottomNavigation,
            // 각 슬롯이 냅 전체 높이를 채워 최소 44x44 터치 영역을 지킨다.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tab(0),
                tab(1),
                if (onChatTap != null) chatTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 라벨 정본. 챗 화면 카피("여러분의 도우미 볼보이(BB)")와 같은 이름을 쓴다.
  /// `BB` 두 글자는 누르기 전에는 뜻을 알 수 없어 탭 라벨로 부적합하다.
  static const _chatLabel = '볼보이';
}
