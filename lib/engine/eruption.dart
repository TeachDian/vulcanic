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
  erupting('Eruption', 2.9),
  flowing('Lava flows', 4.6),
  cooling('Cooling', 12.5);

  const EruptionPhase(this.label, this.start);
  final String label;

  /// Second at which the phase begins.
  final double start;
}

/// A fixed, time-compressed eruption sequence.
///
/// Everything the renderer animates is a pure function of [time], so the
/// sequence can be paused, resumed or scrubbed without drifting.
///
/// The shape of it: three seconds of build-up in which the ground trembles
/// and the crater glow pulses faster, a violent first second, a column that
/// pulses about once a second, lava that advances in three surges with
/// stalls between, and a slow cooling.
class Eruption {
  static const double duration = 18.0;

  /// Second at which the vent opens.
  static const double onset = 2.9;

  /// Seconds between pulses of the sustained column.
  static const double pulse = 1.1;

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
      0.70 * smoothstep(0, onset, time) -
      0.25 * smoothstep(12.5, 18, time);

  /// Glow of the crater floor and walls, 0..1. Before the vent opens it
  /// pulses, faster and faster.
  double get craterGlow {
    final beat = 0.5 + 0.5 * math.sin(2 * math.pi * time * (0.5 + 0.42 * time));
    final before =
        smoothstep(0.4, onset, time) *
        (0.16 + 0.30 * beat) *
        (1 - smoothstep(onset, onset + 0.2, time));
    final after =
        smoothstep(onset, onset + 0.2, time) *
        (1 - 0.9 * smoothstep(12.5, 18, time));
    return math.max(before, after);
  }

  /// Ash emission, 0..1: a burst, then a column that pulses.
  double get plume {
    final column = time > 4
        ? 0.8 + 0.2 * math.sin(2 * math.pi * time / pulse)
        : 1.0;
    return smoothstep(onset + 0.05, onset + 0.22, time) *
        (1 - 0.4 * smoothstep(3.7, 5, time)) *
        column *
        (1 - smoothstep(9.5, 12.5, time));
  }

  /// How violent the ejection is, 1 in the first second and falling to 0
  /// as the column settles. Ash and fragments leave faster while it is high.
  double get burst => dormant ? 0 : 1 - smoothstep(onset + 0.1, 3.9, time);

  /// Ejected glowing fragments, 0..1: the burst, then spits with the column.
  double get fragments {
    final first =
        smoothstep(onset + 0.05, onset + 0.15, time) *
        (1 - smoothstep(3.7, 6, time));
    final spits =
        0.3 *
        smoothstep(5, 5.4, time) *
        (1 - smoothstep(7.6, 8.6, time)) *
        (0.5 + 0.5 * math.sin(2 * math.pi * time / pulse));
    return math.max(first, spits);
  }

  /// How far the fresh lava has travelled along the flow, 0..1. It moves in
  /// three surges with stalls between, the way a real front advances.
  double get lavaReveal {
    double surge(double from, double length) {
      final t = ((time - from) / length).clamp(0.0, 1.0);
      return 1 - (1 - t) * (1 - t) * (1 - t);
    }

    return 0.45 * surge(4.6, 1.6) +
        0.33 * surge(7.2, 1.6) +
        0.22 * surge(9.6, 2);
  }

  /// Temperature of the fresh lava: 1 molten, 0 crusted over. Zero until
  /// lava reaches the rim, and it cools quickly at first, then slowly.
  double get lavaHeat =>
      smoothstep(4.5, 4.8, time) *
      (1 - math.pow(smoothstep(12.5, 18, time), 0.7).toDouble());

  /// Ground tremor amplitude, 0..1: a growing rumble, then the shock.
  double get tremor {
    final before =
        0.38 *
        smoothstep(0.3, onset, time) *
        (1 - smoothstep(onset, onset + 0.2, time));
    final after =
        smoothstep(onset, onset + 0.2, time) *
        (1 - 0.82 * smoothstep(4.2, 8.5, time)) *
        (1 - smoothstep(10, 13, time));
    return math.max(before, after);
  }

  /// Puffs of steam per second. The vent breathes faster before it opens.
  double get steamRate =>
      (3 + 9 * smoothstep(0.3, onset, time)) * (1 - plume.clamp(0.0, 1.0));
}

