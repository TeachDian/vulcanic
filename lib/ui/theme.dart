import 'dart:ui';

import 'package:flutter/material.dart';

/// Colour tokens. A dark, volcanic palette: basalt neutrals and one warm
/// accent that is reserved for the things you can act on.
abstract final class Palette {
  static const Color ink = Color(0xFF0B0C0E);
  static const Color basalt = Color(0xFF14161A);
  static const Color slate = Color(0xFF1E2127);
  static const Color bone = Color(0xFFF4F1EC);
  static const Color ash = Color(0xFFA8A39C);
  static const Color smoke = Color(0xFF6F6B66);

  static const Color ember = Color(0xFFFF6A3D);
  static const Color glow = Color(0xFFFFB347);
  static const Color magma = Color(0xFFD9401C);

  static const Color good = Color(0xFF7EE0A1);
  static const Color caution = Color(0xFFFFC857);

  static Color line([double opacity = 0.10]) =>
      Colors.white.withValues(alpha: opacity);

  static const LinearGradient emberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [glow, ember, magma],
    stops: [0, 0.55, 1],
  );
}

/// Type scale, all in Sora.
abstract final class AppText {
  static const String family = 'Sora';

  static TextStyle _style(
    double size,
    double weight, {
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
    fontVariations: [FontVariation('wght', weight)],
  );

  static final TextStyle display = _style(42, 700, height: 1.04, spacing: -1.4);
  static final TextStyle headline = _style(
    26,
    650,
    height: 1.12,
    spacing: -0.6,
  );
  static final TextStyle title = _style(17, 600, height: 1.25, spacing: -0.2);
  static final TextStyle body = _style(
    15,
    400,
    height: 1.55,
    color: Palette.ash,
  );
  static final TextStyle bodyStrong = _style(15, 550, height: 1.4);
  static final TextStyle label = _style(12.5, 600, height: 1.2);
  static final TextStyle caption = _style(
    11.5,
    500,
    height: 1.3,
    color: Palette.ash,
  );
  static final TextStyle overline = _style(
    10.5,
    650,
    height: 1.2,
    spacing: 1.8,
    color: Palette.ash,
  );
}

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Palette.ember,
        brightness: Brightness.dark,
      ).copyWith(
        primary: Palette.ember,
        onPrimary: const Color(0xFF1A0E08),
        surface: Palette.basalt,
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

/// A translucent panel that blurs whatever is behind it. Used for every
/// control that floats over the 3D scene or the camera.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
    this.tint = 0.62,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Opacity of the dark tint over the blur.
  final double tint;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Palette.basalt.withValues(alpha: tint),
            borderRadius: shape,
            border: Border.all(color: Palette.line(0.09)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
