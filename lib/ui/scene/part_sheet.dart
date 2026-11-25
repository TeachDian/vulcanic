import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../content/parts.dart';
import '../../engine/volcano_controller.dart';
import '../../engine/volcano_geometry.dart';
import '../theme.dart';

/// The sheet for the selected component: its name, what it does, and a
/// few facts as a small table.
class PartSheet extends StatefulWidget {
  const PartSheet({
    super.key,
    required this.part,
    required this.controller,
    this.leading,
    this.bottomInset = 0,
  });

  final VolcanoPart part;
  final VolcanoController controller;

  /// Optional action at the start of the footer (the narrator).
  final Widget? leading;

  /// System inset under the sheet, which runs to the screen's edge.
  final double bottomInset;

  @override
  State<PartSheet> createState() => _PartSheetState();
}

class _PartSheetState extends State<PartSheet>
    with SingleTickerProviderStateMixin {
  /// Brings the sheet's lines in one after another, on arrival and
  /// whenever the component changes.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  VolcanoPart get part => widget.part;
  VolcanoController get controller => widget.controller;

  @override
  void didUpdateWidget(PartSheet old) {
    super.didUpdateWidget(old);
    if (old.part != widget.part) _entrance.forward(from: 0);
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// Wraps [child] so that it fades and rises as the [order]-th line.
  Widget _line(int order, Widget child) {
    final start = 0.10 * order;
    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Interval(
        start,
        (start + 0.55).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.35),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  void _step(int by) {
    HapticFeedback.selectionClick();
    final parts = VolcanoPart.values;
    controller.select(parts[(part.index + by) % parts.length]);
  }

  @override
  Widget build(BuildContext context) {
    final info = part.info;
    final total = VolcanoPart.values.length.toString().padLeft(2, '0');
    return GestureDetector(
      // Flick the sheet down to dismiss it.
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 250) controller.select(null);
      },
      child: Panel(
        opacity: 1,
        radius: const BorderRadius.vertical(top: Radius.circular(26)),
        padding: EdgeInsets.fromLTRB(22, 10, 12, widget.bottomInset + 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Palette.raise,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  '${part.number} / $total',
                  style: AppText.caption.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => controller.select(null),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, size: 21),
                  color: Palette.ash,
                ),
              ],
            ),
            _line(0, Text(part.label, style: AppText.headline)),
            const SizedBox(height: 10),
            Flexible(
              child: _line(
                1,
                SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(info.summary, style: AppText.body),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                children: [
                  for (final (i, fact) in info.facts.indexed)
                    _line(2 + i, _FactRow(fact)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                ?widget.leading,
                const Spacer(),
                IconButton(
                  onPressed: () => _step(VolcanoPart.values.length - 1),
                  tooltip: 'Previous component',
                  icon: const Icon(Icons.arrow_back_rounded, size: 21),
                  color: Palette.bone,
                ),
                IconButton(
                  onPressed: () => _step(1),
                  tooltip: 'Next component',
                  icon: const Icon(Icons.arrow_forward_rounded, size: 21),
                  color: Palette.bone,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One fact: what it is on the left, the value on the right.
class _FactRow extends StatelessWidget {
  const _FactRow(this.fact);
  final Fact fact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Palette.line())),
      ),
      child: Row(
        spacing: 16,
        children: [
          Text(fact.label, style: AppText.caption.copyWith(fontSize: 13)),
          Expanded(
            child: Text(
              fact.value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
