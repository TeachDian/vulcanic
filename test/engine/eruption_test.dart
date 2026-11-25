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
      e.time = 2;
      expect(e.lavaHeat, 0, reason: 'no fresh lava before it reaches the rim');
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
