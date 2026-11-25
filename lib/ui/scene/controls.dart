import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/eruption.dart';
import '../../engine/volcano_controller.dart';
import '../../engine/volcano_geometry.dart';
import '../theme.dart';

/// A circular glass button, used along the top of every scene.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
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
    return Glass(
      radius: 24,
      child: SizedBox.square(
        dimension: 48,
        child: IconButton(
          icon: Icon(icon, size: 22),
          color: Palette.bone,
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// One of the small labelled actions in the dock.
class DockAction {
  const DockAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Toggles are drawn filled while on.
  final bool active;
}

class _DockButton extends StatelessWidget {
  const _DockButton(this.action);
  final DockAction action;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onPressed != null;
    final foreground = action.active ? Palette.ink : Palette.bone;
    return Semantics(
      button: true,
      toggled: action.active,
      label: action.label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: InkResponse(
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  action.onPressed!();
                }
              : null,
          radius: 34,
          child: SizedBox(
            width: 60,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: action.active
                        ? Palette.bone
                        : Colors.white.withValues(alpha: 0.07),
                    border: Border.all(
                      color: Palette.line(action.active ? 0 : 0.10),
                    ),
                  ),
                  child: Icon(action.icon, size: 21, color: foreground),
                ),
                const SizedBox(height: 6),
                Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: Type.caption.copyWith(
                    fontSize: 10.5,
                    color: action.active ? Palette.bone : Palette.ash,
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

/// The eruption trigger: a large ember button ringed by its own progress.
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
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          controller.toggleEruption();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 76,
              child: CustomPaint(
                painter: _ProgressRing(controller),
                child: Center(
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: Palette.emberGradient,
                      boxShadow: [
                        BoxShadow(
                          color: Palette.ember.withValues(alpha: 0.45),
                          blurRadius: 24,
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 32, color: const Color(0xFF1A0E08)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: Type.label.copyWith(fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

class _ProgressRing extends CustomPainter {
  _ProgressRing(this.controller) : super(repaint: controller.frame);
  final VolcanoController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Palette.line(0.12);
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    final progress = controller.eruption.progress;
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      track
        ..color = Palette.glow
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ProgressRing old) => old.controller != controller;
}

/// The floating control bar: two view toggles, the eruption trigger, one
/// action that belongs to the current mode, and reset.
class ControlDock extends StatelessWidget {
  const ControlDock({super.key, required this.controller, this.modeAction});

  final VolcanoController controller;
  final DockAction? modeAction;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Glass(
        radius: 36,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _DockButton(
              DockAction(
                icon: Icons.pie_chart_outline_rounded,
                label: 'Inside',
                active: controller.cutaway,
                onPressed: () => controller.cutaway = !controller.cutaway,
              ),
            ),
            _DockButton(
              DockAction(
                icon: Icons.sell_outlined,
                label: 'Labels',
                active: controller.labels,
                onPressed: () => controller.labels = !controller.labels,
              ),
            ),
            EruptButton(controller: controller),
            if (modeAction != null)
              _DockButton(modeAction!)
            else
              const SizedBox(width: 60),
            _DockButton(
              DockAction(
                icon: Icons.restart_alt_rounded,
                label: 'Reset',
                onPressed: controller.reset,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The four steps of the eruption, filling as the sequence plays.
class PhaseStrip extends StatelessWidget {
  const PhaseStrip({super.key, required this.controller});
  final VolcanoController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final phase = controller.eruption.phase;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
          child: phase == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: Row(
                    spacing: 6,
                    children: [
                      for (final step in EruptionPhase.values)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 7,
                            children: [
                              SizedBox(
                                height: 3,
                                width: double.infinity,
                                child: CustomPaint(
                                  painter: _PhaseBar(controller, step),
                                ),
                              ),
                              Text(
                                step.label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.fade,
                                style: Type.caption.copyWith(
                                  fontSize: 10.5,
                                  color: step == phase
                                      ? Palette.bone
                                      : Palette.smoke,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  static double _end(EruptionPhase step) =>
      step.index + 1 < EruptionPhase.values.length
      ? EruptionPhase.values[step.index + 1].start
      : Eruption.duration;

  static double _length(EruptionPhase step) => _end(step) - step.start;
}

class _PhaseBar extends CustomPainter {
  _PhaseBar(this.controller, this.step) : super(repaint: controller.frame);
  final VolcanoController controller;
  final EruptionPhase step;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    final time = controller.eruption.time;
    final fill = ((time - step.start) / PhaseStrip._length(step)).clamp(
      0.0,
      1.0,
    );
    if (fill <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width * fill, size.height),
        radius,
      ),
      Paint()..color = Palette.glow,
    );
  }

  @override
  bool shouldRepaint(_PhaseBar old) =>
      old.controller != controller || old.step != step;
}

/// Numbered shortcuts to the five components, matching the labels on the
/// model.
class PartRail extends StatelessWidget {
  const PartRail({super.key, required this.controller});
  final VolcanoController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Glass(
        radius: 26,
        padding: const EdgeInsets.all(5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            for (final part in VolcanoPart.values)
              _RailButton(
                part: part,
                selected: controller.selected == part,
                onTap: () {
                  HapticFeedback.selectionClick();
                  controller.select(controller.selected == part ? null : part);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.part,
    required this.selected,
    required this.onTap,
  });

  final VolcanoPart part;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: part.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? Palette.ember : Colors.transparent,
          ),
          child: Text(
            part.number,
            style: Type.label.copyWith(
              fontSize: 12,
              color: selected ? const Color(0xFF1A0E08) : Palette.ash,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
