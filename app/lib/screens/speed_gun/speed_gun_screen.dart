import 'package:flutter/material.dart';

import '../../models/speed_measurement.dart';
import '../../services/ball_detector_service.dart';
import '../../services/speed_calculator.dart';
import '../../services/video_processing_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_card.dart';
import '../../widgets/notification_bell_action.dart';
import 'court_calibration_screen.dart';
import 'speed_result_screen.dart';

enum _Step { idle, picked, calibrated, detecting, done }

class SpeedGunScreen extends StatefulWidget {
  const SpeedGunScreen({super.key});

  @override
  State<SpeedGunScreen> createState() => _SpeedGunScreenState();
}

class _SpeedGunScreenState extends State<SpeedGunScreen> {
  final _videoSvc = VideoProcessingService();
  final _detector = BallDetectorService();

  VideoMeta? _meta;
  CourtCalibration? _calibration;
  SpeedResult? _result;
  _Step _step = _Step.idle;
  int _detectProgress = 0;
  int _detectTotal = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detector.initialize();
  }

  @override
  void dispose() {
    _detector.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    setState(() {
      _error = null;
      _step = _Step.idle;
      _meta = null;
      _calibration = null;
      _result = null;
    });
    try {
      final meta = await _videoSvc.pickVideo();
      if (meta == null || !mounted) return;
      setState(() {
        _meta = meta;
        _step = _Step.picked;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _calibrate() async {
    if (_meta == null) return;
    try {
      final firstFrame = await _videoSvc.extractFirstFrame(_meta!);
      if (!mounted) return;
      final result = await Navigator.of(context).push<CourtCalibration>(
        MaterialPageRoute(
          builder: (_) => CourtCalibrationScreen(firstFramePath: firstFrame),
        ),
      );
      if (result == null || !mounted) return;
      setState(() {
        _calibration = result;
        _step = _Step.calibrated;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _analyze() async {
    if (_meta == null || _calibration == null) return;
    setState(() {
      _step = _Step.detecting;
      _detectProgress = 0;
      _detectTotal = _meta!.estimatedFrameCount;
      _error = null;
    });

    try {
      // 최대 300프레임 (5초 × 60fps 기준)
      final frames = await _videoSvc.extractFrames(
        _meta!,
        maxFrames: 300,
      );
      if (!mounted) return;

      setState(() => _detectTotal = frames.length);

      final detections = await _detector.detectFrames(
        frames,
        onProgress: (cur, total) {
          if (mounted) setState(() => _detectProgress = cur);
        },
      );

      if (!mounted) return;

      final result = SpeedCalculator.calculate(
        detections: detections,
        calibration: _calibration!,
        fps: _meta!.fps,
        totalFrames: frames.length,
      );

      await _videoSvc.cleanup();

      if (!mounted) return;
      setState(() {
        _result = result;
        _step = _Step.done;
      });
    } catch (e) {
      setState(() => _error = e.toString());
      await _videoSvc.cleanup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('스피드건'),
        actions: const [NotificationBellAction()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 설명
            AppCard(
              variant: AppCardVariant.outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.speed_rounded, color: cs.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Text('비디오 속도 분석', style: tt.titleMedium),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '240fps 영상을 선택하면 공의 속도를 자동으로 측정합니다.\n'
                    '측면 촬영 · 코트 전체가 보이는 앵글 권장',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Step 1 — 비디오 선택
            _StepCard(
              number: 1,
              title: '비디오 선택',
              done: _meta != null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_meta != null) ...[
                    _InfoChip(
                      icon: Icons.videocam_rounded,
                      label:
                          '${_meta!.fps.toStringAsFixed(0)}fps · ${(_meta!.durationMs / 1000).toStringAsFixed(1)}초 · ${_meta!.width}×${_meta!.height}',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  AppSecondaryButton(
                    label: _meta == null ? '갤러리에서 선택' : '다른 비디오 선택',
                    icon: Icons.video_library_rounded,
                    onPressed: _pickVideo,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Step 2 — 코트 캘리브레이션
            _StepCard(
              number: 2,
              title: '코트 코너 지정',
              done: _calibration != null,
              disabled: _meta == null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '첫 프레임에서 코트 4개 코너를 순서대로 탭해 속도 계산 기준을 잡습니다.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppPrimaryButton(
                    label: _calibration == null ? '코트 코너 지정' : '다시 지정',
                    icon: Icons.grid_on_rounded,
                    onPressed: _meta == null ? null : _calibrate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Step 3 — 분석
            _StepCard(
              number: 3,
              title: '속도 분석',
              done: _step == _Step.done,
              disabled: _calibration == null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_step == _Step.detecting) ...[
                    Text(
                      '공 감지 중... $_detectProgress / $_detectTotal 프레임',
                      style: tt.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    LinearProgressIndicator(
                      value: _detectTotal > 0
                          ? _detectProgress / _detectTotal
                          : null,
                      color: cs.primary,
                      backgroundColor: cs.surfaceContainerHigh,
                    ),
                  ] else ...[
                    AppPrimaryButton(
                      label: '분석 시작',
                      icon: Icons.play_arrow_rounded,
                      onPressed: _calibration == null ? null : _analyze,
                    ),
                  ],
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                variant: AppCardVariant.outlined,
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: cs.error, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _error!,
                        style: tt.bodySmall?.copyWith(color: cs.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 결과 바로가기 버튼
            if (_step == _Step.done && _result != null) ...[
              const SizedBox(height: AppSpacing.xl),
              AppPrimaryButton(
                label: '결과 보기',
                icon: Icons.bar_chart_rounded,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SpeedResultScreen(result: _result!),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 보조 위젯
// ────────────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  final int number;
  final String title;
  final Widget child;
  final bool done;
  final bool disabled;

  const _StepCard({
    required this.number,
    required this.title,
    required this.child,
    this.done = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final badgeColor = done
        ? cs.primary
        : disabled
            ? cs.surfaceContainerHigh
            : cs.primaryContainer;
    final badgeFg = done
        ? cs.onPrimary
        : disabled
            ? cs.onSurfaceVariant
            : cs.onPrimaryContainer;

    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: done
                        ? Icon(Icons.check_rounded, size: 16, color: badgeFg)
                        : Text(
                            '$number',
                            style: tt.labelMedium?.copyWith(color: badgeFg),
                          ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(title, style: tt.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: AppRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: tt.labelSmall?.copyWith(color: cs.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}
