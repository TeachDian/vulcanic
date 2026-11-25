import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

/// The side of the volcano that faces the viewer when nothing has turned it:
/// between the cutaway and the lava flow. An azimuth, measured from +X
/// toward +Z.
const double kFrontAzimuth = 78 * math.pi / 180;

/// Everything the renderer needs to draw one frame: where the camera is,
/// how it projects, and where the volcano stands.
///
/// All three matrices use OpenGL conventions (right handed, camera looking
/// down -Z, Y up), which is also what ARCore reports.
class SceneFrame {
  const SceneFrame({
    required this.view,
    required this.projection,
    required this.model,
    this.opacity = 1,
    this.exposure = 1,
    this.light,
    this.shadow = true,
  });

  /// World to camera.
  final Matrix4 view;

  /// Camera to clip space.
  final Matrix4 projection;

  /// Model to world.
  final Matrix4 model;

  /// Overall opacity, used to fade the model in and out.
  final double opacity;

  /// Brightness multiplier for lit surfaces (AR light estimate).
  final double exposure;

  /// Direction toward the light, in view space, so the lit side always
  /// faces the viewer. Defaults to high front-left.
  final Vector3? light;

  /// Whether to draw the soft contact shadow under the model.
  final bool shadow;
}

/// Builds the model matrix that stands the volcano on an anchor.
///
/// [anchor] is a pose whose +Y axis is the surface normal. The model's rock
/// block extends [blockDepth] below its own ground level, so it is lifted to
/// rest on the surface. [width] is the diameter of the base in world units.
Matrix4 placeVolcano({
  required Matrix4 anchor,
  required double width,
  required double blockDepth,
  double rotation = 0,
  double scale = 1,
}) {
  final s = width / 2 * scale; // the model's base radius is one unit
  return anchor.clone()
    ..rotateY(rotation)
    ..scaleByDouble(s, s, s, 1)
    ..translateByDouble(0, blockDepth, 0, 1);
}

/// An orbiting camera for the 3D explorer and for previews.
class OrbitCamera {
  OrbitCamera({
    this.azimuth = 78 * math.pi / 180,
    this.elevation = 22 * math.pi / 180,
    this.distance = 4.6,
    Vector3? target,
    this.fieldOfView = 36 * math.pi / 180,
  }) : target = target ?? Vector3(0, 0.08, 0);

  /// Angle around the vertical axis, measured from +X toward +Z.
  double azimuth;

  /// Angle above the horizon, in radians.
  double elevation;
  double distance;
  Vector3 target;

  /// Vertical field of view, in radians.
  double fieldOfView;

  static const double minElevation = 4 * math.pi / 180;
  static const double maxElevation = 80 * math.pi / 180;

  void orbit(double dAzimuth, double dElevation) {
    azimuth += dAzimuth;
    elevation = (elevation + dElevation).clamp(minElevation, maxElevation);
  }

  Vector3 get eye => Vector3(
    target.x + distance * math.cos(elevation) * math.cos(azimuth),
    target.y + distance * math.sin(elevation),
    target.z + distance * math.cos(elevation) * math.sin(azimuth),
  );

  Matrix4 get view => makeViewMatrix(eye, target, Vector3(0, 1, 0));

  /// Distance at which a sphere of [radius] around the target just fits a
  /// viewport of [size], whichever dimension is the tighter one.
  double distanceToFit(Size size, {required double radius}) {
    final vertical = fieldOfView / 2;
    final horizontal = math.atan(math.tan(vertical) * size.width / size.height);
    return radius / math.sin(math.min(vertical, horizontal));
  }

  Matrix4 projection(Size size) =>
      makePerspectiveMatrix(fieldOfView, size.width / size.height, 0.05, 100);

  SceneFrame frame(Size size, {Matrix4? model, double opacity = 1}) =>
      SceneFrame(
        view: view,
        projection: projection(size),
        model: model ?? Matrix4.identity(),
        opacity: opacity,
      );
}
