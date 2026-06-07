import 'package:flutter/material.dart';

import 'synapse_tokens.dart';

ThemeData buildSynapseTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: SynColors.primary,
        brightness: Brightness.dark,
      ).copyWith(
        primary: SynColors.primary,
        onPrimary: Colors.white,
        secondary: SynColors.cyan,
        surface: SynColors.surface,
        onSurface: SynColors.text,
        error: SynColors.red,
        outline: SynColors.border,
        outlineVariant: SynColors.borderStrong,
      );

  final baseText = Typography.whiteMountainView.apply(
    bodyColor: SynColors.text,
    displayColor: SynColors.text,
  );

  OutlineInputBorder inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(SynRadii.lg),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: SynColors.appBg,
    cardColor: SynColors.surface,
    dividerColor: SynColors.border,
    visualDensity: VisualDensity.standard,
    textTheme: baseText.copyWith(
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleSmall: baseText.titleSmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 15, letterSpacing: 0),
      bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 13, letterSpacing: 0),
      bodySmall: baseText.bodySmall?.copyWith(
        fontSize: 12,
        letterSpacing: 0,
        color: SynColors.textMuted,
      ),
      labelLarge: baseText.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelMedium: baseText.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelSmall: baseText.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: SynColors.chrome,
      foregroundColor: SynColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SynColors.surfaceMuted,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: SynSpacing.lg,
        vertical: SynSpacing.md,
      ),
      labelStyle: const TextStyle(color: SynColors.textMuted),
      hintStyle: const TextStyle(color: SynColors.textFaint),
      prefixIconColor: SynColors.textMuted,
      suffixIconColor: SynColors.textMuted,
      border: inputBorder(SynColors.border),
      enabledBorder: inputBorder(SynColors.border),
      focusedBorder: inputBorder(SynColors.primary, width: 1.4),
      errorBorder: inputBorder(SynColors.red),
      focusedErrorBorder: inputBorder(SynColors.red, width: 1.4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SynColors.primaryStrong,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: SynSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SynRadii.md),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SynColors.text,
        side: const BorderSide(color: SynColors.borderStrong),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: SynSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SynRadii.md),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: SynColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SynRadii.md),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: SynColors.surfaceRaised,
      side: const BorderSide(color: SynColors.border),
      labelStyle: const TextStyle(color: SynColors.text, fontSize: 12),
      secondaryLabelStyle: const TextStyle(color: SynColors.text),
      padding: const EdgeInsets.symmetric(horizontal: SynSpacing.xs),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SynRadii.md),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: SynColors.surfaceMuted,
        selectedBackgroundColor: SynColors.primaryStrong.withValues(alpha: 0.9),
        foregroundColor: SynColors.textMuted,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: SynColors.borderStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SynRadii.md),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: SynColors.primaryStrong,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(SynRadii.lg)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: SynColors.surfaceRaised,
      contentTextStyle: const TextStyle(color: SynColors.text),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SynRadii.lg),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
