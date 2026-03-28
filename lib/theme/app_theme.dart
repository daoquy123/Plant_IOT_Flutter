import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/app_card.dart';

/// Giao diện chỉnh chu: font rõ, màu ấm, thẻ có chiều sâu nhẹ — không icon trang trí.
ThemeData buildAppTheme() {
  const ink = Color(0xFF15221A);
  const paper = Color(0xFFF3F1EC);
  const cardTint = Color(0xFFFBFAF8);
  const line = Color(0xFFDDD8CF);
  const accent = Color(0xFF1E6B55);
  const accentMuted = Color(0xFF2A8F72);

  final colorScheme = ColorScheme.light(
    primary: accent,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFD4EDE4),
    onPrimaryContainer: const Color(0xFF0D3D30),
    surface: paper,
    onSurface: ink,
    surfaceContainerLow: const Color(0xFFECEAE4),
    surfaceContainerHighest: cardTint,
    outline: line,
    outlineVariant: line.withValues(alpha: 0.6),
    error: const Color(0xFFB3261E),
    onError: Colors.white,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: paper,
    dividerColor: line.withValues(alpha: 0.65),
    splashFactory: InkRipple.splashFactory,
    extensions: const [
      AppShadows(
        card: [
          BoxShadow(
            color: Color(0x1A15221A),
            blurRadius: 28,
            offset: Offset(0, 10),
            spreadRadius: -8,
          ),
        ],
      ),
    ],
  );

  final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
    bodyColor: ink,
    displayColor: ink,
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: paper,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: ink,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardTint,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: line.withValues(alpha: 0.45)),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: TextStyle(
        color: ink.withValues(alpha: 0.38),
        fontWeight: FontWeight.w400,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: line.withValues(alpha: 0.9)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: line.withValues(alpha: 0.9)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: accentMuted, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          letterSpacing: 0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        side: BorderSide(color: line.withValues(alpha: 0.95)),
        foregroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: 14,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      subtitleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 12.5,
        color: ink.withValues(alpha: 0.55),
        height: 1.35,
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(line),
      thumbColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return Colors.white;
        return ink.withValues(alpha: 0.45);
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return accent;
        return line.withValues(alpha: 0.5);
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        textStyle: WidgetStateProperty.all(
          GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: ink,
      contentTextStyle: GoogleFonts.plusJakartaSans(color: Colors.white),
    ),
  );
}
