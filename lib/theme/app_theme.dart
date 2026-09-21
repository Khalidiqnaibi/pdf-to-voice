import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colour and shape tokens shared by every surface in the app.
///
/// Both palettes are built around a single warm accent so that the narration
/// highlight on the page, the transport controls and the progress rail all read
/// as the same instrument.
@immutable
class LumenPalette extends ThemeExtension<LumenPalette> {
  const LumenPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceHigh,
    required this.stroke,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.accent,
    required this.accentInk,
    required this.highlight,
    required this.highlightEdge,
    required this.positive,
    required this.warning,
    required this.pageBackdrop,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceHigh;
  final Color stroke;
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;
  final Color accent;
  final Color accentInk;

  /// Fill painted behind the sentence currently being spoken.
  final Color highlight;
  final Color highlightEdge;

  final Color positive;
  final Color warning;

  /// Backdrop behind PDF pages in the reader.
  final Color pageBackdrop;

  static const dark = LumenPalette(
    canvas: Color(0xFF0D0F13),
    surface: Color(0xFF14171D),
    surfaceHigh: Color(0xFF1C2028),
    stroke: Color(0xFF272C36),
    ink: Color(0xFFF2F4F8),
    inkSoft: Color(0xFFA8B0BF),
    inkFaint: Color(0xFF6B7385),
    accent: Color(0xFFF0B45C),
    accentInk: Color(0xFF241804),
    highlight: Color(0x54F0B45C),
    highlightEdge: Color(0x8CF0B45C),
    positive: Color(0xFF63C9A0),
    warning: Color(0xFFE8825C),
    pageBackdrop: Color(0xFF090A0D),
  );

  static const light = LumenPalette(
    canvas: Color(0xFFF7F4EE),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFFBF9F5),
    stroke: Color(0xFFE3DED3),
    ink: Color(0xFF1A1B1E),
    inkSoft: Color(0xFF585C66),
    inkFaint: Color(0xFF8B8F9A),
    accent: Color(0xFFB4751A),
    accentInk: Color(0xFFFFF6E7),
    highlight: Color(0x47E0A63C),
    highlightEdge: Color(0x99B4751A),
    positive: Color(0xFF2E8B67),
    warning: Color(0xFFC0552B),
    pageBackdrop: Color(0xFFE8E3DA),
  );

  @override
  LumenPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceHigh,
    Color? stroke,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? accent,
    Color? accentInk,
    Color? highlight,
    Color? highlightEdge,
    Color? positive,
    Color? warning,
    Color? pageBackdrop,
  }) {
    return LumenPalette(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      stroke: stroke ?? this.stroke,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      inkFaint: inkFaint ?? this.inkFaint,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      highlight: highlight ?? this.highlight,
      highlightEdge: highlightEdge ?? this.highlightEdge,
      positive: positive ?? this.positive,
      warning: warning ?? this.warning,
      pageBackdrop: pageBackdrop ?? this.pageBackdrop,
    );
  }

  @override
  LumenPalette lerp(ThemeExtension<LumenPalette>? other, double t) {
    if (other is! LumenPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return LumenPalette(
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceHigh: c(surfaceHigh, other.surfaceHigh),
      stroke: c(stroke, other.stroke),
      ink: c(ink, other.ink),
      inkSoft: c(inkSoft, other.inkSoft),
      inkFaint: c(inkFaint, other.inkFaint),
      accent: c(accent, other.accent),
      accentInk: c(accentInk, other.accentInk),
      highlight: c(highlight, other.highlight),
      highlightEdge: c(highlightEdge, other.highlightEdge),
      positive: c(positive, other.positive),
      warning: c(warning, other.warning),
      pageBackdrop: c(pageBackdrop, other.pageBackdrop),
    );
  }
}

/// Shorthand so widgets can reach the palette with `context.lumen.accent`.
extension LumenThemeAccess on BuildContext {
  LumenPalette get lumen => Theme.of(this).extension<LumenPalette>()!;
  TextTheme get texts => Theme.of(this).textTheme;
}

class LumenRadius {
  static const sm = Radius.circular(8);
  static const md = Radius.circular(14);
  static const lg = Radius.circular(20);
  static const xl = Radius.circular(28);

  static const brSm = BorderRadius.all(sm);
  static const brMd = BorderRadius.all(md);
  static const brLg = BorderRadius.all(lg);
  static const brXl = BorderRadius.all(xl);
}

class LumenMotion {
  static const quick = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
  static const curve = Curves.easeOutCubic;
}

class AppTheme {
  static ThemeData build(Brightness brightness) {
    final p = brightness == Brightness.dark ? LumenPalette.dark : LumenPalette.light;
    final base = brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();

    // Inter for the interface, Fraunces for the wordmark and titles - the serif
    // keeps the app feeling like a reading tool rather than a media player.
    final ui = GoogleFonts.interTextTheme(base.textTheme);
    final textTheme = ui
        .copyWith(
          displaySmall: GoogleFonts.fraunces(
            textStyle: ui.displaySmall,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
          headlineMedium: GoogleFonts.fraunces(
            textStyle: ui.headlineMedium,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
          headlineSmall: GoogleFonts.fraunces(
            textStyle: ui.headlineSmall,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
          titleLarge: ui.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
          titleMedium: ui.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1),
          labelLarge: ui.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
          labelSmall: ui.labelSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.6),
        )
        .apply(bodyColor: p.ink, displayColor: p.ink);

    final scheme = ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: brightness,
    ).copyWith(
      surface: p.surface,
      primary: p.accent,
      onPrimary: p.accentInk,
      outline: p.stroke,
      error: p.warning,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.canvas,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[p],
      dividerTheme: DividerThemeData(color: p.stroke, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.inkSoft, size: 20),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 420),
        textStyle: textTheme.labelSmall?.copyWith(color: p.ink, letterSpacing: 0.2),
        decoration: BoxDecoration(
          color: p.surfaceHigh,
          borderRadius: LumenRadius.brSm,
          border: Border.all(color: p.stroke),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.stroke,
        thumbColor: p.accent,
        overlayColor: p.accent.withValues(alpha: 0.14),
        trackHeight: 4,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.inkFaint.withValues(alpha: 0.4)),
        radius: LumenRadius.sm,
        thickness: const WidgetStatePropertyAll(7),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceHigh,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: p.ink),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: LumenRadius.brMd),
      ),
    );
  }
}
