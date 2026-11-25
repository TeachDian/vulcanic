import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'ar_session.dart';

/// Draws what the tracker sees: detected planes, feature points and the
/// placement reticle, all projected from world space with the same camera
/// matrices as the volcano.
class TrackingPainter extends CustomPainter {
  TrackingPainter({
    required this.frame,
    required this.showSurfaces,
    required this.showReticle,
    required this.reticleFraction,
  }) : super(repaint: frame);

  final ValueListenable<ArFrame?> frame;

  /// Planes and feature points.
  final bool showSurfaces;

  /// The ring that marks where a tap would place the model.
  final bool showReticle;

  /// Height of the reticle's search point as a fraction of the view.
  final double reticleFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame.value;
    final centre = Offset(size.width / 2, size.height * reticleFraction);
    if (f == null || !f.tracking) {
      if (showReticle) _crosshair(canvas, centre, found: false);
      return;
    }
    final m = (f.projection * f.view).storage;
    final hw = size.width / 2, hh = size.height / 2;

    Offset? project(double x, double y, double z) {
      final w = m[3] * x + m[7] * y + m[11] * z + m[15];
      if (w <= 0.02) return null;
      return Offset(
        hw + (m[0] * x + m[4] * y + m[8] * z + m[12]) / w * hw,
        hh - (m[1] * x + m[5] * y + m[9] * z + m[13]) / w * hh,
      );
    }

    if (showSurfaces) {
      final fill = Paint()..color = Palette.bone.withValues(alpha: 0.07);
      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..color = Palette.bone.withValues(alpha: 0.5);
      for (final plane in f.planes) {
        final path = _outline(plane, project);
        if (path == null) continue;
        canvas.drawPath(path, fill);
        canvas.drawPath(path, edge);
      }

      final points = f.points;
      final dots = Float32List(points.length ~/ 3 * 2);
      var n = 0;
      for (var i = 0; i + 2 < points.length; i += 3) {
        final p = project(points[i], points[i + 1], points[i + 2]);
        if (p == null) continue;
        dots[n++] = p.dx;
        dots[n++] = p.dy;
      }
      canvas.drawRawPoints(
        PointMode.points,
        Float32List.sublistView(dots, 0, n),
        Paint()
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.75),
      );
    }

    if (showReticle) {
      final pose = f.reticle;
      if (pose == null) {
        _crosshair(canvas, centre, found: false);
      } else {
        _ring(canvas, pose, project);
      }
    }
  }

  Path? _outline(
    Float32List plane,
    Offset? Function(double, double, double) project,
  ) {
    final path = Path();
    for (var i = 0; i + 2 < plane.length; i += 3) {
      final p = project(plane[i], plane[i + 1], plane[i + 2]);
      // A plane that passes behind the camera is skipped rather than clipped.
      if (p == null) return null;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  /// A ring lying flat on the surface at [pose].
  void _ring(
    Canvas canvas,
    Matrix4 pose,
    Offset? Function(double, double, double) project,
  ) {
    final s = pose.storage;
    Path circle(double radius) {
      final path = Path();
      const steps = 40;
      for (var i = 0; i <= steps; i++) {
        final a = 2 * math.pi * i / steps;
        final x = radius * math.cos(a), z = radius * math.sin(a);
        final p = project(
          s[0] * x + s[8] * z + s[12],
          s[1] * x + s[9] * z + s[13],
          s[2] * x + s[10] * z + s[14],
        );
        if (p == null) return Path();
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      return path;
    }

    canvas.drawPath(
      circle(0.15),
      Paint()..color = Palette.bone.withValues(alpha: 0.14),
    );
    canvas.drawPath(
      circle(0.15),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..color = Palette.bone,
    );
    canvas.drawPath(circle(0.018), Paint()..color = Colors.white);
  }

  void _crosshair(Canvas canvas, Offset centre, {required bool found}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.7);
    const gap = 9.0, arm = 9.0;
    for (final d in const [
      Offset(1, 0),
      Offset(-1, 0),
      Offset(0, 1),
      Offset(0, -1),
    ]) {
      canvas.drawLine(centre + d * gap, centre + d * (gap + arm), paint);
    }
  }

  @override
  bool shouldRepaint(TrackingPainter old) =>
      old.frame != frame ||
      old.showSurfaces != showSurfaces ||
      old.showReticle != showReticle ||
      old.reticleFraction != reticleFraction;
}
