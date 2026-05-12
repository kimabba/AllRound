import 'package:flutter/material.dart';

import '../../models/speed_measurement.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_card.dart';

class SpeedResultScreen extends StatelessWidget {
  final SpeedResult result;
  const SpeedResultScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('속도 측정 결과')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Big Number — 최고 속도
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primary, cs.primaryContainer],
                ),
                borderRadius: AppRadius.hero,
              ),
              child: Column(
                children: [
                  Text(
                    '최고 속도',
                    style: tt.labelLarge?.copyWith(
                      color: cs.onPrimary.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        result.peakSpeedKmh.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimary,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'km/h',
                        style: tt.titleLarge?.copyWith(color: cs.onPrimary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // 통계 카드
            AppCard(
              child: Column(
                children: [
                  _StatRow(
                    icon: Icons.speed_rounded,
                    label: '평균 속도',
                    value: '${result.avgSpeedKmh.toStringAsFixed(1)} km/h',
                  ),
                  Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                  _StatRow(
                    icon: Icons.videocam_rounded,
                    label: '촬영 프레임레이트',
                    value: '${result.fps.toStringAsFixed(0)} fps',
                  ),
                  Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                  _StatRow(
                    icon: Icons.sports_tennis_rounded,
                    label: '감지된 프레임',
                    value: '${result.detectedFrames} / ${result.totalFrames}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // 궤적 시각화
            if (result.trajectory.isNotEmpty) ...[
              Text(
                '공 궤적',
                style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                padding: EdgeInsets.zero,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: AppRadius.card,
                    child: CustomPaint(
                      painter: _TrajectoryPainter(
                        trajectory: result.trajectory,
                        peakSpeed: result.peakSpeedKmh,
                        primaryColor: cs.primary,
                        secondaryColor: cs.secondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),
            AppCard(
              variant: AppCardVariant.outlined,
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'MVP 버전 정확도: ±15~30% (레이더건 대비). '
                      '측면 카메라 각도·240fps 영상 권장.',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(label, style: tt.bodyMedium),
          ),
          Text(
            value,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _TrajectoryPainter extends CustomPainter {
  final List<TrajectoryPoint> trajectory;
  final double peakSpeed;
  final Color primaryColor;
  final Color secondaryColor;

  const _TrajectoryPainter({
    required this.trajectory,
    required this.peakSpeed,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trajectory.length < 2) return;

    // 좌표 정규화
    final xs = trajectory.map((p) => p.realX).toList();
    final ys = trajectory.map((p) => p.realY).toList();
    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);

    final rangeX = (maxX - minX).abs().clamp(0.1, double.infinity);
    final rangeY = (maxY - minY).abs().clamp(0.1, double.infinity);
    final pad = 20.0;

    Offset toScreen(TrajectoryPoint p) => Offset(
          pad + (p.realX - minX) / rangeX * (size.width - pad * 2),
          pad + (p.realY - minY) / rangeY * (size.height - pad * 2),
        );

    // 배경
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF1A1A2E),
    );

    // 궤적 선 (속도에 따른 색상 그라디언트)
    for (var i = 1; i < trajectory.length; i++) {
      final prev = toScreen(trajectory[i - 1]);
      final cur = toScreen(trajectory[i]);
      final speedRatio =
          peakSpeed > 0 ? (trajectory[i].speedKmh / peakSpeed).clamp(0.0, 1.0) : 0.0;

      final paint = Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(
          secondaryColor.withValues(alpha: 0.5),
          primaryColor,
          speedRatio,
        )!;
      canvas.drawLine(prev, cur, paint);
    }

    // 점 (속도 레이블 포함)
    for (var i = 0; i < trajectory.length; i++) {
      final pt = trajectory[i];
      final sc = toScreen(pt);
      canvas.drawCircle(sc, 5, Paint()..color = primaryColor);

      if (pt.speedKmh > 0 && i % 5 == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: pt.speedKmh.toStringAsFixed(0),
            style: const TextStyle(color: Colors.white, fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, sc.translate(6, -tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_TrajectoryPainter old) => false;
}
