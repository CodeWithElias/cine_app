import 'package:flutter/material.dart';

/// Mismos tokens de color que src/index.css del frontend web (Lumen Cinema),
/// para que la app se sienta parte del mismo producto.
class LumenColors {
  static const primary = Color(0xFFFFC174);
  static const onPrimary = Color(0xFF472A00);
  static const primaryContainer = Color(0xFFF59E0B);
  static const onPrimaryContainer = Color(0xFF613B00);

  static const secondary = Color(0xFF4CD7F6);
  static const onSecondary = Color(0xFF003640);
  static const secondaryContainer = Color(0xFF03B5D3);
  static const onSecondaryContainer = Color(0xFF00424E);

  static const tertiary = Color(0xFF56E5A9);
  static const onTertiary = Color(0xFF003824);
  static const tertiaryContainer = Color(0xFF30C88F);
  static const onTertiaryContainer = Color(0xFF004E34);

  static const error = Color(0xFFFFB4AB);
  static const onError = Color(0xFF690005);
  static const errorContainer = Color(0xFF93000A);
  static const onErrorContainer = Color(0xFFFFDAD6);

  static const surface = Color(0xFF111319);
  static const onSurface = Color(0xFFE2E2E9);
  static const onSurfaceVariant = Color(0xFFD8C3AD);
  static const outline = Color(0xFFA08E7A);
  static const outlineVariant = Color(0xFF534434);

  static const surfaceContainerLowest = Color(0xFF0C0E13);
  static const surfaceContainerLow = Color(0xFF191B21);
  static const surfaceContainer = Color(0xFF1E1F25);
  static const surfaceContainerHigh = Color(0xFF282A30);
  static const surfaceContainerHighest = Color(0xFF33353A);
}

final ThemeData lumenTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: LumenColors.surfaceContainerLowest,
  fontFamily: 'Roboto',
  colorScheme: const ColorScheme.dark(
    primary: LumenColors.primary,
    onPrimary: LumenColors.onPrimary,
    primaryContainer: LumenColors.primaryContainer,
    onPrimaryContainer: LumenColors.onPrimaryContainer,
    secondary: LumenColors.secondary,
    onSecondary: LumenColors.onSecondary,
    secondaryContainer: LumenColors.secondaryContainer,
    onSecondaryContainer: LumenColors.onSecondaryContainer,
    tertiary: LumenColors.tertiary,
    onTertiary: LumenColors.onTertiary,
    tertiaryContainer: LumenColors.tertiaryContainer,
    onTertiaryContainer: LumenColors.onTertiaryContainer,
    error: LumenColors.error,
    onError: LumenColors.onError,
    errorContainer: LumenColors.errorContainer,
    onErrorContainer: LumenColors.onErrorContainer,
    surface: LumenColors.surface,
    onSurface: LumenColors.onSurface,
    onSurfaceVariant: LumenColors.onSurfaceVariant,
    outline: LumenColors.outline,
    outlineVariant: LumenColors.outlineVariant,
    surfaceContainerLowest: LumenColors.surfaceContainerLowest,
    surfaceContainerLow: LumenColors.surfaceContainerLow,
    surfaceContainer: LumenColors.surfaceContainer,
    surfaceContainerHigh: LumenColors.surfaceContainerHigh,
    surfaceContainerHighest: LumenColors.surfaceContainerHighest,
  ),
);
