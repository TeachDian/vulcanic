import 'dart:math' as math;
import 'dart:typed_data';

/// A triangle soup parsed from a Wavefront OBJ file.
///
/// Every triangle owns three corners, so positions, normals and colours are
/// stored per corner (nine floats per triangle). That is the layout the
/// painter needs and it keeps flat and smooth shading uniform.
class ObjMesh {
  ObjMesh({
    required this.positions,
    required this.normals,
    required this.colors,
    required this.materials,
    required this.materialNames,
  });

  /// xyz per corner.
  final Float32List positions;

  /// Unit normal per corner.
  final Float32List normals;

  /// Linear rgb (0..1) per corner.
  final Float32List colors;

  /// Index into [materialNames] per triangle.
  final Uint8List materials;

  final List<String> materialNames;

  int get triangleCount => materials.length;

  /// Parses OBJ text.
  ///
  /// Understands `v` with optional vertex colours, `vn`, `usemtl` and `f`
  /// with any of the `v`, `v/vt`, `v//vn`, `v/vt/vn` forms. Polygons are fan
  /// triangulated, missing normals fall back to the face normal, and
  /// vertices without a colour use [fallbackColor] for their material.
  static ObjMesh parse(
    String source, {
    List<double> Function(String material)? fallbackColor,
  }) {
    final v = <double>[]; // xyz
    final vc = <double>[]; // rgb, NaN when absent
    final vn = <double>[];
    final outPos = <double>[];
    final outNrm = <double>[];
    final outCol = <double>[];
    final outMat = <int>[];
    final names = <String>[];
    var material = 0;
    var hasMaterial = false;

    int resolve(String token, int count) {
      final i = int.parse(token);
      return i < 0 ? count + i : i - 1;
    }

    for (final raw in source.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      switch (parts[0]) {
        case 'v':
          v
            ..add(double.parse(parts[1]))
            ..add(double.parse(parts[2]))
            ..add(double.parse(parts[3]));
          if (parts.length >= 7) {
            vc
              ..add(double.parse(parts[4]))
              ..add(double.parse(parts[5]))
              ..add(double.parse(parts[6]));
          } else {
            vc
              ..add(double.nan)
              ..add(double.nan)
              ..add(double.nan);
          }
        case 'vn':
          vn
            ..add(double.parse(parts[1]))
            ..add(double.parse(parts[2]))
            ..add(double.parse(parts[3]));
        case 'usemtl':
          final name = parts.length > 1 ? parts[1] : 'default';
          var index = names.indexOf(name);
          if (index < 0) {
            names.add(name);
            index = names.length - 1;
          }
          material = index;
          hasMaterial = true;
        case 'f':
          if (!hasMaterial) {
            names.add('default');
            material = names.length - 1;
            hasMaterial = true;
          }
          final vi = <int>[], ni = <int>[];
          for (var k = 1; k < parts.length; k++) {
            final ref = parts[k].split('/');
            vi.add(resolve(ref[0], v.length ~/ 3));
            ni.add(
              ref.length > 2 && ref[2].isNotEmpty
                  ? resolve(ref[2], vn.length ~/ 3)
                  : -1,
            );
          }
          final fallback =
              fallbackColor?.call(names[material]) ?? const [0.6, 0.6, 0.6];
          for (var k = 1; k < vi.length - 1; k++) {
            final corners = [0, k, k + 1];
            // Face normal for corners that do not reference one.
            final a = vi[corners[0]] * 3,
                b = vi[corners[1]] * 3,
                c = vi[corners[2]] * 3;
            final ux = v[b] - v[a], uy = v[b + 1] - v[a + 1];
            final uz = v[b + 2] - v[a + 2];
            final wx = v[c] - v[a], wy = v[c + 1] - v[a + 1];
            final wz = v[c + 2] - v[a + 2];
            var fx = uy * wz - uz * wy;
            var fy = uz * wx - ux * wz;
            var fz = ux * wy - uy * wx;
            final fl = math.sqrt(fx * fx + fy * fy + fz * fz);
            if (fl < 1e-12) continue; // degenerate
            fx /= fl;
            fy /= fl;
            fz /= fl;
            for (final corner in corners) {
              final p = vi[corner] * 3;
              outPos
                ..add(v[p])
                ..add(v[p + 1])
                ..add(v[p + 2]);
              final n = ni[corner];
              if (n >= 0) {
                final q = n * 3;
                final nl = math.sqrt(
                  vn[q] * vn[q] + vn[q + 1] * vn[q + 1] + vn[q + 2] * vn[q + 2],
                );
                final s = nl < 1e-12 ? 0.0 : 1 / nl;
                outNrm
                  ..add(vn[q] * s)
                  ..add(vn[q + 1] * s)
                  ..add(vn[q + 2] * s);
              } else {
                outNrm
                  ..add(fx)
                  ..add(fy)
                  ..add(fz);
              }
              if (vc[p].isNaN) {
                outCol.addAll(fallback);
              } else {
                outCol
                  ..add(vc[p])
                  ..add(vc[p + 1])
                  ..add(vc[p + 2]);
              }
            }
            outMat.add(material);
          }
      }
    }

    return ObjMesh(
      positions: Float32List.fromList(outPos),
      normals: Float32List.fromList(outNrm),
      colors: Float32List.fromList(outCol),
      materials: Uint8List.fromList(outMat),
      materialNames: names,
    );
  }
}
