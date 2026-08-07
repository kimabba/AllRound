import 'package:flutter/material.dart';

import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';

/// 메인 하단 메뉴. 최종 사용자 동선은 대회·클럽·볼보이·MY 네 가지다.
/// 룰북은 대회 화면 안에서 열고, 볼보이는 현재 화면의 대화를 시트로 이어간다.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;

  /// 맨 앞 볼보이 탭 콜백. null이면 볼보이 탭 숨김(채팅 미지원 화면).
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
    const labels = ['대회', '클럽', 'MY'];
    const icons = [
      Icons.emoji_events_outlined,
      Icons.groups_outlined,
      Icons.person_outline_rounded,
    ];
    const selectedIcons = [
      Icons.emoji_events_rounded,
      Icons.groups_rounded,
      Icons.person_rounded,
    ];
    const keys = [
      AllRoundE2EKeys.navToday,
      AllRoundE2EKeys.navClubs,
      AllRoundE2EKeys.navProfile,
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    width: 42,
                    height: 30,
                    decoration: BoxDecoration(
                      color: currentIndex == index
                          ? cs.primaryContainer
                          : Colors.transparent,
                      borderRadius: AppRadius.pill,
                    ),
                    child: Icon(
                      currentIndex == index
                          ? selectedIcons[index]
                          : icons[index],
                      size: 23,
                      color: currentIndex == index
                          ? cs.primary
                          : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
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
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 볼보이는 가운데 고정한다. 탭 인덱스를 점유하지 않고 현재 화면 위에
    // 대화 시트를 열어 사용자가 다른 화면으로 이동해도 대화를 이어간다.
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
                  Container(
                    width: 42,
                    height: 30,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: AppRadius.pill,
                    ),
                    child: Icon(
                      Icons.chat_bubble_rounded,
                      size: 21,
                      color: cs.onPrimary,
                    ),
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
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
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
                tab(2),
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
