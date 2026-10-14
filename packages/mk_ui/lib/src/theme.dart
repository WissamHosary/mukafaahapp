import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

abstract final class MkTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: MkColors.purple900,
      onPrimary: Colors.white,
      primaryContainer: MkColors.purple100,
      onPrimaryContainer: MkColors.purple900,
      secondary: MkColors.yellow500,
      onSecondary: MkColors.purple900,
      secondaryContainer: MkColors.yellow50,
      onSecondaryContainer: MkColors.purple900,
      tertiary: MkColors.shared,
      onTertiary: Colors.white,
      error: MkColors.danger,
      onError: Colors.white,
      errorContainer: MkColors.dangerBg,
      onErrorContainer: MkColors.danger,
      surface: MkColors.surface,
      onSurface: MkColors.ink,
      onSurfaceVariant: MkColors.ink2,
      surfaceContainerLowest: MkColors.surface,
      surfaceContainerLow: MkColors.canvas,
      surfaceContainer: MkColors.purple50,
      surfaceContainerHigh: MkColors.purple100,
      outline: MkColors.line,
      outlineVariant: MkColors.line,
      shadow: MkColors.purple900,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme.copyWith(
      displaySmall: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.5),
      headlineMedium: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.3),
      headlineSmall: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25),
      titleLarge: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.3),
      titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.35),
      titleSmall: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
      bodyLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5),
      bodyMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5),
      bodySmall: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, height: 1.45),
      labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1),
      labelMedium: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3),
    ).apply(bodyColor: MkColors.ink, displayColor: MkColors.ink);

    final shape = RoundedRectangleBorder(borderRadius: MkRadius.all(MkRadius.md));
    const btnPad = EdgeInsets.symmetric(horizontal: MkSpace.xl, vertical: MkSpace.md);

    return base.copyWith(
      scaffoldBackgroundColor: MkColors.canvas,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: MkColors.canvas,
        foregroundColor: MkColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MkColors.purple900,
          foregroundColor: Colors.white,
          disabledBackgroundColor: MkColors.line,
          minimumSize: const Size(64, 54),
          padding: btnPad,
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MkColors.purple900,
          minimumSize: const Size(64, 54),
          padding: btnPad,
          shape: shape,
          side: const BorderSide(color: MkColors.line, width: 1.4),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: MkColors.purple700, textStyle: text.labelLarge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MkColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: MkSpace.md, vertical: MkSpace.md),
        hintStyle: text.bodyLarge?.copyWith(color: MkColors.ink3),
        labelStyle: text.bodyMedium?.copyWith(color: MkColors.ink2),
        border: OutlineInputBorder(borderRadius: MkRadius.all(MkRadius.md), borderSide: const BorderSide(color: MkColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: MkRadius.all(MkRadius.md), borderSide: const BorderSide(color: MkColors.line, width: 1.2)),
        focusedBorder: OutlineInputBorder(borderRadius: MkRadius.all(MkRadius.md), borderSide: const BorderSide(color: MkColors.purple700, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: MkRadius.all(MkRadius.md), borderSide: const BorderSide(color: MkColors.danger, width: 1.2)),
      ),
      cardTheme: CardThemeData(
        color: MkColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: MkRadius.all(MkRadius.lg), side: const BorderSide(color: MkColors.line)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: MkColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: MkColors.yellow500,
        height: 70,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? MkColors.purple900 : MkColors.ink3, size: 24),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: MkColors.purple900,
        indicatorColor: MkColors.yellow500,
        selectedIconTheme: const IconThemeData(color: MkColors.purple900),
        unselectedIconTheme: const IconThemeData(color: Color(0xFFCBBEDC)),
        selectedLabelTextStyle: text.labelMedium?.copyWith(color: Colors.white),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(color: const Color(0xFFCBBEDC)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: MkColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(MkRadius.xl))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: MkColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: MkRadius.all(MkRadius.lg)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MkColors.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: MkRadius.all(MkRadius.md)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MkColors.surface,
        selectedColor: MkColors.purple900,
        side: const BorderSide(color: MkColors.line),
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: MkRadius.all(MkRadius.pill)),
        showCheckmark: false,
      ),
      dividerTheme: const DividerThemeData(color: MkColors.line, thickness: 1, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: MkColors.purple900),
    );
  }
}
