import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:vulcanic/ar/gravity.dart';
import 'package:vulcanic/ar/marker_pose.dart';

void main() {
  const view = Size(400, 800);
  const focal = 620.0;
  const dt = 1 / 30;

  /// Corners of a marker lying on a table, as a camera looking down at it
  /// would see them (image conventions: Y down, Z forward).
  List<Offset> corners({double tilt = 55, Vector3? at}) {
    final pose = Matrix4.translation(at ?? Vector3(0.3, 0.6, 5))
      ..rotateX(-tilt * math.pi / 180)
      ..rotateZ(20 * math.pi / 180);
    return [
      for (final c in const [
        [-0.5, -0.5],
        [0.5, -0.5],
        [0.5, 0.5],
        [-0.5, 0.5],
      ])
        () {
          final p = pose.transform3(Vector3(c[0], c[1], 0));
          return Offset(
            view.width / 2 + focal * p.x / p.z,
            view.height / 2 + focal * p.y / p.z,
          );
        }(),
    ];
  }

  /// The corners with up to [pixels] of noise on each.
  List<Offset> noisy(List<Offset> clean, math.Random random, double pixels) => [
    for (final c in clean)
      c +
          Offset(
            (random.nextDouble() * 2 - 1) * pixels,
            (random.nextDouble() * 2 - 1) * pixels,
          ),
  ];

  /// Angle between the up axes of two poses, in degrees.
  double tiltBetween(Matrix4 a, Matrix4 b) {
    final d = a
        .getColumn(1)
        .xyz
        .normalized()
        .dot(b.getColumn(1).xyz.normalized());
    return math.acos(d.clamp(-1.0, 1.0)) * 180 / math.pi;
  }

  /// How far the top of a model stood on [poses] wanders on screen, in
  /// pixels. This is the trembling a viewer sees.
  double wander(List<Matrix4> poses) {
    final projection = MarkerPose.projection(view, focal);
    final tops = [
      for (final p in poses)
        () {
          final c = (projection * p).transformed(Vector4(0, 1, 0, 1));
          return Offset(
            (c.x / c.w * 0.5 + 0.5) * view.width,
            (0.5 - c.y / c.w * 0.5) * view.height,
          );
        }(),
    ];
    final mean = tops.reduce((a, b) => a + b) / tops.length.toDouble();
    return tops.map((t) => (t - mean).distance).reduce(math.max);
  }

  // Up, in camera space, for a table seen at a 55 degree tilt: the true
  // normal of the marker in the scene above.
  final truth = MarkerPose.estimate(corners(), view, focal)!;
  final up = truth.getColumn(1).xyz.normalized();

  test('a still marker gives a still model', () {
    final random = math.Random(11);
    final clean = corners();
    final stabilizer = MarkerStabilizer();
    final raw = <Matrix4>[], steady = <Matrix4>[];
    for (var i = 0; i < 120; i++) {
      final pose = MarkerPose.estimate(noisy(clean, random, 1.2), view, focal)!;
      final out = stabilizer.update(pose, up: up, dt: dt);
      if (i >= 30) {
        raw.add(pose);
        steady.add(out);
      }
    }
    // The raw pose visibly trembles; the steadied one barely moves.
    expect(wander(raw), greaterThan(8));
    expect(wander(steady), lessThan(wander(raw) / 5));
  });

  test('with gravity the model is exactly level', () {
    final random = math.Random(5);
    final stabilizer = MarkerStabilizer();
    late Matrix4 out;
    for (var i = 0; i < 40; i++) {
      final pose = MarkerPose.estimate(
        noisy(corners(), random, 1.5),
        view,
        focal,
      )!;
      out = stabilizer.update(pose, up: up, dt: dt);
      expect(out.getColumn(1).xyz.dot(up), closeTo(1, 1e-9));
    }
    expect(out.getRotation().determinant(), closeTo(1, 1e-9));
  });

  test('without gravity the tilt is smoothed, not frozen', () {
    final random = math.Random(8);
    final stabilizer = MarkerStabilizer();
    var worstRaw = 0.0, worstSteady = 0.0;
    for (var i = 0; i < 120; i++) {
      final pose = MarkerPose.estimate(
        noisy(corners(), random, 1.2),
        view,
        focal,
      )!;
      final out = stabilizer.update(pose, dt: dt);
      if (i >= 45) {
        worstRaw = math.max(worstRaw, tiltBetween(pose, truth));
        worstSteady = math.max(worstSteady, tiltBetween(out, truth));
      }
    }
    expect(worstSteady, lessThan(worstRaw / 2));
  });

  test('a marker that is not level is not forced level', () {
    // "Up" here is far from the marker's normal, as for a marker on a wall.
    final wallUp = Vector3(0, 1, 0);
    expect(
      math.acos(wallUp.dot(up)),
      greaterThan(MarkerStabilizer.levelWithin),
    );
    final stabilizer = MarkerStabilizer();
    late Matrix4 out;
    for (var i = 0; i < 30; i++) {
      out = stabilizer.update(truth, up: wallUp, dt: dt);
    }
    expect(tiltBetween(out, truth), lessThan(0.5));
  });

  test('a moving marker is followed closely', () {
    final stabilizer = MarkerStabilizer();
    // Settle, then slide the marker steadily to one side.
    for (var i = 0; i < 30; i++) {
      stabilizer.update(truth, up: up, dt: dt);
    }
    late Matrix4 out, target;
    for (var i = 1; i <= 30; i++) {
      target = MarkerPose.estimate(
        corners(at: Vector3(0.3 + 0.08 * i, 0.6, 5)),
        view,
        focal,
      )!;
      out = stabilizer.update(target, up: up, dt: dt);
    }
    final lag = (out.getTranslation() - target.getTranslation()).length;
    // Moving 2.4 marker widths a second, it trails by a fraction of one.
    expect(lag, lessThan(0.25));
  });

  test('reset takes the next pose as it comes', () {
    final stabilizer = MarkerStabilizer();
    stabilizer.update(truth, up: up, dt: dt);
    final far = MarkerPose.estimate(
      corners(at: Vector3(-1.5, 0.2, 7)),
      view,
      focal,
    )!;
    stabilizer.reset();
    expect(stabilizer.hasPose, isFalse);
    final out = stabilizer.update(far, up: up, dt: dt);
    expect(
      (out.getTranslation() - far.getTranslation()).length,
      lessThan(1e-9),
    );
  });

  group('GravitySensor', () {
    test('normalises and smooths readings', () {
      final sensor = GravitySensor();
      expect(sensor.up, isNull);
      final start = DateTime(2026);
      sensor.report(Vector3(0, 9.81, 0), start);
      expect(sensor.up!.y, closeTo(1, 1e-9));

      // A sudden jolt barely moves it; a sustained tilt wins.
      sensor.report(
        Vector3(9.81, 0, 0),
        start.add(const Duration(milliseconds: 20)),
      );
      expect(sensor.up!.y, greaterThan(0.95));
      for (var i = 2; i < 60; i++) {
        sensor.report(
          Vector3(9.81, 0, 0),
          start.add(Duration(milliseconds: 20 * i)),
        );
      }
      expect(sensor.up!.x, greaterThan(0.99));
      expect(sensor.up!.length, closeTo(1, 1e-9));
    });

    test('ignores an empty reading', () {
      final sensor = GravitySensor()..report(Vector3.zero(), DateTime(2026));
      expect(sensor.up, isNull);
    });
  });
}
