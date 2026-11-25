import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/eruption.dart';
import '../../engine/volcano_controller.dart';
import '../theme.dart';

/// A plain icon button for the top bar. It has no container of its own;
/// a soft shadow keeps it readable over the camera.
class BarButton extends StatelessWidget {
  const BarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 23, shadows: AppText.overCamera),
        color: Palette.bone,
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

/// A button in the view rail.
class ViewAction {
  const ViewAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Drawn filled while a mode it switches on is in effect.
  final bool active;
}

/// Buttons that move the view without a gesture: zoom in, zoom out and a
/// quarter turn, followed by whatever the current mode adds.
class ViewRail extends StatelessWidget {
  const ViewRail({super.key, required this.controller, this.extra = const []});

  final VolcanoController controller;
  final List<ViewAction> extra;

  @override
  Widget build(BuildContext context) {
    final actions = [
      ViewAction(
        icon: Icons.add_rounded,
        tooltip: 'Zoom in',
        onPressed: () => controller.zoomBy(1.25),
      ),
      ViewAction(
        icon: Icons.remove_rounded,
        tooltip: 'Zoom out',
        onPressed: () => controller.zoomBy(1 / 1.25),
      ),
      ViewAction(
        icon: Icons.rotate_90_degrees_cw_outlined,
        tooltip: 'Turn to the next side',
        onPressed: () => controller.turnBy(math.pi / 2),
      ),
      ...extra,
    ];
    return Panel(
      radius: const BorderRadius.all(Radius.circular(14)),
      opacity: 0.72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, action) in actions.indexed) ...[
            if (i > 0) Container(width: 40, height: 1, color: Palette.line()),
            SizedBox.square(
              dimension: 40,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(action.icon, size: 20),
                color: action.active ? Palette.onBone : Palette.bone,
                style: action.active
                    ? IconButton.styleFrom(backgroundColor: Palette.bone)
                    : null,
                tooltip: action.tooltip,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  action.onPressed();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The one place for controls: the eruption's trace and trigger, with the
/// two view toggles either side.
class Console extends StatelessWidget {
  const Console({super.key, required this.controller});
  final VolcanoController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final phase = controller.eruption.phase;
        final changed = phase != null || controller.transformed;
        return Panel(
          radius: const BorderRadius.all(Radius.circular(24)),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 34,
                child: Row(
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(painter: _Seismograph(controller)),
                          // The only caption: which step is playing.
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: phase == null ? 0 : 1,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                phase?.label ?? '',
                                style: AppText.caption.copyWith(fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: changed ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !changed,
                        child: SizedBox.square(
                          dimension: 34,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.restart_alt_rounded,
                              size: 20,
                            ),
                            color: Palette.ash,
                            tooltip: 'Reset',
                            onPressed: controller.reset,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Toggle(
                    icon: Icons.pie_chart_outline_rounded,
                    label: 'Inside',
                    active: controller.cutaway,
                    onPressed: () => controller.cutaway = !controller.cutaway,
                  ),
                  EruptButton(controller: controller),
                  _Toggle(
                    icon: Icons.sell_outlined,
                    label: 'Labels',
                    active: controller.labels,
                    onPressed: () => controller.labels = !controller.labels,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// An icon-only switch. Its name is there for screen readers and as a
/// long-press tooltip, not as a caption.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: active,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkResponse(
          radius: 30,
          onTap: () {
            HapticFeedback.selectionClick();
            onPressed();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Palette.raise : Colors.transparent,
            ),
            child: Icon(
              icon,
              size: 22,
              color: active ? Palette.bone : Palette.ash,
            ),
          ),
        ),
      ),
    );
  }
}

/// The eruption trigger: the one filled button on the screen.
class EruptButton extends StatelessWidget {
  const EruptButton({super.key, required this.controller});
  final VolcanoController controller;

  @override
  Widget build(BuildContext context) {
    final eruption = controller.eruption;
    final String label;
    final IconData icon;
    if (eruption.running) {
      label = 'Pause';
      icon = Icons.pause_rounded;
    } else if (eruption.dormant) {
      label = 'Erupt';
      icon = Icons.play_arrow_rounded;
    } else if (eruption.finished) {
      label = 'Replay';
      icon = Icons.replay_rounded;
    } else {
      label = 'Resume';
      icon = Icons.play_arrow_rounded;
    }
    return Semantics(
      button: true,
      label: '$label eruption',
      excludeSemantics: true,
      child: Material(
        color: Palette.bone,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            controller.toggleEruption();
          },
          child: SizedBox(
            height: 48,
            width: 132,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 6,
              children: [
                Icon(icon, size: 22, color: Palette.onBone),
                Text(
                  label,
                  style: AppText.label.copyWith(
                    fontSize: 14.5,
                    color: Palette.onBone,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The eruption drawn as a seismograph trace: calm while the volcano is
/// quiet, rough where the ground shakes. The played part is bright and a
/// playhead in heat colour marks the moment.
class _Seismograph extends CustomPainter {
  _Seismograph(this.controller) : super(repaint: controller.frame);
  final VolcanoController controller;

  /// A probe used only to read how violent each moment of the sequence is.
  static final Eruption _probe = Eruption();

  static double _violence(double time) {
    _probe.time = time;
    return 0.9 * _probe.tremor + 0.45 * _probe.plume + 0.25 * _probe.fragments;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final time = controller.eruption.time;
    final mid = size.height * 0.62;
    final reach = size.height * 0.36;
    final played = Path(), ahead = Path();
    final playheadX = size.width * time / Eruption.duration;
    var startedPlayed = false, startedAhead = false;
    for (var x = 0.0; x <= size.width; x += 2) {
      final t = x / size.width * Eruption.duration;
      // Two detuned sines read as a needle scratching, and never change
      // from frame to frame.
      final wobble = math.sin(x * 1.31) * 0.6 + math.sin(x * 0.47 + 1.3) * 0.4;
      final y = mid + wobble * (0.6 + reach * _violence(t));
      if (x <= playheadX) {
        startedPlayed ? played.lineTo(x, y) : played.moveTo(x, y);
        startedPlayed = true;
      }
      if (x >= playheadX - 2) {
        startedAhead ? ahead.lineTo(x, y) : ahead.moveTo(x, y);
        startedAhead = true;
      }
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      ahead,
      stroke..color = Palette.bone.withValues(alpha: 0.26),
    );
    if (time > 0) {
      canvas.drawPath(played, stroke..color = Palette.bone);
      canvas.drawLine(
        Offset(playheadX, size.height * 0.28),
        Offset(playheadX, size.height),
        Paint()
          ..color = Palette.heat
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_Seismograph old) => old.controller != controller;
}
