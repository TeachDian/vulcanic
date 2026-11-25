import 'package:flutter/material.dart';

/// Colour tokens.
///
/// The interface is graphite and bone and stays out of the way. Vivid
/// colour is reserved for the volcano and for things that are hot, so
/// [heat] is used sparingly: the eruption's playhead and little else.
abstract final class Palette {
  static const Color ink = Color(0xFF0E1216);
  static const Color panel = Color(0xFF161C22);
  static const Color raise = Color(0xFF222B34);
  static const Color bone = Color(0xFFECE8E1);
  static const Color ash = Color(0xFF98A2AD);
  static const Color smoke = Color(0xFF5E6873);

  /// Dark text and icons on a bone surface.
  static const Color onBone = Color(0xFF0E1216);

  static const Color heat = Color(0xFFF26A1B);
  static const Color good = Color(0xFF7BD3A0);
  static const Color caution = Color(0xFFF2B950);

  static Color line([double opacity = 0.09]) =>
      Colors.white.withValues(alpha: opacity);
}

/// Type scale: one family, Archivo, set wide for names and at its normal
/// width for everything else.
abstract final class AppText {
  static const String family = 'Archivo';

  static TextStyle _style(
    double size,
    double weight, {
    double width = 100,
    double height = 1.3,
    double spacing = 0,
    Color color = Palette.bone,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: height,
    letterSpacing: spacing,
    color: color,
    fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
    fontVariations: [
      FontVariation('wght', weight),
      FontVariation('wdth', width),
    ],
  );

  static final TextStyle display = _style(
    34,
    660,
    width: 122,
    height: 1.02,
    spacing: -0.6,
  );
  static final TextStyle headline = _style(
    25,
    650,
    width: 118,
    height: 1.08,
    spacing: -0.4,
  );
  static final TextStyle title = _style(16, 620, width: 106, height: 1.25);
  static final TextStyle body = _style(
    14.5,
    400,
    height: 1.5,
    color: Palette.ash,
  );
  static final TextStyle bodyStrong = _style(14.5, 600, height: 1.35);
  static final TextStyle label = _style(13, 600, height: 1.2);
  static final TextStyle caption = _style(
    12,
    500,
    height: 1.3,
    color: Palette.ash,
  );
  static final TextStyle wordmark = _style(
    13,
    680,
    width: 125,
    height: 1,
    spacing: 1.4,
  );

  /// Keeps text and icons legible over a camera image without a box
  /// behind them.
  static const List<Shadow> overCamera = [
    Shadow(color: Color(0xB3000000), blurRadius: 10),
    Shadow(color: Color(0x66000000), blurRadius: 2),
  ];
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: Palette.bone,
    onPrimary: Palette.onBone,
    secondary: Palette.bone,
    onSecondary: Palette.onBone,
    surface: Palette.panel,
    onSurface: Palette.bone,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.ink,
    fontFamily: AppText.family,
    splashFactory: InkSparkle.splashFactory,
    textTheme: TextTheme(
      displaySmall: AppText.display,
      headlineSmall: AppText.headline,
      titleMedium: AppText.title,
      bodyMedium: AppText.body,
      labelLarge: AppText.label,
      bodySmall: AppText.caption,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
  );
}

/// A solid surface for controls that sit over the scene or the camera.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(20)),
    this.padding = EdgeInsets.zero,
    this.opacity = 0.94,
  });

  final Widget child;
  final BorderRadius radius;
  final EdgeInsetsGeometry padding;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Palette.panel.withValues(alpha: opacity),
        borderRadius: radius,
        border: Border.all(color: Palette.line()),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
