import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:vulcanic/ar/marker_pose.dart';

void main() {
  const view = Size(400, 800);
  const focal = 620.0;

  /// Projects the unit marker under [pose] (image conventions: Y down, Z
  /// forward) to view pixels, the way a pinhole camera would.
  List<Offset> project(Matrix4 pose) => [
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

  /// A marker lying on a table, seen from above and in front.
  Matrix4 tablePose({double tilt = 55, double spin = 20, Vector3? at}) =>
      Matrix4.translation(at ?? Vector3(0.3, 0.6, 5))
        // Negative about X tips the top edge away, as on a table.
        ..rotateX(-tilt * math.pi / 180)
        ..rotateZ(spin * math.pi / 180);

  test('recovers position and orientation from four corners', () {
    final truth = tablePose();
    final anchor = MarkerPose.estimate(project(truth), view, focal)!;

    // Position: image space to OpenGL flips Y and Z.
    final t = truth.getTranslation();
    expect(anchor.getTranslation().x, closeTo(t.x, 1e-6));
    expect(anchor.getTranslation().y, closeTo(-t.y, 1e-6));
    expect(anchor.getTranslation().z, closeTo(-t.z, 1e-6));

    // The anchor's up axis is the marker's outward normal (-Z of the marker).
    final normal = truth.getRotation().transformed(Vector3(0, 0, -1));
    final up = anchor.getRotation().transformed(Vector3(0, 1, 0));
    expect(up.x, closeTo(normal.x, 1e-6));
    expect(up.y, closeTo(-normal.y, 1e-6));
    expect(up.z, closeTo(-normal.z, 1e-6));
  });

  test('the anchor is a proper rotation facing the camera', () {
    final anchor = MarkerPose.estimate(project(tablePose()), view, focal)!;
    final r = anchor.getRotation();
    expect(r.determinant(), closeTo(1, 1e-6));
    // A marker on a table shows its top face: the normal has a component
    // toward the camera (+Z in OpenGL camera space) and upward.
    final up = r.transformed(Vector3(0, 1, 0));
    expect(up.z, greaterThan(0));
    expect(up.y, greaterThan(0));
  });

  test('re-projecting through the matching projection hits the corners', () {
    final corners = project(tablePose(tilt: 40, spin: -35));
    final anchor = MarkerPose.estimate(corners, view, focal)!;
    final clip = MarkerPose.projection(view, focal) * anchor;
    // Model space on the anchor: X right, Z toward the bottom of the code.
    final model = const [
      [-0.5, -0.5],
      [0.5, -0.5],
      [0.5, 0.5],
      [-0.5, 0.5],
    ];
    for (var i = 0; i < 4; i++) {
      final p = clip.transformed(Vector4(model[i][0], 0, model[i][1], 1));
      final x = (p.x / p.w * 0.5 + 0.5) * view.width;
      final y = (0.5 - p.y / p.w * 0.5) * view.height;
      expect(x, closeTo(corners[i].dx, 1e-3));
      expect(y, closeTo(corners[i].dy, 1e-3));
    }
  });

  test('stays stable under a pixel of corner noise', () {
    final truth = tablePose();
    final clean = project(truth);
    final random = math.Random(3);
    for (var trial = 0; trial < 50; trial++) {
      final noisy = [
        for (final c in clean)
          c + Offset(random.nextDouble() * 2 - 1, random.nextDouble() * 2 - 1),
      ];
      final anchor = MarkerPose.estimate(noisy, view, focal)!;
      final t = truth.getTranslation();
      expect(anchor.getTranslation().z, closeTo(-t.z, 0.6));
      expect(anchor.getRotation().determinant(), closeTo(1, 1e-6));
    }
  });

  test('rejects degenerate input', () {
    expect(MarkerPose.estimate(const [Offset.zero], view, focal), isNull);
    expect(
      MarkerPose.estimate(List.filled(4, const Offset(10, 10)), view, focal),
      isNull,
    );
  });

  test('maps camera pixels to a cover-fitted view', () {
    // A 480x640 image shown on a 400x800 view is scaled 1.25x and cropped
    // by 100px on each side.
    const image = Size(480, 640);
    expect(MarkerPose.coverScale(image, view), 1.25);
    final mapped = MarkerPose.toView(
      const [Offset(240, 320), Offset(0, 0)],
      image,
      view,
    );
    expect(mapped[0], const Offset(200, 400));
    expect(mapped[1], const Offset(-100, 0));
  });

  group('MarkerTracker', () {
    final a = List.filled(4, const Offset(100, 100));
    final b = List.filled(4, const Offset(140, 100));

    test('eases toward new detections', () {
      final tracker = MarkerTracker()..report(a);
      expect(tracker.lost, isFalse);
      tracker.report(b);
      tracker.advance(1 / 60);
      expect(tracker.corners!.first.dx, inExclusiveRange(100, 140));
      for (var i = 0; i < 60; i++) {
        tracker
          ..report(b)
          ..advance(1 / 60);
      }
      expect(tracker.corners!.first.dx, closeTo(140, 0.01));
    });

    test('reports the marker lost, then snaps when it returns', () {
      final tracker = MarkerTracker()..report(a);
      for (var i = 0; i < 60; i++) {
        tracker.advance(1 / 60);
      }
      expect(tracker.lost, isTrue);
      tracker.report(b);
      expect(tracker.lost, isFalse);
      expect(tracker.corners!.first.dx, 140);
    });
  });
}
