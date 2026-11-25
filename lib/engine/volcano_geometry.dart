import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart';

import 'obj_mesh.dart';

/// The five modeled components of the volcano.
enum VolcanoPart {
  cone('cone', 'Volcanic cone', 106),
  terrain('terrain', 'Rock layers', 160),
  chamber('chamber', 'Magma chamber', 45),
  conduit('conduit', 'Main conduit', 45),
  lava('lava', 'Lava flow', 133);

  const VolcanoPart(this.asset, this.label, this.azimuthDegrees);

  /// File name (without extension) under assets/models/.
  final String asset;
  final String label;

  /// Direction, around the vertical axis, from which the part is best
  /// seen. Its label is anchored on that side and the view turns to it.
  final double azimuthDegrees;

  double get azimuth => azimuthDegrees * math.pi / 180;

  /// Two digit display number, "01" to "05".
  String get number => (index + 1).toString().padLeft(2, '0');

  /// Parts that sit underground and only show through the cutaway.
  bool get isInterior => this == chamber || this == conduit;
}

/// How a triangle is shaded and when it is visible.
enum FaceRole {
  /// Lit exterior rock.
  rock,

  /// Cut face revealed by the cutaway.
  section,

  /// Crater wall and floor, glows while erupting.
  crater,

  /// Magma chamber.
  magma,

  /// Conduit, fills with magma from the bottom up.
  conduit,

  /// Lava flow, advances from the crater outward.
  lava,
}

/// The assembled volcano: one triangle soup with per-triangle metadata.
class VolcanoGeometry {
  VolcanoGeometry._({
    required this.positions,
    required this.normals,
    required this.colors,
    required this.aux,
    required this.parts,
    required this.roles,
    required this.quadrants,
    required this.vent,
    required this.blockDepth,
    required this.baseRadius,
    required this.anchors,
    required this.anchorNormals,
  });

  /// The quadrant (x > 0, z > 0) that the cutaway opens.
  static const int notchQuadrant = 3;

  final Float32List positions; // xyz per corner
  final Float32List normals; // xyz per corner
  final Float32List colors; // rgb per corner
  /// Per corner animation parameter: distance along the flow for lava,
  /// height fraction for the conduit, zero elsewhere.
  final Float32List aux;
  final Uint8List parts; // VolcanoPart index per triangle
  final Uint8List roles; // FaceRole index per triangle
  final Uint8List quadrants; // bit 0: x > 0, bit 1: z > 0

  /// Where ash and lava leave the crater, in model space.
  final Vector3 vent;

  /// How far the rock block extends below the ground surface (y = 0).
  final double blockDepth;
  final double baseRadius;

  /// Label anchor per part and the direction it faces, in model space.
  final List<Vector3> anchors;
  final List<Vector3> anchorNormals;

  int get triangleCount => parts.length;

  static Future<VolcanoGeometry> load([AssetBundle? bundle]) async {
    bundle ??= rootBundle;
    final sources = <VolcanoPart, String>{};
    for (final part in VolcanoPart.values) {
      sources[part] = await bundle.loadString(
        'assets/models/${part.asset}.obj',
      );
    }
    return VolcanoGeometry.fromSources(sources);
  }

