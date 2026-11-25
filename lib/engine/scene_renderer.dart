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
  static const Color ember = Color(0xFFFF6A3D);

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
        0.007 * tremor * math.sin(clock * 71),
        0.004 * tremor * math.sin(clock * 93),
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
    final light = (frame.light ?? Vector3(-0.42, 0.74, 0.52)).normalized();
    final toModel = mv.getRotation()..transpose();
    final l = toModel.transformed(light)..normalize();
    final lx = l.x, ly = l.y, lz = l.z;

    final hw = size.width / 2, hh = size.height / 2;
    final m = mvp.storage;

    if (frame.shadow) _paintShadow(canvas, m, hw, hh, frame.opacity);

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
        final ny = nrm[j + 1];
        var ndl = nrm[j] * lx + ny * ly + nrm[j + 2] * lz;
        if (ndl < 0) ndl = 0;
        final lit = (0.36 + 0.92 * ndl + 0.10 * (ny * 0.5 + 0.5)) * exposure;

        switch (role) {
          case 0: // rock
            r *= lit;
            gr *= lit;
            b *= lit;
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
            final hot =
                heat * (1 - smoothstep(reveal - 0.03, reveal + 0.03, a));
            final d = (a - reveal) / 0.05;
            final front = reveal < 0.995 ? heat * math.exp(-d * d) : 0.0;
            final flow = 0.92 + 0.08 * math.sin(a * 42 - clock * 5);
            // Old flow: dark crust that still takes the light.
            final cr = 0.19 * lit + 0.05 * r;
            final cg = 0.14 * lit + 0.02 * gr;
            final cb = 0.13 * lit;
            r = cr + (r * flow - cr) * hot + 0.25 * front;
            gr = cg + (gr * flow - cg) * hot + 0.20 * front;
            b = cb + (b * flow - cb) * hot + 0.10 * front;
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
    _paintParticles(canvas, state.particles, m, hw, hh, unit, frame.opacity);
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
      );
    }
  }

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
        -g.blockDepth,
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
          x - particles.velocity[q] * 0.07,
          y - particles.velocity[q + 1] * 0.07,
          z - particles.velocity[q + 2] * 0.07,
        );
        if (tail == null) continue;
        emberPaint
          ..strokeWidth = math.max(1.2, particles.size[i] * unit / s.$3)
          ..color = Color.lerp(
            const Color(0xFFFFF1B0),
            const Color(0xFFFF5A1F),
            a,
          )!.withValues(alpha: (1 - a * a) * opacity);
        canvas.drawLine(
          Offset(tail.$1, tail.$2),
          Offset(s.$1, s.$2),
          emberPaint,
        );
        continue;
      }

      final diameter =
          particles.size[i] * (0.35 + 0.65 * math.sqrt(a)) * unit / s.$3;
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
        color = a < 0.12
            ? Color.lerp(
                const Color(0xFFFFB060),
                const Color(0xFF5A4640),
                a / 0.12,
              )!
            : Color.lerp(
                const Color(0xFF4A403C),
                const Color(0xFF8D8782),
                (a - 0.12) / 0.88,
              )!;
        alpha = math.min(a / 0.08, 1) * (1 - smoothstep(0.55, 1, a)) * 0.66;
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
  ) {
    final g = geometry;
    style ??= const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600);
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
    final placed = <Rect>[];

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
      // Unselected labels step back while a part is selected.
      final dimmed = selected != null && !isSelected;
      if (dimmed) alpha *= _dimmedLabel;

      final variant = isSelected ? 2 : (dimmed ? 1 : 0);
      final number = _text(part, true, variant, style);
      final name = _text(part, false, variant, style);
      final side = s.$1 >= centre.$1 ? 1.0 : -1.0;
      final dot = Offset(s.$1, s.$2);
      const height = 30.0;
      final width = 12 + number.width + 7 + name.width + 13;
      var left = side > 0 ? dot.dx + 26 : dot.dx - 26 - width;
      left = left.clamp(8.0, math.max(8.0, size.width - width - 8));
      var pill = Rect.fromLTWH(left, dot.dy - 22 - height / 2, width, height);
      // Nudge down past labels that are already placed.
      for (var tries = 0; tries < 4; tries++) {
        final hit = placed.where((r) => r.inflate(4).overlaps(pill));
        if (hit.isEmpty) break;
        pill = pill.shift(Offset(0, hit.first.bottom + 6 - pill.top));
      }
      placed.add(pill);
      _labelRects[part] = pill.expandToInclude(
        Rect.fromCircle(center: dot, radius: 14),
      );

      // Painters carry their own colour, so a label only needs a layer while
      // it is fading.
      final settled = dimmed ? _dimmedLabel : 1.0;
      final fading = (alpha - settled).abs() > 0.02;
      final base = fading ? settled : alpha;
      if (fading) {
        canvas.saveLayer(
          _labelRects[part]!.inflate(4),
          Paint()..color = Color.fromRGBO(0, 0, 0, alpha / settled),
        );
      }
      int a(double v) => (v * base * 255).round().clamp(0, 255);

      final attach = Offset(side > 0 ? pill.left : pill.right, pill.center.dy);
      canvas.drawLine(
        dot,
        attach,
        Paint()
          ..color = Color.fromARGB(a(0.7), 255, 255, 255)
          ..strokeWidth = 1.1,
      );
      canvas.drawCircle(
        dot,
        5.5,
        Paint()..color = Color.fromARGB(a(0.28), 255, 255, 255),
      );
      canvas.drawCircle(
        dot,
        2.6,
        Paint()
          ..color = isSelected
              ? ember.withAlpha(a(1))
              : Color.fromARGB(a(1), 255, 255, 255),
      );

      final shape = RRect.fromRectAndRadius(
        pill,
        const Radius.circular(height),
      );
      canvas.drawRRect(
        shape,
        Paint()
          ..color = isSelected
              ? ember.withAlpha(a(1))
              : Color.fromARGB(a(0.84), 16, 17, 20),
      );
      if (!isSelected) {
        canvas.drawRRect(
          shape.deflate(0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Color.fromARGB(a(0.16), 255, 255, 255),
        );
      }
      final baseline = pill.top + (height - number.height) / 2;
      number.paint(canvas, Offset(pill.left + 12, baseline));
      name.paint(canvas, Offset(pill.left + 12 + number.width + 7, baseline));
      if (fading) canvas.restore();
    }
  }

  static const double _dimmedLabel = 0.45;

  /// Cached text for a label. [variant] is 0 normal, 1 dimmed, 2 selected.
  TextPainter _text(
    VolcanoPart part,
    bool number,
    int variant,
    TextStyle style,
  ) {
    return _textPainters[(part, number, variant)] ??= () {
      final Color color = switch (variant) {
        2 => const Color(0xFF1A0E08),
        1 => (number ? ember : const Color(0xFFFFFFFF)).withValues(
          alpha: _dimmedLabel,
        ),
        _ => number ? ember : const Color(0xFFFFFFFF),
      };
      return TextPainter(
        text: TextSpan(
          text: number ? part.number : part.label,
          style: style.copyWith(
            color: color,
            fontFeatures: number
                ? const [ui.FontFeature.tabularFigures()]
                : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }();
  }
}
