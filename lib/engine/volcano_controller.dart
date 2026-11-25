import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import 'eruption.dart';
import 'scene_frame.dart';
import 'volcano_geometry.dart';

/// Interactive state of the volcano, shared by every viewing mode.
///
/// Listeners are notified on discrete changes (a toggle, a new phase, a
/// selection). Per-frame animation is signalled through [frame] instead, so
/// the surrounding UI is not rebuilt sixty times a second.
class VolcanoController extends ChangeNotifier {
  final Eruption eruption = Eruption();
  final Particles particles = Particles();

  /// Bumped once per animation tick; the painter repaints on it.
  final ValueNotifier<int> frame = ValueNotifier<int>(0);

  bool _cutaway = false;
  bool _labels = true;
  VolcanoPart? _selected;
  VolcanoPart? _highlighted;
  EruptionPhase? _phase;

  /// Animated 0..1 companions of the toggles above.
  double cutawayT = 0;
  double labelsT = 1;
  double selectionT = 0;

  /// Seconds of animation time, drives pulses and shimmer.
  double clock = 0;

  /// User rotation about the vertical axis, in radians.
  double rotation = 0;

  /// User scale multiplier.
  double _scale = 1;

  static const double minScale = 0.4;
  static const double maxScale = 2.5;

  /// Centre of the quadrant the cutaway opens, as an azimuth.
  static const double openingAzimuth = 45 * math.pi / 180;

  /// How far the view zooms in on the opening.
  static const double openingZoom = 1.22;

  // Where the view is easing to, when the app (not a finger) is moving it.
  double? _rotationGoal;
  double? _scaleGoal;

  /// The view as it was before the cutaway turned it, to return to.
  ({double rotation, double scale})? _beforeOpening;

  /// True while the view is easing toward a new orientation or size.
  bool get inMotion => _rotationGoal != null || _scaleGoal != null;
  double _rotationSpeed = 0;
  double _scaleSpeed = 0;

  /// How far the model has risen into place after being put down: 0 when
  /// it lands, settling at 1 with a small overshoot. Hosts scale and lift
  /// the model by it.
  double arrival = 1;
  double _arrivalSpeed = 0;

  /// Seconds since [arrive] was last called; drives the surface ripple.
  double arrivalAge = 10;

  /// Plays the arrival: call when the model is placed or first appears.
  void arrive() {
    arrival = 0;
    _arrivalSpeed = 0;
    arrivalAge = 0;
  }

  /// Size multiplier for the arrival animation.
  double get arrivalScale => 0.55 + 0.45 * arrival;

  bool get cutaway => _cutaway;
  bool get labels => _labels;
  VolcanoPart? get selected => _selected;

  /// The part to draw emphasised. Follows [selected], but outlives it while
  /// the highlight fades out, so deselecting does not flash the part grey.
  VolcanoPart? get highlighted => _highlighted;
  double get scale => _scale;
  bool get transformed => rotation != 0 || _scale != 1 || inMotion;

  set scale(double value) => _scale = value.clamp(minScale, maxScale);

  set cutaway(bool value) {
    if (_cutaway == value) return;
    if (value) {
      _openCutaway();
    } else {
      _cutaway = false;
      // Parts that are only visible in the cutaway cannot stay selected.
      if (_selected?.isInterior ?? false) _selected = null;
      // Hand the view back as it was, unless the user has moved it since.
      final before = _beforeOpening;
      if (before != null) {
        _rotationGoal = rotation + _shortWay(before.rotation - rotation);
        _scaleGoal = before.scale;
        _beforeOpening = null;
      }
    }
    notifyListeners();
  }

  /// Opens the cutaway and brings the opening round to face the viewer.
  void _openCutaway() {
    if (_cutaway) return;
    _cutaway = true;
    _beforeOpening = (
      rotation: _rotationGoal ?? rotation,
      scale: _scaleGoal ?? _scale,
    );
    face(openingAzimuth, atLeast: openingZoom);
  }

  /// Turns the model so that the side at [azimuth] faces the viewer, the
  /// short way round, zooming in to [atLeast] if it is smaller than that.
  void face(double azimuth, {double? atLeast}) {
    // A rotation of r about +Y moves azimuth a to a - r.
    _rotationGoal = rotation + _shortWay(azimuth - kFrontAzimuth - rotation);
    if (atLeast != null && (_scaleGoal ?? _scale) < atLeast) {
      _scaleGoal = atLeast;
    }
  }

  /// Turns the model by [radians], eased. Repeated calls add up.
  void turnBy(double radians) {
    _rotationGoal = (_rotationGoal ?? rotation) + radians;
    _beforeOpening = null;
  }

  /// Zooms by [factor], eased. Repeated calls add up.
  void zoomBy(double factor) {
    _scaleGoal = ((_scaleGoal ?? _scale) * factor).clamp(minScale, maxScale);
    _beforeOpening = null;
  }

