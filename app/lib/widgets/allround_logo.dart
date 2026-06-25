import 'dart:math' as math;

import 'package:flutter/material.dart';

class AllRoundLogo extends StatelessWidget {
  const AllRoundLogo({
    super.key,
    this.fontSize = 24,
    this.textColor,
    this.dotColor,
    this.showMark = false,
    this.markSize = 40,
  });

  final double fontSize;
  final Color? textColor;
  final Color? dotColor;
  final bool showMark;
  final double markSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = textColor ?? cs.onSurface;

    final brandName = RichText(
      text: TextSpan(
        style: TextStyle(
          color: foreground,
          fontFamily: 'Pretendard',
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
          height: 1,
        ),
        children: [
          const TextSpan(text: 'ALL'),
          TextSpan(
            text: 'ROUND',
            style: TextStyle(color: textColor ?? cs.primary),
          ),
        ],
      ),
    );

    final lockup = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AllroundMark(size: fontSize < 20 ? 26 : markSize),
        SizedBox(width: fontSize < 20 ? 7 : 9),
        brandName,
      ],
    );

    if (!showMark) return lockup;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AllroundMark(size: markSize),
        const SizedBox(width: 8),
        brandName,
      ],
    );
  }
}

class BrandedAppBarTitle extends StatelessWidget {
  const BrandedAppBarTitle({
    super.key,
    required this.title,
    this.textColor,
    this.dotColor,
  });

  final String title;
  final Color? textColor;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AllRoundLogo(fontSize: 18, textColor: textColor, dotColor: dotColor),
        const SizedBox(width: 10),
        Container(width: 1, height: 18, color: cs.outlineVariant),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            style: tt.titleMedium?.copyWith(
              color: textColor ?? cs.onSurface,
              fontWeight: FontWeight.w900,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _AllroundMark extends StatelessWidget {
  const _AllroundMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AllroundMarkPainter(
          background: cs.primary,
          orbit: cs.secondary,
          accent: cs.tertiary,
        ),
      ),
    );
  }
}

class _AllroundMarkPainter extends CustomPainter {
  const _AllroundMarkPainter({
    required this.background,
    required this.orbit,
    required this.accent,
  });

  final Color background;
  final Color orbit;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final rect = Offset.zero & Size(side, side);
    final radius = side * 0.34;

    final bgPaint = Paint()..color = background;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      bgPaint,
    );

    final center = Offset(side * 0.5, side * 0.51);
    final orbitStroke = side * 0.09;
    final orbitRect = Rect.fromCircle(center: center, radius: side * 0.25);
    final whiteStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = orbitStroke;

    canvas.drawArc(
        orbitRect, math.pi * 0.06, math.pi * 1.36, false, whiteStroke);

    final orbitPaint = Paint()
      ..color = orbit
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = side * 0.075;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: side * 0.34),
      math.pi * 1.12,
      math.pi * 0.48,
      false,
      orbitPaint,
    );

    final slashPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = side * 0.105;
    canvas.drawLine(
      Offset(side * 0.34, side * 0.68),
      Offset(side * 0.68, side * 0.32),
      slashPaint,
    );

    final accentPaint = Paint()..color = accent;
    canvas.drawCircle(
        Offset(side * 0.71, side * 0.28), side * 0.095, accentPaint);

    final smallNodePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95);
    canvas.drawCircle(
      Offset(side * 0.29, side * 0.72),
      side * 0.055,
      smallNodePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AllroundMarkPainter oldDelegate) {
    return background != oldDelegate.background ||
        orbit != oldDelegate.orbit ||
        accent != oldDelegate.accent;
  }
}
