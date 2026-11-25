import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../engine/scene_frame.dart';
import '../engine/scene_renderer.dart';
import '../engine/volcano_controller.dart';
import '../engine/volcano_geometry.dart';
import '../engine/volcano_view.dart';
import 'scene/controls.dart';
import 'scene/scene_chrome.dart';
import 'scene/scene_gestures.dart';
import 'theme.dart';

/// The volcano on its own, with no camera: drag to turn and tilt, pinch to
/// zoom.
///
/// Turning and zooming go through the shared controller, exactly as in the
/// AR modes, so the app can steer the view here too (toward the cutaway,
/// toward a selected component). Only the tilt belongs to this screen: in AR
/// the phone itself decides how high the viewer is.
class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key, required this.geometry});
  final VolcanoGeometry geometry;

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  static const double _level = 22 * math.pi / 180;
  static const double _overhead = 56 * math.pi / 180;

  /// A lower viewpoint shows more of the cut faces and the chamber.
  static const double _intoOpening = 13 * math.pi / 180;

  late final SceneRenderer _renderer = SceneRenderer(widget.geometry);
  final VolcanoController _controller = VolcanoController();
  final OrbitCamera _camera = OrbitCamera(azimuth: kFrontAzimuth);

  /// The tilt the user chose, and where it is easing to.
  double _restingElevation = _level;
  double _elevationGoal = _level;
  bool _wasCutaway = false;
  double _lastClock = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _renderer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    // Follow the cutaway: look into the opening while it is open.
    if (_controller.cutaway == _wasCutaway) return;
    _wasCutaway = _controller.cutaway;
    _elevationGoal = _wasCutaway ? _intoOpening : _restingElevation;
  }

  void _onDrag(SceneDrag drag) {
    applyDragToModel(_controller, drag);
    if (drag.pointers == 1 && drag.delta.dy != 0) {
      _restingElevation = (_camera.elevation + drag.delta.dy * 0.006).clamp(
        OrbitCamera.minElevation,
        OrbitCamera.maxElevation,
      );
      _camera.elevation = _elevationGoal = _restingElevation;
    }
  }

  void _recentre() {
    _controller.resetTransform();
    _restingElevation = _level;
    _elevationGoal = _controller.cutaway ? _intoOpening : _level;
  }

  void _toggleTilt() {
    _restingElevation = _restingElevation > (_level + _overhead) / 2
        ? _level
        : _overhead;
    setState(() => _elevationGoal = _restingElevation);
  }

  SceneFrame _frame(Size size) {
    final dt = (_controller.clock - _lastClock).clamp(0.0, 0.1);
    _lastClock = _controller.clock;
    _camera
      ..elevation +=
          (_elevationGoal - _camera.elevation) * (1 - math.exp(-dt * 6.5))
      // Sit the model above the dock, and higher still above the detail card.
      ..target.y = lerpDouble(-0.30, -0.95, _controller.selectionT)!
      // Zoom moves the camera, which keeps the model's proportions honest.
      ..distance =
          _camera.distanceToFit(size, radius: 1.16) / _controller.scale;
    return _camera.frame(size, model: Matrix4.rotationY(_controller.rotation));
  }

  @override
  Widget build(BuildContext context) {
    final overhead = _restingElevation > (_level + _overhead) / 2;
    return SceneChrome(
      controller: _controller,
      viewActions: [
        ViewAction(
          icon: overhead
              ? Icons.landscape_outlined
              : Icons.flight_takeoff_rounded,
          tooltip: overhead ? 'View from the side' : 'View from above',
          onPressed: _toggleTilt,
        ),
        ViewAction(
          icon: Icons.filter_center_focus_rounded,
          tooltip: 'Recentre',
          onPressed: _recentre,
        ),
      ],
      scene: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.25),
            radius: 1.05,
            colors: [Color(0xFF1C2630), Palette.ink],
          ),
        ),
        child: SceneGestures(
          renderer: _renderer,
          controller: _controller,
          onDrag: _onDrag,
          child: VolcanoView(
            renderer: _renderer,
            controller: _controller,
            frameFor: _frame,
            labelStyle: AppText.label,
          ),
        ),
      ),
    );
  }
}
