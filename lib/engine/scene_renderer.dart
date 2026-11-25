import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math_64.dart';

import 'eruption.dart';
import 'scene_frame.dart';
import 'volcano_controller.dart';
import 'volcano_geometry.dart';

/// Draws the volcano onto a [Canvas].
///
/// This is a small software pipeline: vertices are transformed on the CPU,
/// triangles are back-face culled, ordered back to front and handed to
/// `Canvas.drawVertices` in a single call.
///
/// A canvas has no depth buffer, so ordering is done in two steps:
///
///  1. The planes x = 0 and z = 0 split the model into four quadrants. Seen
///     from any camera position they have a fixed far-to-near order, and no
///     triangle straddles a plane, so quadrants never interleave.
///  2. Inside a quadrant the components stack in a known order (rock block,
///     cone, chamber, conduit, lava) and each is sorted by depth.
///
/// The cutaway is the same structure used in reverse: it hides the exterior
/// of one quadrant and shows the section faces and interior behind it.
class SceneRenderer {
  SceneRenderer(this.geometry) {
    final t = geometry.triangleCount;
    _sx = Float32List(t * 3);
    _sy = Float32List(t * 3);
    _sw = Float32List(t * 3);
    _xy = Float32List(t * 6);
    _argb = Int32List(t * 3);
    _order = Int32List(t);
    _keys = Float64List(t);
    _alpha = Float32List(t);
  }

  final VolcanoGeometry geometry;

  late final Float32List _sx, _sy, _sw; // projected corners
  late final Float32List _xy; // vertex positions handed to the canvas
  late final Int32List _argb; // vertex colours handed to the canvas
  late final Int32List _order;
  late final Float64List _keys;
  late final Float32List _alpha;

  final Paint _meshPaint = Paint();
  ui.Image? _puff;

  final Map<VolcanoPart, Rect> _labelRects = {};
  final Map<(VolcanoPart, bool, int), TextPainter> _textPainters = {};
  TextStyle? _labelStyle;

  /// Screen rectangle covered by the model in the last frame, if visible.
  Rect? bounds;

  static const double _near = 0.02;

  /// Pins and their names are bone, like the rest of the interface.
  static const Color pinColor = Color(0xFFECE8E1);

  /// The part whose label is under [position], if any.
  VolcanoPart? partAt(Offset position) {
    for (final entry in _labelRects.entries) {
      if (entry.value.inflate(8).contains(position)) return entry.key;
    }
    return null;
  }

  void dispose() {
    _puff?.dispose();
    for (final painter in _textPainters.values) {
      painter.dispose();
    }
  }