  /// Stops any eased motion: the user has taken hold of the model.
  void holdStill() {
    _rotationGoal = null;
    _scaleGoal = null;
    _rotationSpeed = 0;
    _scaleSpeed = 0;
    _beforeOpening = null;
  }

  /// The equivalent of [angle] within half a turn of zero.
  static double _shortWay(double angle) {
    const turn = 2 * math.pi;
    final wrapped = angle % turn; // 0 .. 2pi
    return wrapped > math.pi ? wrapped - turn : wrapped;
  }

  set labels(bool value) {
    if (_labels == value) return;
    _labels = value;
    notifyListeners();
  }

  /// Selects [part] (or clears the selection). Interior parts open the
  /// cutaway so that there is something to look at.
  void select(VolcanoPart? part) {
    if (_selected == part) return;
    _selected = part;
    if (part != null) {
      _highlighted = part;
      // Bring the part round to the viewer. Interior parts sit in the
      // opening, so opening the cutaway already faces them.
      if (part.isInterior && !_cutaway) {
        _openCutaway();
      } else {
        face(part.azimuth);
      }
    }
    notifyListeners();
  }

  void toggleEruption() {
    if (eruption.running) {
      eruption.pause();
    } else {
      eruption.start();
    }
    notifyListeners();
  }

  /// Returns the eruption, the cutaway, the selection and the user transform
  /// to their starting state. The labels toggle is a viewing preference and
  /// is left alone.
  void reset() {
    eruption.reset();
    particles.clear();
    _phase = null;
    holdStill();
    rotation = 0;
    _scale = 1;
    _cutaway = false;
    _selected = null;
    notifyListeners();
  }

  /// Eases the model back to its starting orientation and size.
  void resetTransform() {
    _beforeOpening = null;
    _rotationGoal = rotation + _shortWay(-rotation);
    _scaleGoal = 1;
    notifyListeners();
  }

  /// Advances every animation by [dt] seconds.
  void tick(double dt, Vector3 vent) {
    dt = dt.clamp(0.0, 0.1);
    clock += dt;
    final wasRunning = eruption.running;
    eruption.advance(dt);
    particles.update(dt, eruption, vent);

    cutawayT = _approach(cutawayT, _cutaway ? 1 : 0, dt * 3.2);
    labelsT = _approach(labelsT, _labels ? 1 : 0, dt * 5);
    selectionT = _approach(selectionT, _selected == null ? 0 : 1, dt * 5);

    if (selectionT == 0) _highlighted = _selected;

    // Spring toward wherever the app has pointed the view. A turn has a
    // little overshoot, so the model feels like it has weight; a zoom is
    // nearly critically damped, because bouncing size reads as a glitch.
    final rotationGoal = _rotationGoal;
    if (rotationGoal != null) {
      _rotationSpeed +=
          (90 * (rotationGoal - rotation) - 11.8 * _rotationSpeed) * dt;
      rotation += _rotationSpeed * dt;
      if ((rotationGoal - rotation).abs() < 0.0015 &&
          _rotationSpeed.abs() < 0.02) {
        rotation = rotationGoal;
        _rotationGoal = null;
        _rotationSpeed = 0;
      }
    }
    final scaleGoal = _scaleGoal;
    if (scaleGoal != null) {
      _scaleSpeed += (100 * (scaleGoal - _scale) - 16.5 * _scaleSpeed) * dt;
      _scale += _scaleSpeed * dt;
      if (_scale < minScale || _scale > maxScale) {
        _scale = _scale.clamp(minScale, maxScale);
        _scaleSpeed = 0;
      }
      if ((scaleGoal - _scale).abs() < 0.0015 && _scaleSpeed.abs() < 0.02) {
        _scale = scaleGoal;
        _scaleGoal = null;
        _scaleSpeed = 0;
      }
    }

    // The model's arrival on a surface: it rises into place.
    if (arrival < 1 || _arrivalSpeed != 0) {
      arrivalAge += dt;
      _arrivalSpeed += (130 * (1 - arrival) - 12.5 * _arrivalSpeed) * dt;
      arrival += _arrivalSpeed * dt;
      if ((1 - arrival).abs() < 0.002 && _arrivalSpeed.abs() < 0.02) {
        arrival = 1;
        _arrivalSpeed = 0;
      }
    } else if (arrivalAge < 10) {
      arrivalAge += dt;
    }

    final phase = eruption.phase;
    if (phase != _phase || wasRunning != eruption.running) {
      _phase = phase;
      notifyListeners();
    }
    frame.value++;
  }

  static double _approach(double value, double target, double step) {
    if (value < target) return (value + step).clamp(0.0, target);
    if (value > target) return (value - step).clamp(target, 1.0);
    return value;
  }

  @override
  void dispose() {
    frame.dispose();
    super.dispose();
  }
}
