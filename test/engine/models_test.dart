import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vulcanic/engine/volcano_geometry.dart';

import '../../tool/forge_models.dart' as forge;

void main() {
  test('committed models match the forge', () {
    forge.forgeAll().forEach((name, text) {
      expect(
        File('assets/models/$name').readAsStringSync(),
        text,
        reason: '$name is stale: run `dart run tool/forge_models.dart`',
      );
    });
  });

  group('assembled volcano', () {
    final g = VolcanoGeometry.fromSources({
      for (final part in VolcanoPart.values)
        part: File('assets/models/${part.asset}.obj').readAsStringSync(),
    });

    test('has five substantial components', () {
      final counts = List.filled(VolcanoPart.values.length, 0);
      for (final part in g.parts) {
        counts[part]++;
      }
      for (final part in VolcanoPart.values) {
        expect(counts[part.index], greaterThan(200), reason: part.label);
      }
      expect(g.positions.every((v) => v.isFinite), isTrue);
      expect(g.normals.every((v) => v.isFinite), isTrue);
    });

    test('measures the model from its meshes', () {
      expect(g.blockDepth, closeTo(forge.kBlockDepth, 1e-3));
      expect(g.baseRadius, closeTo(forge.kBaseRadius, 1e-3));
      expect(g.vent.y, inInclusiveRange(0.6, 0.8));
    });

    test('no triangle straddles a quadrant plane', () {
      // The painter orders quadrants back to front, which only works if
      // every triangle sits wholly inside one of them.
      for (var t = 0; t < g.triangleCount; t++) {
        var minX = double.infinity, maxX = -double.infinity;
        var minZ = double.infinity, maxZ = -double.infinity;
        for (var c = 0; c < 3; c++) {
          final i = (t * 3 + c) * 3;
          minX = math.min(minX, g.positions[i]);
          maxX = math.max(maxX, g.positions[i]);
          minZ = math.min(minZ, g.positions[i + 2]);
          maxZ = math.max(maxZ, g.positions[i + 2]);
        }
        const eps = 1e-3;
        expect(minX > -eps || maxX < eps, isTrue, reason: 'triangle $t on x');
        expect(minZ > -eps || maxZ < eps, isTrue, reason: 'triangle $t on z');
      }
    });

    test('the cutaway has section faces and an interior to show', () {
      var sections = 0, interior = 0;
      for (var t = 0; t < g.triangleCount; t++) {
        if (g.roles[t] == FaceRole.section.index) {
          sections++;
          expect(
            g.quadrants[t],
            isNot(VolcanoGeometry.notchQuadrant),
            reason: 'section faces belong to the neighbouring quadrants',
          );
        }
        final part = VolcanoPart.values[g.parts[t]];
        if (part.isInterior &&
            g.quadrants[t] == VolcanoGeometry.notchQuadrant) {
          interior++;
        }
      }
      expect(sections, greaterThan(100));
      expect(interior, greaterThan(100));
    });

    test('lava and conduit carry a 0..1 animation parameter', () {
      for (var t = 0; t < g.triangleCount; t++) {
        final part = VolcanoPart.values[g.parts[t]];
        for (var c = 0; c < 3; c++) {
          final a = g.aux[t * 3 + c];
          expect(a, inInclusiveRange(0, 1));
          if (part != VolcanoPart.lava && part != VolcanoPart.conduit) {
            expect(a, 0);
          }
        }
      }
    });
  });
}
