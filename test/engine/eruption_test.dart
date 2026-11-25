import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:vulcanic/engine/eruption.dart';
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

    test('magma rises before the lava flows, then everything cools', () {
      final e = Eruption()..start();
      e.time = 3.4;
      expect(e.magmaLevel, greaterThan(0.95));
      expect(e.lavaReveal, 0);
      e.time = 6;
      expect(e.plume, greaterThan(0.9));
      expect(e.fragments, greaterThan(0.9));
      e.time = 12.5;
      expect(e.lavaReveal, closeTo(1, 1e-9));
      expect(e.lavaHeat, 1);
      e.time = Eruption.duration;
      expect(e.plume, 0);
      expect(e.lavaHeat, closeTo(0, 1e-9));
      expect(e.craterGlow, lessThan(0.2));
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
