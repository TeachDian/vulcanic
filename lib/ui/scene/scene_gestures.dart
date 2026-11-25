import 'package:flutter/material.dart';

import '../../engine/scene_renderer.dart';
import '../../engine/volcano_controller.dart';

/// One step of a drag, pinch or twist over the scene.
class SceneDrag {
  const SceneDrag({
    required this.delta,
    required this.scale,
    required this.rotation,
    required this.pointers,
  });

  /// Movement of the focal point since the last update, in logical pixels.
  final Offset delta;

  /// Pinch factor since the last update (1 means no change).
  final double scale;

  /// Twist since the last update, in radians.
  final double rotation;
  final int pointers;
}

/// Routes touches over the scene: taps select a labelled part, everything
/// else is reported to the host, which decides whether a drag moves the
/// camera (explorer) or the model (AR).
class SceneGestures extends StatefulWidget {
  const SceneGestures({
    super.key,
    required this.renderer,
    required this.controller,
    required this.onDrag,
    required this.child,
    this.onTapEmpty,
  });

  final SceneRenderer renderer;
  final VolcanoController controller;
  final ValueChanged<SceneDrag> onDrag;

  /// A tap that did not land on a label. When null, such a tap clears the
  /// selection.
  final ValueChanged<Offset>? onTapEmpty;
  final Widget child;

  @override
  State<SceneGestures> createState() => _SceneGesturesState();
}

class _SceneGesturesState extends State<SceneGestures> {
  double _lastScale = 1;
  double _lastRotation = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final controller = widget.controller;
        final part = widget.renderer.partAt(details.localPosition);
        if (part != null) {
          controller.select(part == controller.selected ? null : part);
        } else if (widget.onTapEmpty != null) {
          widget.onTapEmpty!(details.localPosition);
        } else {
          controller.select(null);
        }
      },
      onScaleStart: (_) {
        _lastScale = 1;
        _lastRotation = 0;
      },
      onScaleUpdate: (details) {
        widget.onDrag(
          SceneDrag(
            delta: details.focalPointDelta,
            scale: details.scale / _lastScale,
            rotation: details.rotation - _lastRotation,
            pointers: details.pointerCount,
          ),
        );
        _lastScale = details.scale;
        _lastRotation = details.rotation;
      },
      child: widget.child,
    );
  }
}

/// The standard AR interpretation of a drag: slide sideways to turn the
/// model, pinch to resize it, twist to turn it.
void applyDragToModel(VolcanoController controller, SceneDrag drag) {
  controller.holdStill();
  if (drag.pointers == 1) {
    controller.rotation += drag.delta.dx * 0.011;
  } else {
    controller.scale = controller.scale * drag.scale;
    controller.rotation -= drag.rotation;
  }
}