/// Ash, steam and ejected fragments, simulated in model space.
class Particles {
  Particles({this.capacity = 260, int seed = 7}) : _random = math.Random(seed) {
    position = Float32List(capacity * 3);
    velocity = Float32List(capacity * 3);
    age = Float32List(capacity);
    life = Float32List(capacity);
    size = Float32List(capacity);
    phase = Float32List(capacity);
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

  /// A random angle per particle, so each one swirls in its own way.
  late final Float32List phase;
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

  void _spawn(int type, Vector3 vent, double burst) {
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
      phase[i] = angle;
      switch (type) {
        case steam:
          velocity[p] = 0.03 + 0.03 * _signed();
          velocity[p + 1] = 0.14 + 0.06 * _random.nextDouble();
          velocity[p + 2] = 0.03 * _signed();
          life[i] = 2.6 + _random.nextDouble();
          size[i] = 0.16 + 0.08 * _random.nextDouble();
        case ash:
          // The first second is a jet; after that a steadier column.
          velocity[p] = 0.17 * _signed();
          velocity[p + 1] =
              (0.62 + 0.5 * _random.nextDouble()) * (1 + 1.5 * burst);
          velocity[p + 2] = 0.17 * _signed();
          life[i] = 3.4 + 2.2 * _random.nextDouble();
          size[i] = (0.30 + 0.20 * _random.nextDouble());
        default:
          final speed =
              (0.3 + 0.75 * _random.nextDouble()) * (0.7 + 0.5 * burst);
          velocity[p] = speed * math.cos(angle);
          velocity[p + 1] = 0.9 + 0.9 * _random.nextDouble();
          velocity[p + 2] = speed * math.sin(angle);
          life[i] = 1.5 + 0.9 * _random.nextDouble();
          size[i] = 0.007 + 0.008 * _random.nextDouble();
      }
      return;
    }
  }

  void update(double dt, Eruption eruption, Vector3 vent) {
    final burst = eruption.burst;
    // Emit.
    _steamDebt += dt * eruption.steamRate;
    _ashDebt += dt * 44 * eruption.plume;
    _emberDebt += dt * 22 * eruption.fragments;
    while (_steamDebt >= 1) {
      _steamDebt -= 1;
      _spawn(steam, vent, burst);
    }
    while (_ashDebt >= 1) {
      _ashDebt -= 1;
      _spawn(ash, vent, burst);
    }
    while (_emberDebt >= 1) {
      _emberDebt -= 1;
      _spawn(ember, vent, burst);
    }

    // Integrate.
    final steamDrag = math.exp(-0.7 * dt);
    final ashDrag = math.exp(-1.25 * dt);
    for (var i = 0; i < capacity; i++) {
      if (life[i] <= 0) continue;
      age[i] += dt;
      final p = i * 3;
      if (age[i] >= life[i] || position[p + 1] < 0.02) {
        life[i] = 0;
        continue;
      }
      switch (kind[i]) {
        case ember:
          velocity[p + 1] -= 1.35 * dt; // gravity
        case ash:
          final rise = position[p + 1] - vent.y;
          // Higher up the column opens out, and each puff swirls.
          final open = 1.1 * smoothstep(0.35, 1.3, rise);
          final swirl = 0.16 * math.sin(age[i] * 2.1 + phase[i]);
          velocity[p] =
              velocity[p] * ashDrag +
              ((position[p] - vent.x) * open + swirl + 0.07) * dt;
          velocity[p + 1] = velocity[p + 1] * ashDrag + 0.09 * dt; // buoyancy
          velocity[p + 2] =
              velocity[p + 2] * ashDrag +
              ((position[p + 2] - vent.z) * open +
                      0.16 * math.cos(age[i] * 1.7 + phase[i])) *
                  dt;
        default:
          velocity[p] = velocity[p] * steamDrag + 0.05 * dt; // drift downwind
          velocity[p + 1] *= steamDrag;
          velocity[p + 2] *= steamDrag;
      }
      position[p] += velocity[p] * dt;
      position[p + 1] += velocity[p + 1] * dt;
      position[p + 2] += velocity[p + 2] * dt;
    }
  }
}
