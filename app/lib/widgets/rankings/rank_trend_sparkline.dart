import 'package:flutter/material.dart';

import '../../models/org_ranking_snapshot.dart';

/// 순위 추이를 선 하나로 보여주는 가벼운 스파크라인. 점 2개 미만이면
/// 그래프 대신 안내 문구를 보여준다 — 빈 그래프를 그리지 않는다.
class RankTrendSparkline extends StatelessWidget {
  const RankTrendSparkline({super.key, required this.snapshots});

  final List<OrgRankingSnapshot> snapshots;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (snapshots.length < 2) {
      return Text(
        '추이를 보려면 며칠 더 필요해요',
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      );
    }

    return SizedBox(
      height: 80,
      width: double.infinity,
      child: CustomPaint(
        painter: _RankTrendPainter(snapshots: snapshots, lineColor: cs.primary),
      ),
    );
  }
}

class _RankTrendPainter extends CustomPainter {
  _RankTrendPainter({required this.snapshots, required this.lineColor});

  final List<OrgRankingSnapshot> snapshots;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final ranks = snapshots.map((s) => s.rank).toList();
    final minRank = ranks.reduce((a, b) => a < b ? a : b);
    final maxRank = ranks.reduce((a, b) => a > b ? a : b);
    final range = maxRank - minRank;

    final path = Path();
    for (var i = 0; i < snapshots.length; i++) {
      final x = size.width * i / (snapshots.length - 1);
      // 낮을수록(1등에 가까울수록) 그래프 위쪽 — y 축 반전.
      final t = range == 0 ? 0.5 : (snapshots[i].rank - minRank) / range;
      final y = t * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RankTrendPainter oldDelegate) =>
      oldDelegate.snapshots != snapshots || oldDelegate.lineColor != lineColor;
}
