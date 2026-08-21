import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';

enum TournamentSection { overview, rankings, rules }

/// 대회 메뉴 안의 2차 내비게이션.
///
/// 전역 하단 내비게이션은 핵심 영역만 담고, 랭킹과 룰북은
/// 대회 문맥 안에서 짧은 탭 띠로 전환한다.
class TournamentSectionBar extends StatelessWidget
    implements PreferredSizeWidget {
  const TournamentSectionBar({
    super.key,
    required this.selected,
    this.showRankings = true,
  });

  final TournamentSection selected;
  final bool showRankings;

  @override
  Size get preferredSize => const Size.fromHeight(AppSizes.control);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final entries = [
      (section: TournamentSection.overview, label: '대회', route: '/'),
      if (showRankings)
        (section: TournamentSection.rankings, label: '랭킹', route: '/rankings'),
      (section: TournamentSection.rules, label: '룰북', route: '/rules'),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: SizedBox(
        height: AppSizes.control,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in entries)
              Expanded(
                child: Semantics(
                  selected: selected == entry.section,
                  button: true,
                  label: '대회 메뉴 ${entry.label}',
                  child: ExcludeSemantics(
                    child: InkWell(
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        context.go(entry.route);
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            entry.label,
                            style: tt.labelLarge?.copyWith(
                              color: selected == entry.section
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                              fontWeight: selected == entry.section
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: AppSpacing.md,
                            right: AppSpacing.md,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              curve: Curves.easeOut,
                              height: 2,
                              color: selected == entry.section
                                  ? cs.primary
                                  : Colors.transparent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