  void paint(
    Canvas canvas,
    Size size,
    SceneFrame frame,
    VolcanoController state, {
    TextStyle? labelStyle,
    EdgeInsets labelInsets = EdgeInsets.zero,
  }) {
    _labelRects.clear();
    bounds = null;
    if (frame.opacity <= 0.01 || size.isEmpty) return;

    final g = geometry;
    final eruption = state.eruption;
    final clock = state.clock;

    // Ground tremor while the eruption builds.
    final model = frame.model.clone();
    final tremor = eruption.tremor;
    if (tremor > 0) {
      model.translateByDouble(
        0.010 * tremor * math.sin(clock * 71),
        0.006 * tremor * math.sin(clock * 93),
        0,
        1,
      );
    }
    final mv = frame.view * model;
    final mvp = frame.projection * mv;
    final inverse = Matrix4.zero();
    if (inverse.copyInverse(mv) == 0) return;
    final camera = inverse.getTranslation(); // camera in model space

    // Key light, fixed relative to the viewer so the lit side faces them.
    // Three lights, all fixed relative to the viewer so the model always
    // presents well: a warm key from the upper left, a cool fill from the
    // right that keeps the shadow side from going flat, and a rim that
    // picks out the silhouette against a dark table or backdrop.
    final toModel = mv.getRotation()..transpose();
    final key = toModel.transformed(
      (frame.light ?? Vector3(-0.42, 0.74, 0.52)).normalized(),
    )..normalize();
    final fill = toModel.transformed(Vector3(0.72, 0.12, 0.42).normalized())
      ..normalize();
    final eye = camera.normalized();
    final lx = key.x, ly = key.y, lz = key.z;
    final fx = fill.x, fy = fill.y, fz = fill.z;
    final ex = eye.x, ey = eye.y, ez = eye.z;

    final hw = size.width / 2, hh = size.height / 2;
    final m = mvp.storage;

    if (frame.shadow) {
      _paintShadow(
        canvas,
        m,
        hw,
        hh,
        frame.opacity,
        g.restDepth(state.cutawayT),
      );
    }

    // 1. Project every corner.
    final p = g.positions;
    final corners = g.triangleCount * 3;
    for (var i = 0, j = 0; i < corners; i++, j += 3) {
      final x = p[j], y = p[j + 1], z = p[j + 2];
      final w = m[3] * x + m[7] * y + m[11] * z + m[15];
      _sw[i] = w;
      if (w > _near) {
        final inv = 1 / w;
        _sx[i] = hw + (m[0] * x + m[4] * y + m[8] * z + m[12]) * inv * hw;
        _sy[i] = hh - (m[1] * x + m[5] * y + m[9] * z + m[13]) * inv * hh;
      }
    }

    // 2. Decide what is visible and build the sort keys.
    final cut = state.cutawayT;
    const notch = VolcanoGeometry.notchQuadrant;
    final cameraQuadrant = (camera.x > 0 ? 1 : 0) | (camera.z > 0 ? 2 : 0);
    final quadrantRank = Int32List(4);
    quadrantRank[cameraQuadrant ^ 3] = 0; // opposite: farthest
    quadrantRank[cameraQuadrant ^ 1] = 1;
    quadrantRank[cameraQuadrant ^ 2] = 2;
    quadrantRank[cameraQuadrant] = 3; // own: nearest
    // Stacking of the components inside a quadrant, indexed by part.
    final layerRank = camera.y >= 0
        ? const [1, 0, 2, 3, 4] // seen from above: block first
        : const [0, 4, 3, 2, 1]; // seen from below: block last

    var count = 0;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    final roles = g.roles, quadrants = g.quadrants, parts = g.parts;
    for (var t = 0; t < g.triangleCount; t++) {
      final quadrant = quadrants[t];
      final role = roles[t];
      double a;
      if (role == FaceRole.section.index) {
        a = cut;
      } else if (role == FaceRole.deep.index) {
        // Rock under the plinth appears with the cutaway.
        a = quadrant == notch ? 0 : cut;
      } else if (role == FaceRole.magma.index ||
          role == FaceRole.conduit.index) {
        a = quadrant == notch ? cut : 0;
      } else {
        a = quadrant == notch ? 1 - cut : 1;
      }
      a *= frame.opacity;
      if (a < 0.02) continue;

      final i = t * 3;
      final w0 = _sw[i], w1 = _sw[i + 1], w2 = _sw[i + 2];
      if (w0 <= _near || w1 <= _near || w2 <= _near) continue;
      final ax = _sx[i], ay = _sy[i];
      final area =
          (_sx[i + 1] - ax) * (_sy[i + 2] - ay) -
          (_sy[i + 1] - ay) * (_sx[i + 2] - ax);
      if (area >= 0) continue; // facing away (screen Y points down)

      _alpha[t] = a;
      _keys[t] =
          (quadrantRank[quadrant] * 8 + layerRank[parts[t]]) * 1e4 -
          (w0 + w1 + w2) / 3;
      _order[count++] = t;

      for (var c = 0; c < 3; c++) {
        final x = _sx[i + c], y = _sy[i + c];
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    if (count == 0) return;
    bounds = Rect.fromLTRB(minX, minY, maxX, maxY);

    final order = Int32List.sublistView(_order, 0, count)
      ..sort((a, b) => _keys[a].compareTo(_keys[b]));

    // 3. Shade and emit.
    final nrm = g.normals, col = g.colors, aux = g.aux;
    final exposure = frame.exposure;
    final glow = eruption.craterGlow;
    final level = eruption.magmaLevel;
    final reveal = eruption.lavaReveal;
    final heat = eruption.lavaHeat;
    final rising =
        smoothstep(0.2, 3.5, eruption.time) *
        (1 - smoothstep(13, 18, eruption.time));
    final selected = state.highlighted?.index ?? -1;
    final selection = state.selectionT;
    final pulse = 0.5 + 0.5 * math.sin(clock * 3.2);

    for (var k = 0; k < count; k++) {
      final t = order[k];
      final role = roles[t];
      final part = parts[t];
      final alpha = (_alpha[t] * 255).round() << 24;
      for (var c = 0; c < 3; c++) {
        final i = t * 3 + c;
        final j = i * 3;
        var r = col[j], gr = col[j + 1], b = col[j + 2];
        final nx = nrm[j], ny = nrm[j + 1], nz = nrm[j + 2];
        var ndl = nx * lx + ny * ly + nz * lz;
        if (ndl < 0) ndl = 0;
        var ndf = nx * fx + ny * fy + nz * fz;
        if (ndf < 0) ndf = 0;
        var facing = nx * ex + ny * ey + nz * ez;
        if (facing < 0) facing = 0;
        final edge = (1 - facing) * (1 - facing) * (1 - facing);
        // Overall brightness, used where a surface is tinted as a whole.
        final lit = (0.30 + 0.86 * ndl + 0.22 * ndf + 0.16 * edge) * exposure;

        switch (role) {
          case 0 || 6: // rock, and the rock under the plinth
            // Warm key, cool fill, cool rim.
            r *= (0.27 + 0.92 * ndl + 0.12 * ndf + 0.13 * edge) * exposure;
            gr *= (0.29 + 0.86 * ndl + 0.17 * ndf + 0.16 * edge) * exposure;
            b *= (0.34 + 0.74 * ndl + 0.27 * ndf + 0.22 * edge) * exposure;
          case 1: // section
            final s = (0.80 + 0.28 * ndl) * exposure;
            r *= s;
            gr *= s;
            b *= s;
          case 2: // crater
            final e = glow * 0.92;
            r = r * lit * (1 - e) + 1.00 * e;
            gr = gr * lit * (1 - e) + 0.50 * e;
            b = b * lit * (1 - e) + 0.14 * e;
          case 3: // magma chamber
            final s =
                (0.93 + 0.07 * math.sin(clock * 2.2 + p[j] * 9)) *
                (1 + 0.14 * rising) *
                (0.80 + 0.26 * ndl);
            r *= s;
            gr *= s;
            b *= s;
          case 4: // conduit
            final a = aux[i];
            final hot = 1 - smoothstep(level - 0.04, level + 0.04, a);
            final shimmer = 0.07 * math.sin(a * 34 - clock * 7);
            final v = 0.84 + 0.22 * ndl;
            r *= (0.36 + (0.68 + shimmer) * hot) * v;
            gr *= (0.20 + (0.84 + shimmer) * hot) * v;
            b *= (0.22 + (0.80 + shimmer) * hot) * v;
          default: // lava
            final a = aux[i];
            // How much of this point is fresh lava: all of it behind the
            // advancing front, none ahead of it.
            final fresh = 1 - smoothstep(reveal - 0.03, reveal + 0.03, a);
            final d = (a - reveal) / 0.07;
            final front = reveal < 0.995 ? math.exp(-d * d) : 0.0;
            // Temperature, 0 (crust) to 1 (about 1,250 C). The front is the
            // hottest part, the middle of the flow hotter than its edges
            // (the model's own colour says how central a vertex is), and a
            // slow shimmer runs downhill.
            final central = gr;
            final shimmer = 0.04 * math.sin(a * 42 - clock * 5);
            final t =
                heat * fresh * (0.50 + 0.26 * central + 0.30 * front + shimmer);
            // Old flow: dark crust that still takes the light.
            final cr = 0.17 * lit, cg = 0.125 * lit, cb = 0.12 * lit;
            final glowR = _heatR(t), glowG = _heatG(t), glowB = _heatB(t);
            final w = smoothstep(0.0, 0.16, t);
            r = cr + (glowR - cr) * w;
            gr = cg + (glowG - cg) * w;
            b = cb + (glowB - cb) * w;
        }

        if (selection > 0) {
          if (part == selected) {
            final s = 1 + 0.10 * selection * pulse;
            r *= s;
            gr *= s;
            b *= s;
          } else {
            final grey = (0.30 * r + 0.59 * gr + 0.11 * b) * 0.55;
            final s = 0.72 * selection;
            r += (grey - r) * s;
            gr += (grey - gr) * s;
            b += (grey - b) * s;
          }
        }

        _argb[k * 3 + c] =
            alpha | (_channel(r) << 16) | (_channel(gr) << 8) | _channel(b);
        _xy[(k * 3 + c) * 2] = _sx[i];
        _xy[(k * 3 + c) * 2 + 1] = _sy[i];
      }
    }

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_xy, 0, count * 6),
      colors: Int32List.sublistView(_argb, 0, count * 3),
    );
    canvas.drawVertices(vertices, BlendMode.dst, _meshPaint);
    vertices.dispose();

    final unit = model.getMaxScaleOnAxis() * frame.projection.storage[5] * hh;
    _paintVentGlow(canvas, m, hw, hh, unit, glow * frame.opacity);
    _paintParticles(
      canvas,
      state.particles,
      m,
      hw,
      hh,
      unit,
      frame.opacity,
      glow,
    );
    if (state.labelsT > 0.01) {
      _paintLabels(
        canvas,
        size,
        state,
        m,
        hw,
        hh,
        camera,
        frame.opacity,
        labelStyle,
        labelInsets,
      );
    }
  }

