import 'package:flutter/material.dart';
import 'color_schemes.dart';
import 'tokens.dart';
import 'typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(appLightScheme);
  static ThemeData dark() => _build(appDarkScheme);

  static ThemeData _build(ColorScheme cs) {
    final TextTheme tt = AppTypography.textTheme.apply(
      bodyColor: cs.onSurface,
      displayColor: cs.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      textTheme: tt,
      fontFamily: 'Pretendard',
      visualDensity: VisualDensity.adaptivePlatformDensity,

      // Card
      cardTheme: CardThemeData(
        color: cs.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
        clipBehavior: Clip.antiAlias,
      ),

      // Buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.pill),
          textStyle: tt.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.pill),
          textStyle: tt.labelLarge,
          side: BorderSide(color: cs.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: tt.labelLarge),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        selectedColor: cs.primaryContainer,
        labelStyle: tt.labelMedium,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: cs.surfaceTint,
        centerTitle: false,
        titleTextStyle: tt.titleLarge?.copyWith(color: cs.onSurface),
      ),

      // NavigationBar
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cs.surface,
        indicatorColor: cs.primaryContainer,
        height: 68,
        labelTextStyle: WidgetStateProperty.all(tt.labelSmall),
        elevation: 0,
        surfaceTintColor: cs.surface,
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        backgroundColor: cs.inverseSurface,
        contentTextStyle: tt.bodyMedium?.copyWith(color: cs.onInverseSurface),
      ),

      splashFactory: InkSparkle.splashFactory,
    );
  }
}
