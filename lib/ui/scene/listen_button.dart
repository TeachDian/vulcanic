import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/volcano_geometry.dart';
import '../../narration/narrator.dart';
import '../theme.dart';

/// Reads the selected component's description aloud, and stops it.
class ListenButton extends StatefulWidget {
  const ListenButton({super.key, required this.part});
  final VolcanoPart part;

  @override
  State<ListenButton> createState() => _ListenButtonState();
}

class _ListenButtonState extends State<ListenButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bars = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  final Narrator _narrator = Narrator.instance;

  @override
  void initState() {
    super.initState();
    _narrator.addListener(_sync);
  }

  @override
  void didUpdateWidget(ListenButton old) {
    super.didUpdateWidget(old);
    // Moving to another component ends the reading of the previous one.
    if (old.part != widget.part && _narrator.speaking == old.part) {
      _narrator.stop();
    }
  }

  @override
  void dispose() {
    _narrator.removeListener(_sync);
    if (_narrator.speaking == widget.part) _narrator.stop();
    _bars.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final speaking = _narrator.speaking == widget.part;
    if (speaking && !_bars.isAnimating) {
      _bars.repeat();
    } else if (!speaking && _bars.isAnimating) {
      _bars.stop();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final speaking = _narrator.speaking == widget.part;
    return Semantics(
      button: true,
      label: speaking ? 'Stop reading' : 'Listen to this description',
      excludeSemantics: true,
      child: Material(
        color: speaking ? Palette.ember : Palette.ember.withValues(alpha: 0.16),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            _narrator.toggle(widget.part);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 10,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: speaking
                      ? CustomPaint(painter: _Bars(_bars))
                      : const Icon(
                          Icons.volume_up_rounded,
                          size: 20,
                          color: Palette.ember,
                        ),
                ),
                Text(
                  speaking ? 'Stop' : 'Listen',
                  style: AppText.label.copyWith(
                    fontSize: 13.5,
                    color: speaking ? const Color(0xFF1A0E08) : Palette.ember,
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

/// A small level meter that moves while the narrator speaks.
class _Bars extends CustomPainter {
  _Bars(this.animation) : super(repaint: animation);
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A0E08)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const count = 4;
    for (var i = 0; i < count; i++) {
      final phase = animation.value * 2 * math.pi + i * 1.7;
      final level = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(phase));
      final x = size.width * (i + 0.5) / count;
      final half = size.height * 0.5 * level;
      canvas.drawLine(
        Offset(x, size.height / 2 - half),
        Offset(x, size.height / 2 + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Bars old) => old.animation != animation;
}
