import 'package:flutter/material.dart';

/// Values from the reviewed HTML prototype, kept independent of screen logic.
abstract final class AppColors {
  static const primary = Color(0xFF0F766E);
  static const background = Color(0xFFF7FAF8);
  static const ink = Color(0xFF16302C);
  static const secondaryInk = Color(0xFF4B5563);
  static const outline = Color(0xFF6B7F7A);
  static const divider = Color(0xFFCBD7D3);
  static const selected = Color(0xFFE3F2EF);
}

enum AppTone { teal, peach, lavender, sky, warning, error, success }

@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({this.cardRadius = 20, this.ticketRadius = 24});

  final double cardRadius;
  final double ticketRadius;
  static const double gap = 12;
  static const double padding = 20;
  static const double minimumTap = 48;
  static const double buttonHeight = 56;
  static const double smallRadius = 14;

  ({Color background, Color foreground}) tone(AppTone tone) => switch (tone) {
    AppTone.teal => (
      background: const Color(0xFFDDF1EC),
      foreground: AppColors.primary,
    ),
    AppTone.peach => (
      background: const Color(0xFFFDE8DF),
      foreground: const Color(0xFFA8471F),
    ),
    AppTone.lavender => (
      background: const Color(0xFFECE8FA),
      foreground: const Color(0xFF4F3C9C),
    ),
    AppTone.sky => (
      background: const Color(0xFFE2EEFB),
      foreground: const Color(0xFF24548F),
    ),
    AppTone.warning => (
      background: const Color(0xFFFFF4DB),
      foreground: const Color(0xFF6B4500),
    ),
    AppTone.error => (
      background: const Color(0xFFFDECEC),
      foreground: const Color(0xFF8A1C1C),
    ),
    AppTone.success => (
      background: const Color(0xFFE6F4EA),
      foreground: const Color(0xFF14532D),
    ),
  };

  List<BoxShadow> get shadow => const [
    BoxShadow(color: Color(0x1216302C), blurRadius: 14, offset: Offset(0, 4)),
  ];

  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>()!;

  @override
  AppTokens copyWith({double? cardRadius, double? ticketRadius}) => AppTokens(
    cardRadius: cardRadius ?? this.cardRadius,
    ticketRadius: ticketRadius ?? this.ticketRadius,
  );

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      cardRadius: cardRadius + (other.cardRadius - cardRadius) * t,
      ticketRadius: ticketRadius + (other.ticketRadius - ticketRadius) * t,
    );
  }
}

abstract final class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'BeVietnamPro',
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.selected,
        onPrimaryContainer: AppColors.ink,
        secondary: AppColors.primary,
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: AppColors.ink,
        onSurfaceVariant: AppColors.secondaryInk,
        outline: AppColors.outline,
        outlineVariant: AppColors.divider,
        error: Color(0xFF8A1C1C),
        onError: Colors.white,
      ),
      extensions: const [AppTokens()],
    );
    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: const TextStyle(
              fontSize: 28,
              height: 1.3,
              fontWeight: FontWeight.w800,
            ),
            headlineMedium: const TextStyle(
              fontSize: 26,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
            titleLarge: const TextStyle(
              fontSize: 20,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
            titleMedium: const TextStyle(
              fontSize: 18,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
            bodyLarge: const TextStyle(fontSize: 18, height: 1.5),
            bodyMedium: const TextStyle(fontSize: 16, height: 1.5),
            bodySmall: const TextStyle(
              fontSize: 16,
              height: 1.45,
              color: AppColors.secondaryInk,
            ),
            labelLarge: const TextStyle(
              fontSize: 18,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
            labelMedium: const TextStyle(
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          )
          .apply(
            fontFamily: 'BeVietnamPro',
            bodyColor: AppColors.ink,
            displayColor: AppColors.ink,
          ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: 'BeVietnamPro',
            fontSize: 18,
            height: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 56),
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: 'BeVietnamPro',
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(
            fontFamily: 'BeVietnamPro',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outline, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorMaxLines: 5,
        errorStyle: const TextStyle(fontSize: 16, height: 1.4),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, space: 24),
    );
  }
}
