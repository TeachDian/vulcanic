import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../engine/scene_frame.dart';

/// Rotation about the anchor's vertical axis that turns the volcano's front
/// toward the camera.
///
/// [anchor] is the pose the model stands on and [view] the camera's
/// world-to-camera matrix.
double facingYaw(Matrix4 anchor, Matrix4 view) {
  final camera = Matrix4.inverted(view).getTranslation();
  final local = Matrix4.inverted(anchor).transform3(camera);
  // A rotation of r about +Y moves azimuth a to a - r.
  return kFrontAzimuth - math.atan2(local.z, local.x);
}

/// A fixed virtual camera for phones without motion tracking.
///
/// With no way to sense the room, the app assumes a typical pose: the phone
/// held a little above a table and tilted down toward it. A tap is then a
/// ray from that camera, and the model stands where the ray meets the
/// assumed table. The result is placed on the screen rather than anchored
/// in the world: it does not stay put when the phone moves.
class ScreenPlacementCamera {
  const ScreenPlacementCamera({
    this.height = 0.50,
    this.pitch = 36 * math.pi / 180,
    this.fieldOfView = 60 * math.pi / 180,
    this.maxReach = 1.5,
  });

  /// Assumed height of the phone above the surface, in metres.
  final double height;

  /// Assumed downward tilt of the phone, in radians.
  final double pitch;

  /// Vertical field of view, in radians.
  final double fieldOfView;

  /// Farthest a tap can place the model, in metres along the ground.
  final double maxReach;

  Vector3 get _eye => Vector3(0, height, 0);

  Vector3 get _forward => Vector3(0, -math.sin(pitch), -math.cos(pitch));

  Matrix4 get view => makeViewMatrix(_eye, _eye + _forward, Vector3(0, 1, 0));

  Matrix4 projection(Size size) =>
      makePerspectiveMatrix(fieldOfView, size.width / size.height, 0.05, 60);

  /// The point on the assumed surface (y = 0) under screen position [tap].
  Vector3 groundPoint(Offset tap, Size size) {
    final t = math.tan(fieldOfView / 2);
    final x = (tap.dx / size.width * 2 - 1) * t * size.width / size.height;
    final y = (1 - tap.dy / size.height * 2) * t;
    // Camera basis in world space.
    final forward = _forward;
    final right = Vector3(1, 0, 0);
    final up = right.cross(forward);
    final ray = (forward + right * x + up * y)..normalize();

    final horizontal = Vector3(ray.x, 0, ray.z);
    if (ray.y < -1e-3) {
      final hit = _eye + ray * (-height / ray.y);
      final reach = math.sqrt(hit.x * hit.x + hit.z * hit.z);
      if (reach <= maxReach) return Vector3(hit.x, 0, hit.z);
    }
    // At or above the horizon, or too far: stop at the farthest reach.
    horizontal.normalize();
    return horizontal * maxReach;
  }
}
