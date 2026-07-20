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
        color: cs.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: cs.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // Buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSizes.control),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: tt.labelLarge,
          elevation: 0,
          disabledBackgroundColor: cs.surfaceContainerHighest,
          disabledForegroundColor: cs.onSurfaceVariant,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSizes.control),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: tt.labelLarge,
          side: BorderSide(color: cs.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size.square(AppSizes.touchTarget),
          textStyle: tt.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: cs.surfaceContainerLow,
        selectedColor: cs.primaryContainer,
        labelStyle: tt.labelMedium,
        side: BorderSide(color: cs.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: cs.primary, width: 1.5),
        ),
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        toolbarHeight: AppSizes.appBar,
        titleTextStyle: tt.titleLarge?.copyWith(
          color: cs.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cs.surface,
        indicatorColor: Colors.transparent,
        height: AppSizes.bottomNavigation,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return tt.labelSmall?.copyWith(
            color: selected ? cs.onSurface : cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? cs.primary : cs.onSurfaceVariant,
            size: 23,
          );
        }),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        backgroundColor: cs.inverseSurface,
        contentTextStyle: tt.bodyMedium?.copyWith(color: cs.onInverseSurface),
      ),

      dividerTheme: DividerThemeData(
        color: cs.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: cs.outlineVariant,
        indicatorColor: cs.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: cs.onSurface,
        unselectedLabelColor: cs.onSurfaceVariant,
        labelStyle: tt.labelLarge,
        unselectedLabelStyle: tt.labelLarge,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        minTileHeight: AppSizes.listRow,
        iconColor: cs.onSurfaceVariant,
        textColor: cs.onSurface,
      ),

      splashFactory: InkRipple.splashFactory,
    );
  }
}
