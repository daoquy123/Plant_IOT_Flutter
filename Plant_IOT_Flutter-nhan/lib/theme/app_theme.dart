import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/app_card.dart';

/// Trắng + Emerald — giao diện sáng, nút bo góc mềm.
ThemeData buildAppTheme() {
  const ink = Color(0xFF134E4A);
  const inkMuted = Color(0xFF475569);
  const paper = Color(0xFFFFFFFF);
  const surfaceSoft = Color(0xFFF0FDF4);
  const line = Color(0xFFD1FAE5);
  const lineMuted = Color(0xFFE2E8F0);
  const accent = Color(0xFF059669);
  const accentLight = Color(0xFF10B981);
  const accentDark = Color(0xFF047857);

  final colorScheme = ColorScheme.light(
    primary: accent,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFD1FAE5),
    onPrimaryContainer: const Color(0xFF064E3B),
    secondary: accentLight,
    onSecondary: Colors.white,
    surface: paper,
    onSurface: ink,
    surfaceContainerLow: surfaceSoft,
    surfaceContainerHighest: paper,
    outline: lineMuted,
    outlineVariant: line,
    error: const Color(0xFFDC2626),
    onError: Colors.white,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: paper,
    dividerColor: lineMuted.withValues(alpha: 0.8),
    splashFactory: InkRipple.splashFactory,
    extensions: const [
      AppShadows(
        card: [
          BoxShadow(
            color: Color(0x14059669),
            blurRadius: 24,
            offset: Offset(0, 8),
            spreadRadius: -6,
          ),
        ],
      ),
    ],
  );

  final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
    bodyColor: ink,
    displayColor: ink,
  );

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
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
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 56,
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      indicatorColor: accent.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? accentDark : inkMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 20,
          color: selected ? accent : inkMuted.withValues(alpha: 0.75),
        );
      }),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: lineMuted.withValues(alpha: 0.65)),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceSoft,
      hintStyle: TextStyle(
        color: inkMuted.withValues(alpha: 0.55),
        fontWeight: FontWeight.w400,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: lineMuted.withValues(alpha: 0.9)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: lineMuted.withValues(alpha: 0.9)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accent, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: accent.withValues(alpha: 0.35),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: buttonShape,
        shadowColor: accent.withValues(alpha: 0.35),
        textStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          letterSpacing: 0.1,
        ),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return Colors.white.withValues(alpha: 0.12);
          }
          return null;
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        elevation: 0,
        backgroundColor: surfaceSoft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
        foregroundColor: accentDark,
        disabledForegroundColor: inkMuted.withValues(alpha: 0.45),
        disabledBackgroundColor: surfaceSoft.withValues(alpha: 0.6),
        shape: buttonShape,
        textStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ).copyWith(
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(color: lineMuted.withValues(alpha: 0.7));
          }
          if (states.contains(WidgetState.pressed)) {
            return const BorderSide(color: accent, width: 1.4);
          }
          return BorderSide(color: accent.withValues(alpha: 0.4));
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return accent.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.hovered)) {
            return accent.withValues(alpha: 0.05);
          }
          return surfaceSoft;
        }),
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
        color: inkMuted,
        height: 1.35,
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(lineMuted),
      thumbColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return Colors.white;
        return inkMuted.withValues(alpha: 0.55);
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return accent;
        return lineMuted.withValues(alpha: 0.55);
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
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          if (states.contains(WidgetState.disabled)) {
            return surfaceSoft.withValues(alpha: 0.5);
          }
          return paper;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          if (states.contains(WidgetState.disabled)) {
            return inkMuted.withValues(alpha: 0.45);
          }
          return accentDark;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const BorderSide(color: accent);
          }
          return BorderSide(color: accent.withValues(alpha: 0.28));
        }),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceSoft,
      selectedColor: colorScheme.primaryContainer,
      side: BorderSide(color: accent.withValues(alpha: 0.28)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: accentDark,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      circularTrackColor: line.withValues(alpha: 0.65),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: GoogleFonts.plusJakartaSans(
        color: ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: GoogleFonts.plusJakartaSans(
        color: inkMuted,
        fontSize: 14.5,
        height: 1.4,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: accentDark,
      contentTextStyle: GoogleFonts.plusJakartaSans(color: Colors.white),
    ),
  );
}
