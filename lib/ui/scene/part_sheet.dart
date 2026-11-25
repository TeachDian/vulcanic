import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../content/parts.dart';
import '../../engine/volcano_controller.dart';
import '../../engine/volcano_geometry.dart';
import '../theme.dart';

/// The detail card for the selected component.
class PartSheet extends StatelessWidget {
  const PartSheet({
    super.key,
    required this.part,
    required this.controller,
    this.leading,
  });

  final VolcanoPart part;
  final VolcanoController controller;

  /// Optional action shown at the start of the footer (the narrator).
  final Widget? leading;

  void _step(int by) {
    HapticFeedback.selectionClick();
    final parts = VolcanoPart.values;
    controller.select(parts[(part.index + by) % parts.length]);
  }

  @override
  Widget build(BuildContext context) {
    final info = part.info;
    return GestureDetector(
      // Flick the card down to dismiss it.
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 250) controller.select(null);
      },
      child: Glass(
        radius: 32,
        tint: 0.78,
        padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Palette.ember.withValues(alpha: 0.16),
                  ),
                  child: Icon(info.icon, color: Palette.ember, size: 23),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 5,
                    children: [
                      Text(
                        'COMPONENT ${part.number} OF '
                        '${VolcanoPart.values.length.toString().padLeft(2, '0')}',
                        style: Type.overline,
                      ),
                      Text(part.label, style: Type.headline),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => controller.select(null),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, size: 22),
                  color: Palette.ash,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Text(info.tagline, style: Type.bodyStrong),
                  Text(info.description, style: Type.body),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 54,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: info.facts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => _FactChip(info.facts[i]),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ?leading,
                const Spacer(),
                IconButton(
                  onPressed: () => _step(VolcanoPart.values.length - 1),
                  tooltip: 'Previous component',
                  icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  color: Palette.bone,
                ),
                IconButton(
                  onPressed: () => _step(1),
                  tooltip: 'Next component',
                  icon: const Icon(Icons.arrow_forward_rounded, size: 22),
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

class _FactChip extends StatelessWidget {
  const _FactChip(this.fact);
  final Fact fact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          Icon(fact.icon, size: 18, color: Palette.glow),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(fact.label, style: Type.caption.copyWith(fontSize: 10.5)),
              Text(fact.value, style: Type.label),
            ],
          ),
        ],
      ),
    );
  }
}
