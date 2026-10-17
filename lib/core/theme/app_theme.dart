import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_tokens.dart';

class AppTheme {
  static const String _fontDisplay = 'BarlowCondensed';
  static const String _fontBody = 'Inter';

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;

    // Build ColorScheme manually per spec
    final ColorScheme scheme = ColorScheme(
      brightness: b,
      primary: isDark ? AppColors.primaryDark : AppColors.primaryLight,
      onPrimary: isDark ? AppColors.onPrimaryDark : AppColors.onPrimaryLight,
      secondary: AppColors.accent,
      onSecondary: AppColors.onAccent,
      error: isDark ? AppColors.errorDark : AppColors.errorLight,
      onError: isDark ? Colors.white : Colors.white,
      surface: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      onSurface: isDark ? AppColors.textDark : AppColors.textLight,
      surfaceContainerLowest:
          isDark ? const Color(0xFF0C1711) : const Color(0xFFFAFBF6),
      surfaceContainerLow:
          isDark ? const Color(0xFF0F1B14) : const Color(0xFFF8FAF3),
      surfaceContainer:
          isDark ? const Color(0xFF111C16) : const Color(0xFFFFFFFF),
      surfaceContainerHigh:
          isDark ? AppColors.surfaceHighDark : AppColors.surfaceHighLight,
      surfaceContainerHighest:
          isDark ? const Color(0xFF1D2C23) : const Color(0xFFF2F5EC),
      outline: isDark ? AppColors.outlineDark : AppColors.outlineLight,
      outlineVariant:
          isDark ? const Color(0xFF22312A) : const Color(0xFFE2E9DC),
      scrim: const Color(0xFF000000),
      inverseSurface: isDark ? AppColors.surfaceLight : AppColors.surfaceDark,
      onInverseSurface: isDark ? AppColors.textLight : AppColors.textDark,
      inversePrimary: isDark ? AppColors.primaryLight : AppColors.primaryDark,
      shadow: const Color(0xFF000000),
      surfaceTint: isDark ? AppColors.primaryDark : AppColors.primaryLight,
    );

    final fzColors = FanzoneColors(
      accent: AppColors.accent,
      onAccent: AppColors.onAccent,
      accentText: isDark ? AppColors.accent : AppColors.accentTextLight,
      surfaceHigh:
          isDark ? AppColors.surfaceHighDark : AppColors.surfaceHighLight,
      textMuted: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
      heroGradientStart:
          isDark ? AppColors.surfaceDark : AppColors.surfaceHighLight,
      heroGradientEnd: isDark ? AppColors.bgDark : AppColors.bgLight,
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );

    final filledButtonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final outlinedButtonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      dividerColor: scheme.outline,
      extensions: [fzColors],
      textTheme: _buildTextTheme(),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: _buildTextTheme().headlineSmall?.copyWith(
              fontFamily: _fontDisplay,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: scheme.outline, width: 1),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondary,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _buildTextTheme().labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                );
          }
          return _buildTextTheme().labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: scheme.onSecondary);
          }
          return IconThemeData(color: scheme.onSurfaceVariant);
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: filledButtonShape,
          backgroundColor: scheme.secondary,
          foregroundColor: scheme.onSecondary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: outlinedButtonShape,
          side: BorderSide(color: scheme.outline, width: 1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: shape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        labelStyle: _buildTextTheme().labelMedium?.copyWith(
              color: scheme.onSurface,
            ),
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outline, width: 1),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.onSecondary;
          }
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.secondary;
          }
          return scheme.surfaceContainerHigh;
        }),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline,
        thickness: 1,
      ),
    );
  }

  static TextTheme _buildTextTheme() {
    return const TextTheme(
      displaySmall:
          TextStyle(fontFamily: _fontDisplay, fontWeight: FontWeight.w700),
      headlineLarge: TextStyle(
          fontFamily: _fontDisplay, fontWeight: FontWeight.w700, fontSize: 32),
      headlineMedium: TextStyle(
          fontFamily: _fontDisplay, fontWeight: FontWeight.w600, fontSize: 28),
      headlineSmall: TextStyle(
          fontFamily: _fontDisplay, fontWeight: FontWeight.w700, fontSize: 24),
      titleLarge: TextStyle(
          fontFamily: _fontDisplay, fontWeight: FontWeight.w700, fontSize: 22),
      titleMedium: TextStyle(
          fontFamily: _fontBody, fontWeight: FontWeight.w600, fontSize: 16),
      titleSmall: TextStyle(
          fontFamily: _fontBody, fontWeight: FontWeight.w500, fontSize: 14),
      bodyLarge: TextStyle(
          fontFamily: _fontBody, fontWeight: FontWeight.w400, fontSize: 16),
      bodyMedium: TextStyle(
          fontFamily: _fontBody, fontWeight: FontWeight.w400, fontSize: 14),
      bodySmall: TextStyle(
          fontFamily: _fontBody, fontWeight: FontWeight.w400, fontSize: 12),
      labelLarge: TextStyle(
          fontFamily: _fontBody, fontWeight: FontWeight.w600, fontSize: 14),
      labelMedium: TextStyle(
          fontFamily: _fontBody, fontWeight: FontWeight.w500, fontSize: 12),
      labelSmall: TextStyle(
          fontFamily: _fontBody, fontWeight: FontWeight.w500, fontSize: 10),
    );
  }
}
