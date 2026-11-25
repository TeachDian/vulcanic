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

/// The volcano on its own, with no camera: drag to orbit, pinch to zoom.
class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key, required this.geometry});
  final VolcanoGeometry geometry;

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  late final SceneRenderer _renderer = SceneRenderer(widget.geometry);
  final VolcanoController _controller = VolcanoController();
  final OrbitCamera _camera = OrbitCamera();
  double _zoom = 1;

  @override
  void dispose() {
    _renderer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDrag(SceneDrag drag) {
    _camera.orbit(
      -drag.delta.dx * 0.008 + drag.rotation,
      drag.delta.dy * 0.006,
    );
    _zoom = (_zoom / drag.scale).clamp(0.55, 1.7);
  }

  void _recentre() {
    final home = OrbitCamera();
    _camera
      ..azimuth = home.azimuth
      ..elevation = home.elevation;
    _zoom = 1;
  }

  SceneFrame _frame(Size size) {
    // Sit the model above the dock, and higher still above the detail card.
    _camera
      ..target.y = lerpDouble(-0.30, -0.95, _controller.selectionT)!
      ..distance = _camera.distanceToFit(size, radius: 1.16) * _zoom;
    return _camera.frame(size);
  }

  @override
  Widget build(BuildContext context) {
    return SceneChrome(
      controller: _controller,
      status: const StatusPill(
        label: '3D explorer',
        icon: Icons.threed_rotation_rounded,
      ),
      modeAction: DockAction(
        icon: Icons.filter_center_focus_rounded,
        label: 'Recentre',
        onPressed: _recentre,
      ),
      scene: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.25),
            radius: 1.05,
            colors: [Color(0xFF2A1A14), Palette.ink],
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
            labelStyle: Type.label,
          ),
        ),
      ),
    );
  }
}
