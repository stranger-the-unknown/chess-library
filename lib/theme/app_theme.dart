import 'package:flutter/material.dart';

import '../widgets/cursors.dart';

/// Uygulamanın renk paleti ve tema tanımları.
///
/// Renkler doğrudan sabit olarak kullanılmaz; ekranlar
/// `Theme.of(context).colorScheme` ve [AppPalette] uzantısı üzerinden
/// okur, böylece açık/koyu tema tek bir yerden yönetilir.
class AppTheme {
  AppTheme._();

  // Marka renkleri
  static const Color green = Color(0xFF5A8232);
  static const Color greenDark = Color(0xFF3F5E22);
  static const Color gold = Color(0xFFDDBB72);
  static const Color danger = Color(0xFFD1584C);
  static const Color info = Color(0xFF5B8DD9);

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: green,
    onPrimary: Color(0xFF0E1207),
    primaryContainer: greenDark,
    onPrimaryContainer: Color(0xFFF0F6E6),
    secondary: gold,
    onSecondary: Color(0xFF1A1408),
    secondaryContainer: Color(0xFF4A3A18),
    onSecondaryContainer: Color(0xFFFBEBD0),
    error: danger,
    onError: Colors.white,
    errorContainer: Color(0xFF5C221D),
    onErrorContainer: Color(0xFFFFDAD5),
    surface: Color(0xFF16130F),
    onSurface: Color(0xFFF3EFE8),
    surfaceContainerLowest: Color(0xFF100D0A),
    surfaceContainerLow: Color(0xFF1B1713),
    surfaceContainer: Color(0xFF211C17),
    surfaceContainerHigh: Color(0xFF2A241E),
    surfaceContainerHighest: Color(0xFF332C25),
    onSurfaceVariant: Color(0xFFB6ADA1),
    outline: Color(0xFF544C43),
    outlineVariant: Color(0xFF39332C),
    inverseSurface: Color(0xFFF3EFE8),
    onInverseSurface: Color(0xFF16130F),
    shadow: Colors.black,
    scrim: Colors.black,
  );

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: greenDark,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFD7E8C0),
    onPrimaryContainer: Color(0xFF1A280C),
    secondary: Color(0xFFA37527),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFF7E7C7),
    onSecondaryContainer: Color(0xFF3A2A08),
    error: Color(0xFFB3261E),
    onError: Colors.white,
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: Color(0xFFFAF7F2),
    onSurface: Color(0xFF1E1B18),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFF6F2EB),
    surfaceContainer: Color(0xFFF1ECE3),
    surfaceContainerHigh: Color(0xFFEBE5DA),
    surfaceContainerHighest: Color(0xFFE5DED1),
    onSurfaceVariant: Color(0xFF5C554C),
    outline: Color(0xFFBFB6A9),
    outlineVariant: Color(0xFFDDD5C8),
    inverseSurface: Color(0xFF33302B),
    onInverseSurface: Color(0xFFF6F2EB),
    shadow: Colors.black,
    scrim: Colors.black,
  );

  static ThemeData get dark => _build(_darkScheme);
  static ThemeData get light => _build(_lightScheme);

  static ThemeData _build(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
          foregroundColor: scheme.onSurfaceVariant,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        mouseCursor: kClickable,
      ),
      popupMenuTheme: const PopupMenuThemeData(mouseCursor: kClickable),
      checkboxTheme: const CheckboxThemeData(mouseCursor: kClickable),
      radioTheme: const RadioThemeData(mouseCursor: kClickable),
      menuButtonTheme: MenuButtonThemeData(
        style: MenuItemButton.styleFrom(
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        mouseCursor: kClickable,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
      ),
      switchTheme: SwitchThemeData(
        mouseCursor: kClickable,
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : (isDark ? scheme.onSurfaceVariant : Colors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
    );
  }
}

/// Satranca özgü, tema tablosunda karşılığı olmayan renkler.
extension AppPalette on ColorScheme {
  Color get success => brightness == Brightness.dark
      ? const Color(0xFF7FC24A)
      : const Color(0xFF3F7D1E);

  Color get warning => const Color(0xFFE0A83A);

  Color get drawColor => brightness == Brightness.dark
      ? const Color(0xFF9E958A)
      : const Color(0xFF6E665C);

  /// Son oynanan hamlenin vurgu rengi.
  Color get lastMove => const Color(0x8CFFD24A);

  /// Seçili karenin vurgu rengi.
  Color get selectedSquare => const Color(0x8C7FD44A);

  /// Şah çekilen şahın karesi.
  Color get checkSquare => const Color(0xB3E5484D);

  /// Doğru / yanlış bulmaca geri bildirimi.
  Color get correct => const Color(0xFF57B84E);
  Color get wrong => const Color(0xFFD1584C);
}