  factory VolcanoGeometry.fromSources(Map<VolcanoPart, String> sources) {
    final meshes = {
      for (final part in VolcanoPart.values)
        part: ObjMesh.parse(sources[part]!, fallbackColor: _fallbackColor),
    };
    final total = meshes.values.fold<int>(0, (sum, m) => sum + m.triangleCount);
    final positions = Float32List(total * 9);
    final normals = Float32List(total * 9);
    final colors = Float32List(total * 9);
    final aux = Float32List(total * 3);
    final parts = Uint8List(total);
    final roles = Uint8List(total);
    final quadrants = Uint8List(total);

    var peak = 0.0, depth = 0.0, radius = 0.0;
    var t = 0;
    for (final part in VolcanoPart.values) {
      final mesh = meshes[part]!;
      final p = mesh.positions;
      positions.setRange(t * 9, (t + mesh.triangleCount) * 9, p);
      normals.setRange(t * 9, (t + mesh.triangleCount) * 9, mesh.normals);
      colors.setRange(t * 9, (t + mesh.triangleCount) * 9, mesh.colors);

      // Extents used to normalise the animation parameter.
      var minR = double.infinity, maxR = 0.0;
      var minY = double.infinity, maxY = -double.infinity;
      for (var i = 0; i < p.length; i += 3) {
        final r = math.sqrt(p[i] * p[i] + p[i + 2] * p[i + 2]);
        minR = math.min(minR, r);
        maxR = math.max(maxR, r);
        minY = math.min(minY, p[i + 1]);
        maxY = math.max(maxY, p[i + 1]);
      }
      if (part == VolcanoPart.cone) peak = maxY;
      if (part == VolcanoPart.terrain) {
        depth = -minY;
        radius = maxR;
      }

      for (var k = 0; k < mesh.triangleCount; k++, t++) {
        parts[t] = part.index;
        roles[t] = _roleFor(part, mesh.materialNames[mesh.materials[k]]).index;
        var cx = 0.0, cz = 0.0;
        for (var c = 0; c < 3; c++) {
          final i = (k * 3 + c) * 3;
          cx += p[i];
          cz += p[i + 2];
          if (part == VolcanoPart.lava) {
            final r = math.sqrt(p[i] * p[i] + p[i + 2] * p[i + 2]);
            aux[t * 3 + c] = (r - minR) / math.max(1e-6, maxR - minR);
          } else if (part == VolcanoPart.conduit) {
            aux[t * 3 + c] = (p[i + 1] - minY) / math.max(1e-6, maxY - minY);
          }
        }
        quadrants[t] = (cx > 0 ? 1 : 0) | (cz > 0 ? 2 : 0);
      }
    }

    Vector3 polar(double r, double degrees, double y) {
      final a = degrees * math.pi / 180;
      return Vector3(r * math.cos(a), y, r * math.sin(a));
    }

    return VolcanoGeometry._(
      positions: positions,
      normals: normals,
      colors: colors,
      aux: aux,
      parts: parts,
      roles: roles,
      quadrants: quadrants,
      vent: Vector3(0, peak - 0.07, 0),
      blockDepth: depth,
      baseRadius: radius,
      anchors: [
        polar(0.40, VolcanoPart.cone.azimuthDegrees, peak * 0.50),
        polar(radius, VolcanoPart.terrain.azimuthDegrees, -depth * 0.55),
        polar(0.30, VolcanoPart.chamber.azimuthDegrees, -depth * 0.60),
        polar(0.05, VolcanoPart.conduit.azimuthDegrees, peak * 0.42),
        polar(0.62, VolcanoPart.lava.azimuthDegrees, peak * 0.12),
      ],
      anchorNormals: [
        polar(1, 106, 0.8)..normalize(),
        polar(1, 160, 0),
        polar(1, 45, 0.3)..normalize(),
        polar(1, 45, 0.2)..normalize(),
        polar(1, 133, 0.9)..normalize(),
      ],
    );
  }

  static FaceRole _roleFor(VolcanoPart part, String material) {
    if (material.contains('section')) return FaceRole.section;
    if (material.contains('crater')) return FaceRole.crater;
    return switch (part) {
      VolcanoPart.cone || VolcanoPart.terrain => FaceRole.rock,
      VolcanoPart.chamber => FaceRole.magma,
      VolcanoPart.conduit => FaceRole.conduit,
      VolcanoPart.lava => FaceRole.lava,
    };
  }

  /// Colour for vertices that carry none, e.g. after a Blender re-export.
  static List<double> _fallbackColor(String material) {
    if (material.contains('magma')) return const [0.95, 0.42, 0.11];
    if (material.contains('conduit')) return const [1.0, 0.48, 0.12];
    if (material.contains('lava')) return const [1.0, 0.48, 0.12];
    if (material.contains('crater')) return const [0.15, 0.11, 0.10];
    if (material.contains('section')) return const [0.44, 0.37, 0.31];
    return const [0.39, 0.34, 0.28];
  }
}
