import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../utils/grade_labels.dart';

/// AppBar 타이틀 겸 종목 전환 버튼. 화살표가 있어야 눌리는 줄 안다.
///
/// 홈과 클럽이 같은 자리에서 같은 기준(activeSportProvider)을 보고 바꾼다 —
/// 화면마다 종목 스위치가 따로 있으면 지금 어느 종목을 보고 있는지 어긋난다.
class SportTitle extends ConsumerWidget {
  const SportTitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sport = ref.watch(activeSportProvider) ?? 'futsal';
    return PopupMenuButton<String>(
      initialValue: sport,
      onSelected: (value) =>
          ref.read(sportOverrideProvider.notifier).select(value),
      tooltip: '종목 바꾸기',
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'tennis',
          child: Text(sportLabel(Sport.tennis)),
        ),
        PopupMenuItem(
          value: 'futsal',
          child: Text(sportLabel(Sport.futsal)),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '올라운드 ${sportLabelFromString(sport)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
        ],
      ),
    );
  }
}
