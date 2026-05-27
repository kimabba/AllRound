import 'package:flutter/material.dart';

class MatchUpLogo extends StatelessWidget {
  const MatchUpLogo({
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
    final foreground = textColor ?? cs.primary;
    final accent = dotColor ?? cs.secondary;

    final wordmark = RichText(
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
          const TextSpan(text: 'Match'),
          TextSpan(
            text: '•',
            style: TextStyle(color: accent),
          ),
          const TextSpan(text: 'Up'),
        ],
      ),
    );

    if (!showMark) return wordmark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MatchUpMark(size: markSize),
        const SizedBox(width: 8),
        wordmark,
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
        MatchUpLogo(fontSize: 18, textColor: textColor, dotColor: dotColor),
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

class _MatchUpMark extends StatelessWidget {
  const _MatchUpMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, cs.secondary],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.sports_soccer_rounded,
            color: cs.onPrimary,
            size: size * 0.46,
          ),
          Positioned(
            right: size * 0.12,
            bottom: size * 0.12,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: cs.tertiary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: cs.onPrimary,
                  width: size < 40 ? 1.2 : 2,
                ),
              ),
              child: Icon(
                Icons.sports_tennis_rounded,
                color: cs.onPrimary,
                size: size * 0.17,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
