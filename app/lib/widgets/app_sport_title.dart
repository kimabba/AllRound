import 'package:flutter/material.dart';

import '../utils/grade_labels.dart';

/// AppBar title that also switches the active sport.
class AppSportTitle extends StatelessWidget {
  const AppSportTitle({
    super.key,
    required this.sport,
    required this.onSelected,
  });

  final String sport;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: sport,
      onSelected: onSelected,
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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
        ],
      ),
    );
  }
}
