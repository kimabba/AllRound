import 'package:flutter/material.dart';
import '../theme/tokens.dart';

enum AppToastKind { info, success, warning, error }

class AppToast {
  AppToast._();

  static void show(
    BuildContext context,
    String message, {
    AppToastKind kind = AppToastKind.info,
  }) {
    final cs = Theme.of(context).colorScheme;
    final (Color bg, Color fg, IconData icon) = switch (kind) {
      AppToastKind.success => (
        cs.primaryContainer,
        cs.onPrimaryContainer,
        Icons.check_circle_rounded
      ),
      AppToastKind.warning => (
        cs.tertiaryContainer,
        cs.onTertiaryContainer,
        Icons.warning_amber_rounded
      ),
      AppToastKind.error => (
        cs.errorContainer,
        cs.onErrorContainer,
        Icons.error_rounded,
      ),
      AppToastKind.info => (
        cs.inverseSurface,
        cs.onInverseSurface,
        Icons.info_rounded,
      ),
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: bg,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(AppSpacing.lg),
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          content: Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(message, style: TextStyle(color: fg))),
            ],
          ),
        ),
      );
  }
}
