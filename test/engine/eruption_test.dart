import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:vulcanic/engine/eruption.dart';
import 'package:vulcanic/engine/scene_frame.dart';
import 'package:vulcanic/engine/volcano_controller.dart';
import 'package:vulcanic/engine/volcano_geometry.dart';

void main() {
  final vent = Vector3(0, 0.7, 0);

  group('Eruption', () {
    test('is dormant until started and stops at the end', () {
      final e = Eruption();
      expect(e.dormant, isTrue);
      expect(e.phase, isNull);
      e.advance(5);
      expect(e.time, 0, reason: 'does not run until started');

      e.start();
      e.advance(4);
      expect(e.phase, EruptionPhase.erupting);
      e.advance(1);
      expect(e.phase, EruptionPhase.flowing);
      e.advance(100);
      expect(e.finished, isTrue);
      expect(e.running, isFalse);
      expect(e.phase, EruptionPhase.cooling);

      e.start();
      expect(e.time, lessThan(0.001), reason: 'restarts after finishing');
    });

    test('walks through the four phases in order', () {
      final e = Eruption()..start();
      final seen = <EruptionPhase>[];
      while (!e.finished) {
        e.advance(0.25);
        if (seen.isEmpty || seen.last != e.phase) seen.add(e.phase!);
      }
      expect(seen, EruptionPhase.values);
    });

    test('builds up, bursts, flows and cools, in that order', () {
      final e = Eruption()..start();
      // Build-up: the ground already trembles, nothing has left the vent.
      e.time = 2.5;
      expect(e.tremor, inExclusiveRange(0.1, 0.5));
      expect(e.plume, 0);
      expect(e.lavaHeat, 0, reason: 'no fresh lava before it reaches the rim');
      expect(e.steamRate, greaterThan(6), reason: 'the vent breathes faster');

      // The burst: full tremor, ash and fragments leaving fast.
      e.time = 3.3;
      expect(e.magmaLevel, greaterThan(0.95));
      expect(e.tremor, greaterThan(0.9));
      expect(e.plume, greaterThan(0.9));
      expect(e.fragments, greaterThan(0.9));
      expect(e.burst, greaterThan(0.5));
      expect(e.lavaReveal, 0);

      // The column has settled and the lava is out.
      e.time = 8;
      expect(e.burst, 0);
      expect(e.plume, inExclusiveRange(0.3, 0.8));
      expect(e.lavaHeat, 1);

      e.time = 12;
      expect(e.lavaReveal, closeTo(1, 1e-9));
      e.time = Eruption.duration;
      expect(e.plume, 0);
      expect(e.lavaHeat, closeTo(0, 1e-9));
      expect(e.craterGlow, lessThan(0.2));
    });

    test('lava advances in surges with stalls between', () {
      final e = Eruption()..start();
      double at(double t) {
        e.time = t;
        return e.lavaReveal;
      }

      // Never backwards.
      var last = 0.0;
      for (var t = 0.0; t <= Eruption.duration; t += 0.1) {
        expect(at(t), greaterThanOrEqualTo(last - 1e-9));
        last = at(t);
      }
      // Moving during a surge, still during a stall.
      expect(at(5.4) - at(5.0), greaterThan(0.05));
      expect(at(7.1) - at(6.5), lessThan(0.005));
      expect(at(8.0) - at(7.4), greaterThan(0.05));
    });

    test('the crater pulses faster and faster before it opens', () {
      final e = Eruption()..start();
      var peaks = <double>[];
      var previous = 0.0, rising = false;
      for (var t = 0.5; t < Eruption.onset; t += 0.01) {
        e.time = t;
        final g = e.craterGlow;
        if (rising && g < previous) peaks.add(t);
        rising = g > previous;
        previous = g;
      }
      expect(peaks.length, greaterThanOrEqualTo(3));
      final firstGap = peaks[1] - peaks[0];
      final lastGap = peaks.last - peaks[peaks.length - 2];
      expect(lastGap, lessThan(firstGap));
    });

    test('pausing holds the sequence in place', () {
      final e = Eruption()..start();
      e.advance(2);
      e.pause();
      e.advance(5);
      expect(e.time, closeTo(2, 1e-3));
    });
  });

  group('Particles', () {
    test('emit ash only while the plume is active and never overflow', () {
      final e = Eruption()..start();
      final p = Particles(capacity: 64);
      var ash = 0;
      for (var i = 0; i < 60 * 12; i++) {
        e.advance(1 / 60);
        p.update(1 / 60, e, vent);
        expect(p.alive, lessThanOrEqualTo(64));
        for (var k = 0; k < p.capacity; k++) {
          if (p.life[k] > 0 && p.kind[k] == Particles.ash) ash++;
        }
      }
      expect(ash, greaterThan(0));
      p.clear();
      expect(p.alive, 0);
    });

    test('a dormant volcano only steams', () {
      final e = Eruption();
      final p = Particles();
      for (var i = 0; i < 300; i++) {
        p.update(1 / 60, e, vent);
      }
      expect(p.alive, greaterThan(0));
      for (var k = 0; k < p.capacity; k++) {
        if (p.life[k] > 0) expect(p.kind[k], Particles.steam);
      }
    });
  });

  group('VolcanoController', () {
    test('selecting an interior part opens the cutaway', () {
      final c = VolcanoController();
      var notified = 0;
      c.addListener(() => notified++);
      c.select(VolcanoPart.chamber);
      expect(c.cutaway, isTrue);
      expect(notified, 1);

      c.cutaway = false;
      expect(c.selected, isNull, reason: 'the chamber is no longer visible');
    });

    test('the highlight outlives the selection while it fades', () {
      final c = VolcanoController()..select(VolcanoPart.lava);
      for (var i = 0; i < 30; i++) {
        c.tick(1 / 60, vent);
      }
      c.select(null);
      expect(c.selected, isNull);
      expect(c.highlighted, VolcanoPart.lava);
      for (var i = 0; i < 60; i++) {
        c.tick(1 / 60, vent);
      }
      expect(c.highlighted, isNull);
    });

    /// Runs the controller until its eased motion has settled.
    void settle(VolcanoController c) {
      for (var i = 0; i < 240 && c.inMotion; i++) {
        c.tick(1 / 60, vent);
      }
      expect(c.inMotion, isFalse);
    }

    /// The azimuth of the model that faces the viewer.
    double facing(VolcanoController c) => kFrontAzimuth + c.rotation;

    test('opening the cutaway turns and zooms to the opening', () {
      final c = VolcanoController();
      c.cutaway = true;
      expect(c.inMotion, isTrue);
      c.tick(1 / 60, vent);
      expect(c.rotation, isNot(0), reason: 'eased, not instant');
      expect(c.scale, lessThan(VolcanoController.openingZoom));
      settle(c);
      expect(facing(c), closeTo(VolcanoController.openingAzimuth, 1e-9));
      expect(c.scale, VolcanoController.openingZoom);
    });

    test('closing the cutaway hands the view back', () {
      final c = VolcanoController()
        ..rotation = 0.4
        ..scale = 0.8;
      c.cutaway = true;
      settle(c);
      c.cutaway = false;
      settle(c);
      expect(c.rotation, closeTo(0.4, 1e-9));
      expect(c.scale, closeTo(0.8, 1e-9));
    });

    test('a view the user moved is left where they put it', () {
      final c = VolcanoController()..cutaway = true;
      settle(c);
      c
        ..holdStill()
        ..rotation = 2.0;
      c.cutaway = false;
      expect(c.inMotion, isFalse);
      expect(c.rotation, 2.0);
    });

    test('never zooms out to focus, and takes the short way round', () {
      final c = VolcanoController()
        ..scale = 2
        ..rotation = 6.0; // nearly a full turn
      c.cutaway = true;
      settle(c);
      expect(c.scale, 2);
      // From 6.0 the nearest equivalent of the opening is ahead, not back
      // through zero.
      expect((c.rotation - 6.0).abs(), lessThan(math.pi));
      expect(
        math.cos(facing(c) - VolcanoController.openingAzimuth),
        closeTo(1, 1e-9),
      );
    });

    test('selecting a part brings it round to the viewer', () {
      final c = VolcanoController()..select(VolcanoPart.lava);
      settle(c);
      expect(facing(c), closeTo(VolcanoPart.lava.azimuth, 1e-9));
      expect(c.scale, 1, reason: 'exterior parts do not zoom');

      c.select(VolcanoPart.chamber);
      settle(c);
      expect(c.cutaway, isTrue);
      expect(facing(c), closeTo(VolcanoController.openingAzimuth, 1e-9));
      expect(c.scale, VolcanoController.openingZoom);
    });

    test('view buttons add up and stay within the zoom limits', () {
      final c = VolcanoController()
        ..turnBy(math.pi / 2)
        ..turnBy(math.pi / 2);
      for (var i = 0; i < 20; i++) {
        c.zoomBy(1.25);
      }
      settle(c);
      expect(c.rotation, closeTo(math.pi, 1e-9));
      expect(c.scale, VolcanoController.maxScale);
      c.resetTransform();
      settle(c);
      expect(c.scale, 1);
      expect(math.cos(c.rotation), closeTo(1, 1e-9));
    });

    test('a turn overshoots a little; a zoom does not', () {
      final c = VolcanoController()..turnBy(1);
      var furthest = 0.0;
      for (var i = 0; i < 240 && c.inMotion; i++) {
        c.tick(1 / 60, vent);
        furthest = math.max(furthest, c.rotation);
      }
      expect(furthest, inExclusiveRange(1.005, 1.12));
      expect(c.rotation, 1);

      c.zoomBy(1.5);
      var largest = 0.0;
      for (var i = 0; i < 240 && c.inMotion; i++) {
        c.tick(1 / 60, vent);
        largest = math.max(largest, c.scale);
      }
      expect(largest, lessThan(1.5 * 1.02));
      expect(c.scale, 1.5);
    });

    test('a placed model rises into place', () {
      final c = VolcanoController();
      expect(c.arrivalScale, 1);
      c.arrive();
      expect(c.arrivalScale, closeTo(0.55, 1e-9));
      var peak = 0.0;
      for (var i = 0; i < 180; i++) {
        c.tick(1 / 60, vent);
        peak = math.max(peak, c.arrival);
      }
      expect(peak, greaterThan(1.0), reason: 'settles with a small bounce');
      expect(c.arrival, 1);
      expect(c.arrivalAge, greaterThan(2.9));
    });

    test('reset returns to the starting state', () {
      final c = VolcanoController()
        ..rotation = 1
        ..scale = 99
        ..cutaway = true;
      expect(c.scale, VolcanoController.maxScale);
      c.toggleEruption();
      c.tick(0.05, vent);
      c.reset();
      expect(c.eruption.dormant, isTrue);
      expect(c.transformed, isFalse);
      expect(c.cutaway, isFalse);
    });

    test('notifies when the phase changes, not on every tick', () {
      final c = VolcanoController();
      var notified = 0;
      c.toggleEruption();
      c.addListener(() => notified++);
      for (var i = 0; i < 60; i++) {
        c.tick(1 / 60, vent);
      }
      expect(notified, 1, reason: 'entered the first phase');
      expect(c.frame.value, 60);
    });
  });
}
