import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

/// Marker-based tracking: where is the printed marker relative to the camera?
///
/// The scanner reports the four corners of the marker's code in the camera
/// image. Because the code is a flat square of known shape, those four
/// points are enough to recover its full 3D pose:
///
///  1. Fit the homography that maps the square onto its image.
///  2. Factor the homography into a rotation and a translation, using the
///     camera's focal length.
///
/// Distances come out in units of the code's side length, so the marker can
/// be printed at any size and the volcano scales with it.
abstract final class MarkerPose {
  /// Typical long-side field of view of a phone's main camera.
  static const double assumedFieldOfView = 67 * math.pi / 180;

  /// Focal length in view pixels for a preview that covers [view].
  ///
  /// [image] is the upright camera image the corners were measured in.
  static double focalLength(Size image, Size view) {
    final inImage =
        math.max(image.width, image.height) /
        2 /
        math.tan(assumedFieldOfView / 2);
    return inImage * coverScale(image, view);
  }

  /// Scale applied to the camera image so that it covers the view.
  static double coverScale(Size image, Size view) =>
      math.max(view.width / image.width, view.height / image.height);

  /// Maps corners from camera image pixels to view pixels, for a preview
  /// shown with `BoxFit.cover`.
  static List<Offset> toView(List<Offset> corners, Size image, Size view) {
    final scale = coverScale(image, view);
    final dx = (image.width * scale - view.width) / 2;
    final dy = (image.height * scale - view.height) / 2;
    return [
      for (final c in corners) Offset(c.dx * scale - dx, c.dy * scale - dy),
    ];
  }

  /// Perspective projection that matches [focal] with the principal point
  /// at the centre of [view].
  static Matrix4 projection(Size view, double focal) => makePerspectiveMatrix(
    2 * math.atan(view.height / 2 / focal),
    view.width / view.height,
    0.05,
    200,
  );

  /// Pose of the marker in camera space, as an anchor for the volcano.
  ///
  /// [corners] are the code's top-left, top-right, bottom-right and
  /// bottom-left in view pixels. The result uses OpenGL camera conventions
  /// (X right, Y up, camera looking down -Z), with its +Y axis along the
  /// marker's outward normal and its +Z axis toward the bottom of the code,
  /// so a model stood on it faces whoever is reading the marker.
  ///
  /// Returns null when the corners are degenerate.
  static Matrix4? estimate(List<Offset> corners, Size view, double focal) {
    if (corners.length != 4) return null;
    const square = [
      Offset(-0.5, -0.5),
      Offset(0.5, -0.5),
      Offset(0.5, 0.5),
      Offset(-0.5, 0.5),
    ];
    // Image points on the normalised image plane (focal length one).
    final cx = view.width / 2, cy = view.height / 2;
    final h = _homography(square, [
      for (final c in corners) Offset((c.dx - cx) / focal, (c.dy - cy) / focal),
    ]);
    if (h == null) return null;

    // H = [r1 r2 t] up to scale: its first two columns are the marker's X
    // and Y axes as the camera sees them.
    var r1 = Vector3(h[0], h[3], h[6]);
    var r2 = Vector3(h[1], h[4], h[7]);
    var t = Vector3(h[2], h[5], 1);
    final norm = (r1.length + r2.length) / 2;
    if (norm < 1e-9) return null;
    // The marker must be in front of the camera.
    final scale = (t.z < 0 ? -1 : 1) / norm;
    r1 = r1 * scale;
    r2 = r2 * scale;
    t = t * scale;

    // Noise leaves r1 and r2 slightly skewed; make them orthonormal.
    r1.normalize();
    r2 = (r2 - r1 * r2.dot(r1))..normalize();
    final r3 = r1.cross(r2);
    if (!r3.x.isFinite || !t.x.isFinite) return null;

    // Image space has Y down and Z forward; OpenGL has Y up and Z back.
    Vector3 gl(Vector3 v) => Vector3(v.x, -v.y, -v.z);
    final x = gl(r1); // model X: the marker's X
    final y = gl(-r3); // model Y: out of the marker
    final z = gl(r2); // model Z: toward the bottom of the code
    final p = gl(t);
    return Matrix4.columns(
      Vector4(x.x, x.y, x.z, 0),
      Vector4(y.x, y.y, y.z, 0),
      Vector4(z.x, z.y, z.z, 0),
      Vector4(p.x, p.y, p.z, 1),
    );
  }

  /// The 3x3 homography (row major, h33 = 1) taking each of [from] to [to].
  static List<double>? _homography(List<Offset> from, List<Offset> to) {
    // Eight equations in the eight unknowns h11..h32.
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final x = from[i].dx, y = from[i].dy;
      final u = to[i].dx, v = to[i].dy;
      a[i * 2] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
      a[i * 2 + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
    }
    // Gaussian elimination with partial pivoting.
    for (var col = 0; col < 8; col++) {
      var pivot = col;
      for (var row = col + 1; row < 8; row++) {
        if (a[row][col].abs() > a[pivot][col].abs()) pivot = row;
      }
      if (a[pivot][col].abs() < 1e-12) return null;
      final swap = a[col];
      a[col] = a[pivot];
      a[pivot] = swap;
      for (var row = 0; row < 8; row++) {
        if (row == col) continue;
        final factor = a[row][col] / a[col][col];
        if (factor == 0) continue;
        for (var k = col; k < 9; k++) {
          a[row][k] -= factor * a[col][k];
        }
      }
    }
    return [for (var i = 0; i < 8; i++) a[i][8] / a[i][i], 1];
  }
}

