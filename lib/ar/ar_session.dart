import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether this phone can run markerless AR.
enum ArAvailability {
  /// ARCore is installed and ready.
  supported,

  /// The phone is capable, but Google Play Services for AR is missing or old.
  installable,

  /// The phone is not ARCore capable.
  unsupported,
}

/// Whether the app may use the camera.
enum CameraAccess {
  granted,

  /// Not granted, but the user can still be asked.
  denied,

  /// Denied for good; only the system settings page can change it.
  blocked,
}

/// Camera permission, handled natively so the app needs no extra plugin.
abstract final class CameraPermission {
  static const MethodChannel _methods = MethodChannel('vulcanic/ar');

  /// The current state, asking the user first when [request] is set.
  static Future<CameraAccess> check({bool request = false}) async {
    try {
      final answer = await _methods.invokeMethod<String>('cameraPermission', {
        'request': request,
      });
      return CameraAccess.values.byName(answer ?? 'denied');
    } on PlatformException catch (_) {
      return CameraAccess.denied;
    } on MissingPluginException catch (_) {
      return CameraAccess.denied;
    }
  }

  static Future<void> openSettings() async {
    try {
      await _methods.invokeMethod<void>('openSettings');
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }
}

/// Why ARCore is struggling to track, if it is.
enum TrackingIssue {
  none(''),
  badState('Tracking is restarting'),
  insufficientLight('Too dark to track. Find more light'),
  excessiveMotion('Moving too fast. Slow down'),
  insufficientFeatures('Aim at a surface with more detail'),
  cameraUnavailable('Another app is using the camera');

  const TrackingIssue(this.advice);
  final String advice;
}

/// State of the anchor the volcano stands on.
enum AnchorState { none, tracking, lost }

/// What ARCore knows about the world at one camera frame.
///
/// Decoded from the packet built by `ArSessionRunner.buildPacket` on the
/// Android side; the layout is documented there.
class ArFrame {
  ArFrame._({
    required this.tracking,
    required this.issue,
    required this.light,
    required this.anchorState,
    required this.view,
    required this.projection,
    required this.anchor,
    required this.reticle,
    required this.planes,
    required this.points,
  });

  static const int _header = 72;

  /// True while ARCore knows where the phone is.
  final bool tracking;
  final TrackingIssue issue;

  /// Estimated scene brightness, 0..1, or null when unknown.
  final double? light;
  final AnchorState anchorState;

  /// World to camera, and camera to clip space.
  final Matrix4 view;
  final Matrix4 projection;

  /// Pose of the anchor, when it is tracking.
  final Matrix4? anchor;

  /// Pose where the centre of the screen meets a detected plane.
  final Matrix4? reticle;

  /// Outline of each detected plane as world-space xyz triples.
  final List<Float32List> planes;

  /// Tracked feature points as world-space xyz triples.
  final Float32List points;

  factory ArFrame.parse(Float32List p) {
    Matrix4 matrix(int at) =>
        Matrix4.fromList(Float32List.sublistView(p, at, at + 16));
    final anchorState = AnchorState.values[p[3].toInt().clamp(0, 2)];
    var n = _header;
    final planes = <Float32List>[];
    for (var i = 0; i < p[5].toInt(); i++) {
      final count = p[n++].toInt();
      planes.add(Float32List.sublistView(p, n, n + count * 3));
      n += count * 3;
    }
    final pointCount = p[6].toInt();
    return ArFrame._(
      tracking: p[0] > 0.5,
      issue: TrackingIssue
          .values[p[1].toInt().clamp(0, TrackingIssue.values.length - 1)],
      light: p[2] < 0 ? null : p[2],
      anchorState: anchorState,
      view: matrix(8),
      projection: matrix(24),
      anchor: anchorState == AnchorState.tracking ? matrix(40) : null,
      reticle: p[4] > 0.5 ? matrix(56) : null,
      planes: planes,
      points: Float32List.sublistView(p, n, n + pointCount * 3),
    );
  }
}

/// A running ARCore session, bridged from Android.
///
/// The camera image arrives as a Flutter texture ([textureId]); tracking data
/// arrives once per camera frame through [frame].
class ArSession {
  static const MethodChannel _methods = MethodChannel('vulcanic/ar');
  static const EventChannel _frames = EventChannel('vulcanic/ar/frames');

  /// The most recent frame. Painters listen to this directly.
  final ValueNotifier<ArFrame?> frame = ValueNotifier<ArFrame?>(null);

  /// Set if the session fails after starting (e.g. the camera is taken).
  final ValueNotifier<String?> failure = ValueNotifier<String?>(null);

  int? textureId;
  StreamSubscription<dynamic>? _subscription;

  /// Asks ARCore whether this phone is supported. The first answer can be
  /// "still checking", so this polls for a moment before giving up.
  static Future<ArAvailability> availability() async {
    try {
      for (var attempt = 0; attempt < 15; attempt++) {
        final answer = await _methods.invokeMethod<String>('availability');
        switch (answer) {
          case 'supported':
            return ArAvailability.supported;
          case 'installable':
            return ArAvailability.installable;
          case 'unsupported':
            return ArAvailability.unsupported;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
    return ArAvailability.unsupported;
  }

  /// Opens the store page for Google Play Services for AR.
  static Future<void> requestInstall() async {
    try {
      await _methods.invokeMethod<String>('install');
    } on PlatformException catch (_) {}
  }

  /// Starts tracking and rendering the camera at [width] x [height] pixels.
  Future<void> start(int width, int height) async {
    _subscription ??= _frames.receiveBroadcastStream().listen(
      (dynamic packet) {
        if (!_disposed) frame.value = ArFrame.parse(packet as Float32List);
      },
      onError: (Object error) {
        if (_disposed) return;
        failure.value = error is PlatformException
            ? (error.message ?? error.code)
            : '$error';
      },
    );
    final answer = await _methods.invokeMapMethod<String, Object?>('start', {
      'width': width,
      'height': height,
    });
    textureId = answer!['textureId']! as int;
  }

  Future<void> resize(int width, int height) =>
      _methods.invokeMethod('resize', {'width': width, 'height': height});

  /// Anchors the model where the texture pixel ([x], [y]) meets a detected
  /// plane. Returns false if there is no plane there.
  Future<bool> placeAt(double x, double y) async =>
      await _methods.invokeMethod<bool>('hitTest', {'x': x, 'y': y}) ?? false;

  Future<void> clearAnchor() => _methods.invokeMethod('clearAnchor');

  bool _disposed = false;

  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    textureId = null;
    if (!_disposed) frame.value = null;
    await subscription?.cancel();
    try {
      await _methods.invokeMethod('stop');
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  void dispose() {
    _disposed = true;
    stop();
    frame.dispose();
    failure.dispose();
  }
}
