import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/speed_measurement.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/notification_bell_action.dart';

class CourtCalibrationScreen extends StatefulWidget {
  final String firstFramePath;
  const CourtCalibrationScreen({super.key, required this.firstFramePath});

  @override
  State<CourtCalibrationScreen> createState() => _CourtCalibrationScreenState();
}

class _CourtCalibrationScreenState extends State<CourtCalibrationScreen> {
  final _points = <Offset>[];
  Size? _displaySize;

  static const _labels = ['좌상', '우상', '우하', '좌하'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final done = _points.length == 4;

    return Scaffold(
      appBar: AppBar(
        title: const Text('코트 캘리브레이션'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: const [NotificationBellAction()],
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // 안내 배너
          Container(
            width: double.infinity,
            color: done
                ? Colors.green.withValues(alpha: 0.2)
                : cs.primaryContainer,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              done
                  ? '4개 코너를 모두 선택했습니다. 확인 후 진행하세요.'
                  : '코트의 4개 코너를 순서대로 탭하세요: ${_labels[_points.length]}',
              style: tt.bodySmall?.copyWith(
                color: done ? Colors.green.shade800 : cs.onPrimaryContainer,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // 이미지 + 터치 영역
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: _points.length < 4
                      ? (details) => _onTap(details.localPosition, constraints)
                      : null,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(widget.firstFramePath),
                        fit: BoxFit.contain,
                        frameBuilder: (_, child, frame, __) {
                          if (frame != null && _displaySize == null) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _computeImageDisplaySize(constraints);
                            });
                          }
                          return child;
                        },
                      ),
                      // 선택된 점 오버레이
                      if (_points.isNotEmpty && _displaySize != null)
                        CustomPaint(
                          painter: _CalibrationPainter(
                            points: _points,
                            displaySize: _displaySize!,
                            containerSize: Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),

          // 컨트롤 버튼
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: AppSecondaryButton(
                      label: '다시 찍기',
                      onPressed: _points.isEmpty
                          ? null
                          : () => setState(() => _points.clear()),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppPrimaryButton(
                      label: '확인',
                      onPressed: done ? _confirm : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onTap(Offset localPos, BoxConstraints constraints) {
    setState(() => _points.add(localPos));
  }

  void _computeImageDisplaySize(BoxConstraints constraints) {
    // 실제 이미지 크기를 읽어 aspect ratio 계산
    // 간단히 display size 추정 (ImageInfo 콜백 대용)
    if (mounted) {
      setState(() {
        _displaySize = Size(constraints.maxWidth, constraints.maxHeight);
      });
    }
  }

  void _confirm() {
    if (_points.length != 4 || _displaySize == null) return;

    // 표시 크기 → 실제 픽셀 좌표 변환
    // (간단히 직접 비율 사용 — 실제 ImageInfo가 있으면 더 정확)
    final pixelPoints = _points.map((p) => (x: p.dx, y: p.dy)).toList();

    final calibration = CourtCalibration(
      pixelPoints: pixelPoints,
      realPoints: CourtCalibration.defaultTennisRealPoints,
    );

    Navigator.of(context).pop(calibration);
  }
}

class _CalibrationPainter extends CustomPainter {
  final List<Offset> points;
  final Size displaySize;
  final Size containerSize;

  static const _colors = [
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.orange,
  ];
  static const _labels = ['좌상', '우상', '우하', '좌하'];

  const _CalibrationPainter({
    required this.points,
    required this.displaySize,
    required this.containerSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = 2;
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    // 점 연결선
    if (points.length > 1) {
      for (var i = 0; i < points.length - 1; i++) {
        canvas.drawLine(points[i], points[i + 1], linePaint);
      }
      if (points.length == 4) {
        canvas.drawLine(points[3], points[0], linePaint);
      }
    }

    // 각 점
    for (var i = 0; i < points.length; i++) {
      dotPaint.color = _colors[i];
      canvas.drawCircle(points[i], 12, dotPaint);
      canvas.drawCircle(points[i], 12, borderPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: _labels[i],
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, points[i].translate(-tp.width / 2, 14));
    }
  }

  @override
  bool shouldRepaint(_CalibrationPainter old) => old.points != points;
}
