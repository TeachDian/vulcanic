import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ar/ar_session.dart';
import '../engine/scene_frame.dart';
import '../engine/scene_renderer.dart';
import '../engine/volcano_controller.dart';
import '../engine/volcano_geometry.dart';
import '../engine/volcano_view.dart';
import 'explorer_screen.dart';
import 'guide_screen.dart';
import 'marker_card_screen.dart';
import 'marker_screen.dart';
import 'scene/controls.dart';
import 'surface_screen.dart';
import 'theme.dart';

/// The main interface: a live volcano and the ways to view it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.geometry});
  final VolcanoGeometry geometry;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SceneRenderer _renderer = SceneRenderer(widget.geometry);
  final VolcanoController _hero = VolcanoController()
    ..labels = false
    ..labelsT = 0;
  final OrbitCamera _camera = OrbitCamera(elevation: 17 * math.pi / 180);

  @override
  void initState() {
    super.initState();
    // Ask about AR support now, so Surface can go straight to tracking.
    ArSession.warmUp();
  }

  @override
  void dispose() {
    _renderer.dispose();
    _hero.dispose();
    super.dispose();
  }

  SceneFrame _frame(Size size) {
    // A slow turntable.
    _camera
      ..azimuth = 1.25 + _hero.clock * 0.10
      ..target.y = 0.02
      ..distance = _camera.distanceToFit(size, radius: 1.12);
    return _camera.frame(size);
  }

  void _open(Widget screen) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.55),
                radius: 0.95,
                colors: [Color(0xFF30190F), Palette.ink],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: height * 0.56,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: VolcanoView(
                  renderer: _renderer,
                  controller: _hero,
                  frameFor: _frame,
                ),
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _Wordmark(),
                    const Spacer(),
                    GlassIconButton(
                      icon: Icons.qr_code_2_rounded,
                      tooltip: 'Markers',
                      onPressed: () => _open(const MarkerCardScreen()),
                    ),
                    const SizedBox(width: 10),
                    GlassIconButton(
                      icon: Icons.menu_book_rounded,
                      tooltip: 'How it works',
                      onPressed: () => _open(const GuideScreen()),
                    ),
                  ],
                ),
                const Spacer(),
                Text('A volcano\non your desk.', style: AppText.display),
                const SizedBox(height: 12),
                Text(
                  'Place it, set it off, and look inside.',
                  style: AppText.body.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 24),
                Row(
                  spacing: 12,
                  children: [
                    Expanded(
                      child: _ModeCard(
                        title: 'Surface',
                        caption: 'On a table or floor',
                        glyph: _Glyph.surface,
                        onTap: () =>
                            _open(SurfaceScreen(geometry: widget.geometry)),
                      ),
                    ),
                    Expanded(
                      child: _ModeCard(
                        title: 'Marker',
                        caption: 'On the printed card',
                        glyph: _Glyph.marker,
                        onTap: () =>
                            _open(MarkerScreen(geometry: widget.geometry)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _WideCard(
                  title: 'Explore in 3D',
                  caption: 'No camera needed',
                  onTap: () => _open(ExplorerScreen(geometry: widget.geometry)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 10,
      children: [
        ShaderMask(
          shaderCallback: (rect) => Palette.emberGradient.createShader(rect),
          child: const Icon(
            Icons.change_history_rounded,
            size: 20,
            color: Colors.white,
          ),
        ),
        Text(
          'VULCANIC',
          style: AppText.overline.copyWith(
            fontSize: 12.5,
            letterSpacing: 3.2,
            color: Palette.bone,
          ),
        ),
      ],
    );
  }
}

enum _Glyph { surface, marker, orbit }

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.caption,
    required this.glyph,
    required this.onTap,
  }) : tag = null;

  final String title;
  final String caption;
  final _Glyph glyph;
  final VoidCallback? onTap;

  /// Small note in the corner, e.g. for a mode that is not available.
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Palette.basalt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: BorderSide(color: Palette.line(0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 72,
                      height: 60,
                      child: CustomPaint(painter: _GlyphPainter(glyph)),
                    ),
                    const Spacer(),
                    if (tag != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(tag!, style: AppText.caption),
                      )
                    else
                      const Icon(
                        Icons.arrow_outward_rounded,
                        size: 20,
                        color: Palette.ash,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(title, style: AppText.title.copyWith(fontSize: 19)),
                const SizedBox(height: 3),
                Text(caption, style: AppText.caption, maxLines: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WideCard extends StatelessWidget {
  const _WideCard({
    required this.title,
    required this.caption,
    required this.onTap,
  });

  final String title;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.basalt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
        side: BorderSide(color: Palette.line(0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
          child: Row(
            children: [
              const SizedBox(
                width: 50,
                height: 44,
                child: CustomPaint(painter: _GlyphPainter(_Glyph.orbit)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(title, style: AppText.title),
                    Text(caption, style: AppText.caption),
                  ],
                ),
              ),
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: Palette.emberGradient,
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: Color(0xFF1A0E08),
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Line drawings that stand in for each mode.
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph);
  final _Glyph glyph;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Palette.ash.withValues(alpha: 0.75);
    final accent = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Palette.ember;

    // A small cone, shared by all three.
    void cone(Offset base, double s) {
      final path = Path()
        ..moveTo(base.dx - s, base.dy)
        ..quadraticBezierTo(
          base.dx - s * 0.35,
          base.dy - s * 0.25,
          base.dx - s * 0.18,
          base.dy - s * 1.05,
        )
        ..lineTo(base.dx + s * 0.18, base.dy - s * 1.05)
        ..quadraticBezierTo(
          base.dx + s * 0.35,
          base.dy - s * 0.25,
          base.dx + s,
          base.dy,
        );
      canvas.drawPath(path, accent);
    }

    switch (glyph) {
      case _Glyph.surface:
        // A plane in perspective with a detected-surface grid.
        final near = h * 0.98, far = h * 0.52;
        for (var i = 0; i <= 4; i++) {
          final t = i / 4;
          canvas.drawLine(
            Offset(w * (0.22 + 0.56 * t), far),
            Offset(w * t, near),
            line,
          );
        }
        for (final t in [0.0, 0.38, 1.0]) {
          final y = far + (near - far) * t;
          final inset = w * 0.22 * (1 - t);
          canvas.drawLine(Offset(inset, y), Offset(w - inset, y), line);
        }
        cone(Offset(w * 0.5, h * 0.74), w * 0.24);
      case _Glyph.marker:
        // A card with corner brackets, as a scanner sees it.
        final card = Rect.fromLTWH(w * 0.14, h * 0.10, w * 0.72, h * 0.86);
        const c = 9.0;
        for (final corner in [
          (card.topLeft, 1.0, 1.0),
          (card.topRight, -1.0, 1.0),
          (card.bottomLeft, 1.0, -1.0),
          (card.bottomRight, -1.0, -1.0),
        ]) {
          final (p, sx, sy) = corner;
          canvas.drawPath(
            Path()
              ..moveTo(p.dx + c * sx, p.dy)
              ..lineTo(p.dx, p.dy)
              ..lineTo(p.dx, p.dy + c * sy),
            line,
          );
        }
        cone(Offset(w * 0.5, h * 0.78), w * 0.22);
      case _Glyph.orbit:
        cone(Offset(w * 0.5, h * 0.80), w * 0.26);
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.56),
            width: w * 0.96,
            height: h * 0.46,
          ),
          0.25,
          math.pi * 1.3,
          false,
          line,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph;
}
