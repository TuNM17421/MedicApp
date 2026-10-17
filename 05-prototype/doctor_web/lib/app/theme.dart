import 'package:flutter/material.dart';

/// Colours of the approved prototype (`prototype/web-bac-si/assets/css/
/// tokens.css`). The adherence colours passed the colour-blind check; every
/// chart cell also carries a ✓ ½ × glyph so colour is never the only cue.
@immutable
class DwColors extends ThemeExtension<DwColors> {
  const DwColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.lineStrong,
    required this.fg,
    required this.fg2,
    required this.muted,
    required this.brand,
    required this.brandFg,
    required this.brandSoft,
    required this.brandInk,
    required this.ai,
    required this.aiSoft,
    required this.pt,
    required this.ptSoft,
    required this.ok,
    required this.okInk,
    required this.okSoft,
    required this.part,
    required this.partInk,
    required this.partSoft,
    required this.miss,
    required this.missInk,
    required this.missSoft,
    required this.s1,
    required this.s2,
    required this.grid,
  });

  final Color bg, surface, surface2, surface3, line, lineStrong;
  final Color fg, fg2, muted;
  final Color brand, brandFg, brandSoft, brandInk;
  final Color ai, aiSoft, pt, ptSoft;
  final Color ok, okInk, okSoft, part, partInk, partSoft;
  final Color miss, missInk, missSoft;
  final Color s1, s2, grid;

  static const light = DwColors(
    bg: Color(0xFFF2F5F5),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF5F8F8),
    surface3: Color(0xFFE9EFEE),
    line: Color(0xFFDDE4E3),
    lineStrong: Color(0xFFC3CECC),
    fg: Color(0xFF111A19),
    fg2: Color(0xFF45524F),
    muted: Color(0xFF6B7876),
    brand: Color(0xFF0E6F67),
    brandFg: Color(0xFFFFFFFF),
    brandSoft: Color(0xFFE2F1EE),
    brandInk: Color(0xFF0B5E57),
    ai: Color(0xFF5543B5),
    aiSoft: Color(0xFFEEEBFB),
    pt: Color(0xFF8A5300),
    ptSoft: Color(0xFFFBF0DD),
    ok: Color(0xFF1E8A4C),
    okInk: Color(0xFF16673A),
    okSoft: Color(0xFFE3F3E9),
    part: Color(0xFFD9940F),
    partInk: Color(0xFF875A00),
    partSoft: Color(0xFFFBF0D9),
    miss: Color(0xFFD03B3B),
    missInk: Color(0xFFA82727),
    missSoft: Color(0xFFFCE8E6),
    s1: Color(0xFF2A78D6),
    s2: Color(0xFFEB6834),
    grid: Color(0xFFE6EBEA),
  );

  static const dark = DwColors(
    bg: Color(0xFF0C1312),
    surface: Color(0xFF141C1B),
    surface2: Color(0xFF18221F),
    surface3: Color(0xFF1F2B29),
    line: Color(0xFF26332F),
    lineStrong: Color(0xFF344440),
    fg: Color(0xFFE6EEEC),
    fg2: Color(0xFFB5C2BF),
    muted: Color(0xFF8C9B98),
    brand: Color(0xFF3DB0A3),
    brandFg: Color(0xFF04211D),
    brandSoft: Color(0xFF16312E),
    brandInk: Color(0xFF6FCFC3),
    ai: Color(0xFFB2A7F2),
    aiSoft: Color(0xFF231F3D),
    pt: Color(0xFFF0B65A),
    ptSoft: Color(0xFF2F2412),
    ok: Color(0xFF1E8A4C),
    okInk: Color(0xFF5CC98A),
    okSoft: Color(0xFF14291E),
    part: Color(0xFFBF8410),
    partInk: Color(0xFFE8B04A),
    partSoft: Color(0xFF2E2410),
    miss: Color(0xFFD84848),
    missInk: Color(0xFFF08A84),
    missSoft: Color(0xFF341816),
    s1: Color(0xFF3987E5),
    s2: Color(0xFFD95926),
    grid: Color(0xFF222D2B),
  );

  static DwColors of(BuildContext context) =>
      Theme.of(context).extension<DwColors>()!;

  @override
  DwColors copyWith() => this;

  @override
  DwColors lerp(covariant DwColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

/// Sizes shared by the screens.
abstract final class Dw {
  static const radiusSm = 6.0;
  static const radius = 10.0;
  static const radiusLg = 14.0;
  static const rail = 76.0;
  static const bar = 56.0;
  static const banner = 300.0;

  /// Below this width the patient column stacks above the tabs.
  static const stackBelow = 980.0;

  /// Below this width the worklist shows cards instead of a table.
  static const cardsBelow = 760.0;
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? DwColors.light : DwColors.dark;
  final scheme =
      ColorScheme.fromSeed(seedColor: c.brand, brightness: brightness).copyWith(
        primary: c.brand,
        onPrimary: c.brandFg,
        surface: c.surface,
        onSurface: c.fg,
        onSurfaceVariant: c.fg2,
        outline: c.lineStrong,
        outlineVariant: c.line,
        error: c.missInk,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'BeVietnamPro',
    // Glyphs Be Vietnam Pro lacks (✓) come from a bundled font, never from
    // a font CDN (bước 18 CSP).
    fontFamilyFallback: const ['DejaVuCheck'],
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
    visualDensity: VisualDensity.standard,
  );
  final text = base.textTheme.apply(bodyColor: c.fg, displayColor: c.fg);
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Dw.radius),
  );
  return base.copyWith(
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: text.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
      bodySmall: text.bodySmall?.copyWith(fontSize: 13, color: c.fg2),
      labelSmall: text.labelSmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: c.muted,
        letterSpacing: 0.3,
      ),
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        shape: shape,
        textStyle: const TextStyle(
          fontFamily: 'BeVietnamPro',
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        foregroundColor: c.fg,
        side: BorderSide(color: c.lineStrong),
        shape: shape,
        textStyle: const TextStyle(
          fontFamily: 'BeVietnamPro',
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.brandInk,
        shape: shape,
        textStyle: const TextStyle(
          fontFamily: 'BeVietnamPro',
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dw.radius),
        borderSide: BorderSide(color: c.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dw.radius),
        borderSide: BorderSide(color: c.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dw.radius),
        borderSide: BorderSide(color: c.brand, width: 2),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: c.brandSoft,
        selectedForegroundColor: c.brandInk,
        foregroundColor: c.fg2,
        side: BorderSide(color: c.line),
        textStyle: const TextStyle(
          fontFamily: 'BeVietnamPro',
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 300),
      textStyle: TextStyle(color: c.surface, fontSize: 12),
      decoration: BoxDecoration(
        color: c.fg,
        borderRadius: BorderRadius.circular(Dw.radiusSm),
      ),
    ),
  );
}
