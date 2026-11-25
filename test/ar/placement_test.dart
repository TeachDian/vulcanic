import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:vulcanic/ar/placement.dart';
import 'package:vulcanic/engine/scene_frame.dart';

void main() {
  const size = Size(400, 800);
  const camera = ScreenPlacementCamera();

  Offset project(Vector3 world) {
    final clip = (camera.projection(size) * camera.view).transformed(
      Vector4(world.x, world.y, world.z, 1),
    );
    return Offset(
      (clip.x / clip.w * 0.5 + 0.5) * size.width,
      (0.5 - clip.y / clip.w * 0.5) * size.height,
    );
  }

  group('ScreenPlacementCamera', () {
    test('a tap lands on the surface under the finger', () {
      for (final tap in const [
        Offset(200, 400),
        Offset(90, 620),
        Offset(330, 500),
      ]) {
        final point = camera.groundPoint(tap, size);
        expect(point.y, 0);
        final back = project(point);
        expect(back.dx, closeTo(tap.dx, 0.5));
        expect(back.dy, closeTo(tap.dy, 0.5));
      }
    });

    test('lower on the screen is nearer the viewer', () {
      final far = camera.groundPoint(const Offset(200, 300), size);
      final near = camera.groundPoint(const Offset(200, 700), size);
      expect(near.z, greaterThan(far.z));
      expect(near.z, lessThan(0), reason: 'still in front of the camera');
    });

    test('a tap above the horizon stops at the farthest reach', () {
      final point = camera.groundPoint(const Offset(200, 5), size);
      expect(point.y, 0);
      expect(point.length, closeTo(camera.maxReach, 1e-6));
      expect(point.z, lessThan(0));
    });
  });

  group('facingYaw', () {
    test('turns the front of the model toward the camera', () {
      // Camera south-east of the anchor, looking at it.
      final anchor = Matrix4.translation(Vector3(1, 0, -2));
      final eye = Vector3(2.5, 1.2, 0.5);
      final view = makeViewMatrix(eye, Vector3(1, 0, -2), Vector3(0, 1, 0));
      final yaw = facingYaw(anchor, view);

      final model = placeVolcano(
        anchor: anchor,
        width: 2,
        lift: 0,
        rotation: yaw,
      );
      final front = model.transform3(
        Vector3(math.cos(kFrontAzimuth), 0, math.sin(kFrontAzimuth)),
      );
      final toFront = (front - Vector3(1, 0, -2))..normalize();
      final toCamera = Vector3(eye.x - 1, 0, eye.z + 2)..normalize();
      expect(toFront.dot(toCamera), closeTo(1, 1e-6));
    });
  });

  test('placeVolcano rests the rock block on the anchor', () {
    final model = placeVolcano(
      anchor: Matrix4.translation(Vector3(0, 1, 0)),
      width: 0.4,
      lift: 0.56,
    );
    // The bottom of the block (y = -0.56 in model space) sits on the anchor.
    expect(model.transform3(Vector3(0, -0.56, 0)).y, closeTo(1, 1e-9));
    // The base radius of one model unit becomes half the requested width.
    expect(model.transform3(Vector3(1, -0.56, 0)).x, closeTo(0.2, 1e-9));
  });
}
