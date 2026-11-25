import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'scene_frame.dart';
import 'scene_renderer.dart';
import 'volcano_controller.dart';
import 'volcano_geometry.dart';

/// Paints the volcano and keeps its animations running.
///
/// The host decides where the camera and the model are by returning a
/// [SceneFrame] from [frameFor] each time the view paints. Returning null
/// draws nothing, which is how AR modes hide the model before placement.
class VolcanoView extends StatefulWidget {
  const VolcanoView({
    super.key,
    required this.renderer,
    required this.controller,
    required this.frameFor,
    this.labelStyle,
    this.animate = true,
  });

  final SceneRenderer renderer;
  final VolcanoController controller;
  final SceneFrame? Function(Size size) frameFor;
  final TextStyle? labelStyle;

  /// Set to false to freeze the scene (used by tests).
  final bool animate;

  @override
  State<VolcanoView> createState() => _VolcanoViewState();
}

class _VolcanoViewState extends State<VolcanoView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  VolcanoGeometry get _geometry => widget.renderer.geometry;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      widget.controller.tick(dt, _geometry.vent);
    });
    if (widget.animate) _ticker.start();
  }

  @override
  void didUpdateWidget(VolcanoView old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!widget.animate && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ScenePainter(
          widget.renderer,
          widget.controller,
          widget.frameFor,
          widget.labelStyle,
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.renderer, this.controller, this.frameFor, this.labelStyle)
    : super(repaint: controller.frame);

  final SceneRenderer renderer;
  final VolcanoController controller;
  final SceneFrame? Function(Size size) frameFor;
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = frameFor(size);
    if (frame == null) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    renderer.paint(canvas, size, frame, controller, labelStyle: labelStyle);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.renderer != renderer ||
      old.controller != controller ||
      old.frameFor != frameFor ||
      old.labelStyle != labelStyle;
}
