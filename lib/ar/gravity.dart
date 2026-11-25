import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart';

/// Which way is up, from the phone's gravity sensor.
///
/// The direction is given in camera space as the renderer uses it (X right,
/// Y toward the top of the screen, Z toward the viewer). With the app locked
/// to portrait and the back camera in use, those are the phone's own sensor
/// axes, so no conversion is needed.
class GravitySensor {
  static const EventChannel _channel = EventChannel('vulcanic/gravity');

  StreamSubscription<dynamic>? _subscription;
  Vector3? _up;
  DateTime? _last;

  /// The smoothed up direction, or null until the sensor has reported (and
  /// on phones or in tests where there is no sensor).
  Vector3? get up => _up;

  void start() {
    _subscription ??= _channel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is List && event.length >= 3) {
          report(
            Vector3(
              (event[0] as num).toDouble(),
              (event[1] as num).toDouble(),
              (event[2] as num).toDouble(),
            ),
            DateTime.now(),
          );
        }
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  /// Folds one sensor reading in. Public so that it can be tested.
  void report(Vector3 reading, DateTime at) {
    if (reading.length2 < 1e-6) return;
    final sample = reading.normalized();
    final previous = _up, last = _last;
    _last = at;
    if (previous == null || last == null) {
      _up = sample;
      return;
    }
    // A short low-pass takes out hand shake without lagging a real tilt.
    final dt = at.difference(last).inMicroseconds / 1e6;
    final k = 1 - math.exp(-dt.clamp(0.0, 0.5) / 0.12);
    _up = (previous + (sample - previous) * k)..normalize();
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _up = null;
    _last = null;
  }
}
