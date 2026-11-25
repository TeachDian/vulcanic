import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

double smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// The four teaching steps of the eruption, in order.
enum EruptionPhase {
  rising('Magma rises', 0.0),
  erupting('Eruption', 3.5),
  flowing('Lava flows', 7.0),
  cooling('Cooling', 13.5);

  const EruptionPhase(this.label, this.start);
  final String label;

  /// Second at which the phase begins.
  final double start;
}

/// A fixed, time-compressed eruption sequence.
///
/// Everything the renderer animates is a pure function of [time], so the
/// sequence can be paused, resumed or scrubbed without drifting.
class Eruption {
  static const double duration = 18.0;

  /// Seconds since the eruption started; zero while dormant.
  double time = 0;
  bool running = false;

  bool get dormant => time <= 0;
  bool get finished => time >= duration;
  double get progress => time / duration;

  EruptionPhase? get phase {
    if (dormant) return null;
    var current = EruptionPhase.rising;
    for (final p in EruptionPhase.values) {
      if (time >= p.start) current = p;
    }
    return current;
  }

  void start() {
    if (finished) time = 0;
    running = true;
    if (time <= 0) time = 1e-6;
  }

  void pause() => running = false;

  void reset() {
    time = 0;
    running = false;
  }

  void advance(double dt) {
    if (!running) return;
    time = math.min(duration, time + dt);
    if (finished) running = false;
  }

  /// How far up the conduit the magma stands, 0..1.
  double get magmaLevel =>
      0.30 +
      0.70 * smoothstep(0, 3.5, time) -
      0.25 * smoothstep(13.5, 18, time);

  /// Glow of the crater floor and walls, 0..1.
  double get craterGlow =>
      smoothstep(2.4, 3.6, time) * (1 - 0.85 * smoothstep(12, 18, time));

  /// Ash emission, 0..1.
  double get plume =>
      smoothstep(3.3, 4.3, time) * (1 - smoothstep(9.5, 13, time));

  /// Ejected glowing fragments, 0..1.
  double get fragments =>
      smoothstep(3.4, 3.8, time) * (1 - smoothstep(7.5, 9, time));

  /// How far the fresh lava has travelled along the flow, 0..1.
  double get lavaReveal {
    final t = ((time - 5.0) / 7.5).clamp(0.0, 1.0);
    return 1 - (1 - t) * (1 - t);
  }

  /// Temperature of the fresh lava: 1 molten, 0 crusted over.
  double get lavaHeat => dormant ? 0 : 1 - smoothstep(13, 18, time);

  /// Ground tremor amplitude, 0..1.
  double get tremor =>
      smoothstep(3.2, 3.6, time) * (1 - smoothstep(5, 7.5, time));
}

/// Ash, steam and ejected fragments, simulated in model space.
class Particles {
  Particles({this.capacity = 180, int seed = 7}) : _random = math.Random(seed) {
    position = Float32List(capacity * 3);
    velocity = Float32List(capacity * 3);
    age = Float32List(capacity);
    life = Float32List(capacity);
    size = Float32List(capacity);
    kind = Uint8List(capacity);
  }

  static const int steam = 0;
  static const int ash = 1;
  static const int ember = 2;

  final int capacity;
  final math.Random _random;
  late final Float32List position;
  late final Float32List velocity;
  late final Float32List age;
  late final Float32List life; // zero marks a free slot
  late final Float32List size;
  late final Uint8List kind;

  double _steamDebt = 0, _ashDebt = 0, _emberDebt = 0;

  int get alive {
    var n = 0;
    for (var i = 0; i < capacity; i++) {
      if (life[i] > 0) n++;
    }
    return n;
  }

  void clear() {
    life.fillRange(0, capacity, 0);
    _steamDebt = _ashDebt = _emberDebt = 0;
  }

  double _signed() => _random.nextDouble() * 2 - 1;

  void _spawn(int type, Vector3 vent) {
    for (var i = 0; i < capacity; i++) {
      if (life[i] > 0) continue;
      final p = i * 3;
      final angle = _random.nextDouble() * 2 * math.pi;
      final spread = _random.nextDouble();
      position[p] = vent.x + 0.04 * spread * math.cos(angle);
      position[p + 1] = vent.y;
      position[p + 2] = vent.z + 0.04 * spread * math.sin(angle);
      age[i] = 0;
      kind[i] = type;
      switch (type) {
        case steam:
          velocity[p] = 0.03 + 0.03 * _signed();
          velocity[p + 1] = 0.14 + 0.06 * _random.nextDouble();
          velocity[p + 2] = 0.03 * _signed();
          life[i] = 2.6 + _random.nextDouble();
          size[i] = 0.16 + 0.08 * _random.nextDouble();
        case ash:
          velocity[p] = 0.06 + 0.13 * _signed();
          velocity[p + 1] = 0.50 + 0.30 * _random.nextDouble();
          velocity[p + 2] = 0.13 * _signed();
          life[i] = 3.2 + 1.4 * _random.nextDouble();
          size[i] = 0.30 + 0.16 * _random.nextDouble();
        default:
          final speed = 0.25 + 0.40 * _random.nextDouble();
          velocity[p] = speed * math.cos(angle);
          velocity[p + 1] = 0.75 + 0.55 * _random.nextDouble();
          velocity[p + 2] = speed * math.sin(angle);
          life[i] = 0.9 + 0.7 * _random.nextDouble();
          size[i] = 0.007 + 0.008 * _random.nextDouble();
      }
      return;
    }
  }

  void update(double dt, Eruption eruption, Vector3 vent) {
    // Emit.
    _steamDebt += dt * 3.0 * (1 - eruption.plume);
    _ashDebt += dt * 30 * eruption.plume;
    _emberDebt += dt * 16 * eruption.fragments;
    while (_steamDebt >= 1) {
      _steamDebt -= 1;
      _spawn(steam, vent);
    }
    while (_ashDebt >= 1) {
      _ashDebt -= 1;
      _spawn(ash, vent);
    }
    while (_emberDebt >= 1) {
      _emberDebt -= 1;
      _spawn(ember, vent);
    }

    // Integrate.
    final drag = math.exp(-0.7 * dt);
    for (var i = 0; i < capacity; i++) {
      if (life[i] <= 0) continue;
      age[i] += dt;
      final p = i * 3;
      if (age[i] >= life[i] || position[p + 1] < 0.02) {
        life[i] = 0;
        continue;
      }
      if (kind[i] == ember) {
        velocity[p + 1] -= 1.7 * dt; // gravity
      } else {
        velocity[p] = velocity[p] * drag + 0.05 * dt; // drift downwind
        velocity[p + 1] *= drag;
        velocity[p + 2] *= drag;
      }
      position[p] += velocity[p] * dt;
      position[p + 1] += velocity[p + 1] * dt;
      position[p + 2] += velocity[p + 2] * dt;
    }
  }
}
