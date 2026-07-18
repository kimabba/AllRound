import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const labels = ['오늘', '대회', '클럽', '코치', 'MY'];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.98),
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var index = 0; index < labels.length; index++)
                Expanded(
                  child: Semantics(
                    selected: currentIndex == index,
                    button: true,
                    label: '${labels[index]} 탭',
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
                                borderRadius: BorderRadius.circular(
                                  AppRadius.xs,
                                ),
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
            ],
          ),
        ),
      ),
    );
  }
}
