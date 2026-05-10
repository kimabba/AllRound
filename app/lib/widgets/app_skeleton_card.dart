import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// `skeletonizer` 래퍼.
/// `loading=true`일 때 자식 위젯을 자동으로 회색 shimmer 로 표시.
class AppSkeletonCard extends StatelessWidget {
  final bool loading;
  final Widget child;

  const AppSkeletonCard({
    super.key,
    required this.loading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Skeletonizer(
      enabled: loading,
      effect: ShimmerEffect(
        baseColor: cs.surfaceContainerHigh,
        highlightColor: cs.surfaceContainerHighest,
      ),
      child: child,
    );
  }
}