  // Incandescence: the colour of rock by temperature, from a dull red near
  // 600 C through orange to pale yellow near 1,250 C. Input 0..1.
  static const List<double> _heatAt = [0.0, 0.22, 0.45, 0.68, 0.86, 1.0];
  static const List<double> _heatRed = [0.16, 0.42, 0.78, 0.95, 1.0, 1.0];
  static const List<double> _heatGreen = [0.11, 0.08, 0.20, 0.42, 0.70, 0.90];
  static const List<double> _heatBlue = [0.10, 0.06, 0.10, 0.11, 0.29, 0.66];

  static double _ramp(List<double> values, double t) {
    if (t <= 0) return values.first;
    for (var i = 1; i < _heatAt.length; i++) {
      if (t <= _heatAt[i]) {
        final u = (t - _heatAt[i - 1]) / (_heatAt[i] - _heatAt[i - 1]);
        return values[i - 1] + (values[i] - values[i - 1]) * u;
      }
    }
    return values.last;
  }

  static double _heatR(double t) => _ramp(_heatRed, t);
  static double _heatG(double t) => _ramp(_heatGreen, t);
  static double _heatB(double t) => _ramp(_heatBlue, t);

  /// The colour of rock at temperature [t] (0..1) with [alpha].
  static Color _heatColor(double t, double alpha) => Color.fromRGBO(
    (_heatR(t) * 255).round(),
    (_heatG(t) * 255).round(),
    (_heatB(t) * 255).round(),
    alpha.clamp(0.0, 1.0),
  );

