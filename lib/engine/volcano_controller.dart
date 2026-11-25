import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import 'eruption.dart';
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

  bool get cutaway => _cutaway;
  bool get labels => _labels;
  VolcanoPart? get selected => _selected;
  double get scale => _scale;
  bool get transformed => rotation != 0 || _scale != 1;

  set scale(double value) => _scale = value.clamp(minScale, maxScale);

  set cutaway(bool value) {
    if (_cutaway == value) return;
    _cutaway = value;
    // Parts that are only visible in the cutaway cannot stay selected.
    if (!value && (_selected?.isInterior ?? false)) _selected = null;
    notifyListeners();
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
    if (part != null && part.isInterior) _cutaway = true;
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

  /// Returns the eruption, the view toggles and the user transform to their
  /// starting state.
  void reset() {
    eruption.reset();
    particles.clear();
    _phase = null;
    rotation = 0;
    _scale = 1;
    _cutaway = false;
    _selected = null;
    notifyListeners();
  }

  void resetTransform() {
    rotation = 0;
    _scale = 1;
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
