import 'package:flutter/material.dart';

import '../models/tournament.dart';

class ClubAvatar extends StatelessWidget {
  final Club club;
  final double size;

  const ClubAvatar({
    super.key,
    required this.club,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final spec = _clubLogoSpec(club);

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: spec.background,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: club.logoUrl == null || club.logoUrl!.isEmpty
          ? Icon(spec.icon, color: spec.foreground, size: size * 0.48)
          : Image.network(
              club.logoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                spec.icon,
                color: spec.foreground,
                size: size * 0.48,
              ),
            ),
    );
  }

  _ClubLogoSpec _clubLogoSpec(Club club) {
    final name = club.name;
    if (name.contains('리얼')) {
      return const _ClubLogoSpec(
        icon: Icons.shield_rounded,
        background: Color(0xFFE8F2FF),
        foreground: Color(0xFF2563EB),
      );
    }
    if (name.contains('올라운드')) {
      return const _ClubLogoSpec(
        icon: Icons.all_inclusive_rounded,
        background: Color(0xFFEAF7F1),
        foreground: Color(0xFF059669),
      );
    }
    if (name.contains('위너스')) {
      return const _ClubLogoSpec(
        icon: Icons.emoji_events_rounded,
        background: Color(0xFFFFF4D6),
        foreground: Color(0xFFF59E0B),
      );
    }
    if (name.contains('랠리')) {
      return const _ClubLogoSpec(
        icon: Icons.sports_tennis_rounded,
        background: Color(0xFFFFF0D8),
        foreground: Color(0xFFFF7A1A),
      );
    }
    if (name.contains('첨단')) {
      return const _ClubLogoSpec(
        icon: Icons.bolt_rounded,
        background: Color(0xFFEDE9FE),
        foreground: Color(0xFF7C3AED),
      );
    }
    if (name.contains('주말')) {
      return const _ClubLogoSpec(
        icon: Icons.wb_sunny_rounded,
        background: Color(0xFFFFF7ED),
        foreground: Color(0xFFEA580C),
      );
    }
    if (club.sport == 'tennis') {
      return const _ClubLogoSpec(
        icon: Icons.sports_tennis_rounded,
        background: Color(0xFFFFF0D8),
        foreground: Color(0xFFFF7A1A),
      );
    }
    return const _ClubLogoSpec(
      icon: Icons.sports_soccer_rounded,
      background: Color(0xFFE8F6D6),
      foreground: Color(0xFF7DCD18),
    );
  }
}

class _ClubLogoSpec {
  final IconData icon;
  final Color background;
  final Color foreground;

  const _ClubLogoSpec({
    required this.icon,
    required this.background,
    required this.foreground,
  });
}