  static int _channel(double v) =>
      v <= 0 ? 0 : (v >= 1 ? 255 : (v * 255).toInt());

  /// Projects a model-space point. Returns null behind the camera.
  static (double, double, double)? _project(
    Float64List m,
    double hw,
    double hh,
    double x,
    double y,
    double z,
  ) {
    final w = m[3] * x + m[7] * y + m[11] * z + m[15];
    if (w <= _near) return null;
    return (
      hw + (m[0] * x + m[4] * y + m[8] * z + m[12]) / w * hw,
      hh - (m[1] * x + m[5] * y + m[9] * z + m[13]) / w * hh,
      w,
    );
  }

  void _paintShadow(
    Canvas canvas,
    Float64List m,
    double hw,
    double hh,
    double opacity,
    double depth,
  ) {
    final g = geometry;
    final path = Path();
    const steps = 28;
    final radius = g.baseRadius * 1.1;
    var minX = double.infinity, maxX = -double.infinity;
    var started = false;
    for (var i = 0; i < steps; i++) {
      final a = 2 * math.pi * i / steps;
      final s = _project(
        m,
        hw,
        hh,
        radius * math.cos(a),
        -depth,
        radius * math.sin(a),
      );
      if (s == null) continue;
      if (!started) {
        started = true;
        path.moveTo(s.$1, s.$2);
      } else {
        path.lineTo(s.$1, s.$2);
      }
      minX = math.min(minX, s.$1);
      maxX = math.max(maxX, s.$1);
    }
    if (!started) return;
    path.close();
    final sigma = ((maxX - minX) * 0.035).clamp(1.5, 28.0);
    canvas.drawPath(
      path,
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, 0.34 * opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
    );
  }