/// Smooths the detected corners between scanner results.
///
/// Detections arrive less often than frames are drawn and carry a pixel or
/// two of noise. Chasing the latest detection with an exponential ease gives
/// steady motion; [lost] turns true when detections stop arriving.
class MarkerTracker {
  MarkerTracker({this.timeout = 0.45});

  /// Seconds without a detection before the marker counts as lost.
  final double timeout;

  List<Offset>? _target;
  List<Offset>? _current;
  double _sinceSeen = double.infinity;

  /// Smoothed corners, or null if the marker has never been seen.
  List<Offset>? get corners => _current;

  bool get lost => _sinceSeen > timeout;

  /// Seconds since the last detection.
  double get sinceSeen => _sinceSeen;

  void report(List<Offset> corners) {
    // After a gap, jump straight to the new position.
    if (lost || _current == null) _current = List.of(corners);
    _target = corners;
    _sinceSeen = 0;
  }

  void advance(double dt) {
    _sinceSeen += dt;
    final target = _target, current = _current;
    if (target == null || current == null) return;
    final ease = 1 - math.exp(-dt * 20);
    _current = [
      for (var i = 0; i < 4; i++) Offset.lerp(current[i], target[i], ease)!,
    ];
  }

  void reset() {
    _target = null;
    _current = null;
    _sinceSeen = double.infinity;
  }
}

/// Takes the shake out of a marker pose.
///
/// A pose recovered from four corner points is exact when the corners are,
/// but a pixel of noise in them swings the marker's apparent tilt by
/// several degrees, so a model stood on the raw pose trembles even when
/// nothing is moving. Three things steady it:
///
///  * **Levelling.** A marker lying on a table has a known tilt: none. When
///    the phone can say which way is up, and the marker is roughly level,
///    the model's vertical axis is taken from gravity and the marker only
///    decides where the model is and which way it faces.
///  * **A slow normal.** Without gravity, or for a marker on a wall, the
///    marker's own normal is used, averaged over about half a second.
///  * **Adaptive smoothing** of position and facing: heavy when the change
///    is the size of the noise, light when the marker is really moving, so
///    it is still at rest and still follows a moving marker closely.
class MarkerStabilizer {
  /// How far the marker may lean from level and still be levelled.
  static const double levelWithin = 35 * math.pi / 180;

  Vector3? _position;
  Vector3? _heading;
  Vector3? _normal;

  /// True once a pose has been seen since the last [reset].
  bool get hasPose => _position != null;

  /// Forgets the pose, so the next one is taken as it comes. Call when the
  /// marker returns after being lost.
  void reset() {
    _position = null;
    _heading = null;
    _normal = null;
  }

  /// Blend factor for a first-order filter with time constant [tau].
  static double _blend(double dt, double tau) => 1 - math.exp(-dt / tau);

  /// A time constant between [slow] and [fast], by how large [change] is
  /// against the size at which it clearly is not noise.
  static double _adaptive(
    double change,
    double clearly, {
    required double slow,
    required double fast,
  }) {
    final t = (change / clearly).clamp(0.0, 1.0);
    return slow + (fast - slow) * t;
  }

  /// The steadied pose for the [raw] one from [MarkerPose.estimate].
  ///
  /// [up] is the direction away from the ground in camera space, when the
  /// phone knows it. [dt] is the time since the last call, in seconds.
  Matrix4 update(Matrix4 raw, {Vector3? up, required double dt}) {
    final rawX = raw.getColumn(0).xyz;
    final rawNormal = raw.getColumn(1).xyz;
    final rawPosition = raw.getTranslation();
    dt = dt.clamp(1 / 240, 0.1);

    // The marker's normal, averaged over about half a second.
    final normal = _normal == null
        ? rawNormal.normalized()
        : ((_normal! + (rawNormal - _normal!) * _blend(dt, 0.45))..normalize());
    _normal = normal;

    // Stand the model along gravity when the marker is close to level.
    final axis = up != null && up.dot(normal) > math.cos(levelWithin)
        ? up.normalized()
        : normal;

    // Facing: the marker's X axis, flattened onto the plane the model
    // stands on.
    Vector3 flatten(Vector3 v) => v - axis * v.dot(axis);
    var target = flatten(rawX);
    if (target.length2 < 1e-9) target = flatten(Vector3(1, 0, 0));
    target.normalize();
    var heading = _heading == null ? target : flatten(_heading!);
    if (heading.length2 < 1e-9) heading = target;
    heading.normalize();
    final turn = math.acos(heading.dot(target).clamp(-1.0, 1.0));
    final headingTau = _adaptive(turn, 0.10, slow: 0.40, fast: 0.05);
    heading = (heading + (target - heading) * _blend(dt, headingTau))
      ..normalize();
    _heading = heading;

    // Position. Distance along the line of sight is the noisiest part of
    // a marker pose (it comes from the marker's apparent size), and the
    // least visible on screen, so it is held more firmly than movement
    // across the view.
    final previous = _position ?? rawPosition;
    final depth = math.max(1e-6, rawPosition.length);
    final ray = rawPosition / depth;
    final delta = rawPosition - previous;
    final along = delta.dot(ray);
    final across = (delta - ray * along).length;
    final moved = math.max(across / depth / 0.012, along.abs() / depth / 0.08);
    final positionTau = _adaptive(moved, 1, slow: 0.35, fast: 0.04);
    final position = previous + delta * _blend(dt, positionTau);
    _position = position;

    final z = heading.cross(axis)..normalize();
    return Matrix4.columns(
      Vector4(heading.x, heading.y, heading.z, 0),
      Vector4(axis.x, axis.y, axis.z, 0),
      Vector4(z.x, z.y, z.z, 0),
      Vector4(position.x, position.y, position.z, 1),
    );
  }
}