  void _paintVentGlow(
    Canvas canvas,
    Float64List m,
    double hw,
    double hh,
    double unit,
    double glow,
  ) {
    if (glow < 0.02) return;
    final v = geometry.vent;
    final s = _project(m, hw, hh, v.x, v.y + 0.05, v.z);
    if (s == null) return;
    final radius = 0.55 * unit / s.$3;
    final center = Offset(s.$1, s.$2);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [
            Color.fromRGBO(255, 170, 70, 0.55 * glow),
            Color.fromRGBO(255, 90, 30, 0.18 * glow),
            const Color(0x00FF5A1E),
          ],
          const [0, 0.45, 1],
        ),
    );
  }

  static ui.Image _makePuff() {
    const d = 64.0;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, d, d),
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(d / 2, d / 2),
          d / 2,
          const [Color(0xFFFFFFFF), Color(0x99FFFFFF), Color(0x00FFFFFF)],
          const [0, 0.5, 1],
        ),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(d.toInt(), d.toInt());
    picture.dispose();
    return image;
  }

  void _paintParticles(
    Canvas canvas,
    Particles particles,
    Float64List m,
    double hw,
    double hh,
    double unit,
    double opacity,
    double glow,
  ) {
    final n = particles.capacity;
    final transforms = Float32List(n * 4);
    final rects = Float32List(n * 4);
    final colors = Int32List(n);
    var sprites = 0;
    final emberPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;

    for (var i = 0; i < n; i++) {
      final life = particles.life[i];
      if (life <= 0) continue;
      final q = i * 3;
      final x = particles.position[q],
          y = particles.position[q + 1],
          z = particles.position[q + 2];
      final s = _project(m, hw, hh, x, y, z);
      if (s == null) continue;
      final a = (particles.age[i] / life).clamp(0.0, 1.0);
      final kind = particles.kind[i];

      if (kind == Particles.ember) {
        final tail = _project(
          m,
          hw,
          hh,
          x - particles.velocity[q] * 0.11,
          y - particles.velocity[q + 1] * 0.11,
          z - particles.velocity[q + 2] * 0.11,
        );
        if (tail == null) continue;
        emberPaint
          ..strokeWidth = math.max(1.2, particles.size[i] * unit / s.$3)
          // A fragment cools in flight, along the same ramp as the lava.
          ..color = _heatColor(1 - 0.75 * a, (1 - a * a) * opacity);
        canvas.drawLine(
          Offset(tail.$1, tail.$2),
          Offset(s.$1, s.$2),
          emberPaint,
        );
        continue;
      }

      final diameter =
          particles.size[i] * (0.25 + 0.75 * math.sqrt(a)) * unit / s.$3;
      final scale = diameter / 64;
      transforms[sprites * 4] = scale;
      transforms[sprites * 4 + 1] = 0;
      transforms[sprites * 4 + 2] = s.$1 - scale * 32;
      transforms[sprites * 4 + 3] = s.$2 - scale * 32;
      rects[sprites * 4 + 2] = 64;
      rects[sprites * 4 + 3] = 64;
      Color color;
      double alpha;
      if (kind == Particles.ash) {
        final seconds = particles.age[i];
        // Ash leaves the vent incandescent and is dark within a quarter of
        // a second. After that it greys as it ages, and the underside of
        // the column is lit by the crater while it is still low.
        final hot = 1 - seconds / 0.28;
        if (hot > 0) {
          color = _heatColor(0.35 + 0.6 * hot, 1);
        } else {
          final under =
              (1 - (y - geometry.vent.y) / 0.5).clamp(0.0, 1.0) * 0.5 * glow;
          final grey = a < 0.5
              ? Color.lerp(
                  const Color(0xFF3C3432),
                  const Color(0xFF686260),
                  a * 2,
                )!
              : Color.lerp(
                  const Color(0xFF686260),
                  const Color(0xFF96928E),
                  a * 2 - 1,
                )!;
          color = Color.lerp(grey, const Color(0xFFFF823C), under)!;
        }
        alpha =
            math.min(seconds / 0.06, 1) * (1 - smoothstep(0.5, 1, a)) * 0.62;
      } else {
        color = const Color(0xFFE9E5DF);
        alpha = math.min(a / 0.2, 1) * (1 - smoothstep(0.4, 1, a)) * 0.20;
      }
      colors[sprites] = color.withValues(alpha: alpha * opacity).toARGB32();
      sprites++;
    }

    if (sprites == 0) return;
    canvas.drawRawAtlas(
      _puff ??= _makePuff(),
      Float32List.sublistView(transforms, 0, sprites * 4),
      Float32List.sublistView(rects, 0, sprites * 4),
      Int32List.sublistView(colors, 0, sprites),
      BlendMode.modulate,
      null,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  void _paintLabels(
    Canvas canvas,
    Size size,
    VolcanoController state,
    Float64List m,
    double hw,
    double hh,
    Vector3 camera,
    double opacity,
    TextStyle? style,
    EdgeInsets insets,
  ) {
    final g = geometry;
    style ??= const TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
    if (style != _labelStyle) {
      _labelStyle = style;
      for (final painter in _textPainters.values) {
        painter.dispose();
      }
      _textPainters.clear();
    }

    final centre = _project(m, hw, hh, 0, 0.2, 0);
    if (centre == null) return;
    final selected = state.selected;

    for (final part in VolcanoPart.values) {
      final anchor = g.anchors[part.index];
      final s = _project(m, hw, hh, anchor.x, anchor.y, anchor.z);
      if (s == null) continue;
      final toCamera = (camera - anchor)..normalize();
      var visible = smoothstep(
        0,
        0.18,
        toCamera.dot(g.anchorNormals[part.index]),
      );
      if (part.isInterior) visible *= smoothstep(0.5, 1, state.cutawayT);
      var alpha = visible * state.labelsT * opacity;
      if (alpha < 0.03) continue;
      final isSelected = selected == part;
      // Other pins step back while one is selected.
      if (selected != null && !isSelected) alpha *= 0.4;
      int a(double v) => (v * alpha * 255).round().clamp(0, 255);

      // The pin: a small numbered disc on the part itself.
      final pin = Offset(s.$1, s.$2);
      const radius = 10.0;
      _labelRects[part] = Rect.fromCircle(center: pin, radius: radius + 10);
      canvas.drawCircle(
        pin,
        radius,
        Paint()
          ..color = isSelected
              ? pinColor.withAlpha(a(1))
              : Color.fromARGB(a(0.62), 14, 18, 22),
      );
      canvas.drawCircle(
        pin,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = pinColor.withAlpha(a(1)),
      );
      final number = _text(part, true, isSelected, style);
      if (alpha > 0.9 || isSelected) {
        number.paint(canvas, pin - number.size.center(Offset.zero));
      } else {
        canvas.saveLayer(
          Rect.fromCircle(center: pin, radius: radius),
          Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
        );
        number.paint(canvas, pin - number.size.center(Offset.zero));
        canvas.restore();
      }

      // Only the selected part is named, beside its pin and with no box.
      if (!isSelected) continue;
      final name = _text(part, false, false, style);
      final right = s.$1 >= centre.$1;
      final minLeft = insets.left + 10;
      final maxLeft = math.max(
        minLeft,
        size.width - insets.right - 10 - name.width,
      );
      final left = (right ? pin.dx + 34 : pin.dx - 34 - name.width).clamp(
        minLeft,
        maxLeft,
      );
      final at = Offset(left, pin.dy - name.height / 2);
      canvas.drawLine(
        pin + Offset(right ? radius : -radius, 0),
        Offset(right ? left - 6 : left + name.width + 6, pin.dy),
        Paint()
          ..color = pinColor.withAlpha(a(0.9))
          ..strokeWidth = 1.1,
      );
      name.paint(canvas, at);
      _labelRects[part] = _labelRects[part]!.expandToInclude(
        (at & name.size).inflate(6),
      );
    }
  }

  /// Cached text for a pin: its number, or its name.
  TextPainter _text(
    VolcanoPart part,
    bool number,
    bool onPin,
    TextStyle style,
  ) {
    return _textPainters[(part, number, onPin ? 1 : 0)] ??= TextPainter(
      text: TextSpan(
        text: number ? '${part.index + 1}' : part.label,
        style: number
            ? style.copyWith(
                fontSize: 11,
                height: 1,
                color: onPin ? const Color(0xFF0E1216) : pinColor,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              )
            : style.copyWith(
                color: pinColor,
                shadows: const [
                  Shadow(color: Color(0xCC000000), blurRadius: 10),
                  Shadow(color: Color(0x80000000), blurRadius: 2),
                ],
              ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }
}
