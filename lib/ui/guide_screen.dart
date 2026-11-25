import 'package:flutter/material.dart';

import 'scene/controls.dart';
import 'theme.dart';

/// One illustrated instruction.
class GuideStep {
  const GuideStep(this.icon, this.title, this.detail);
  final IconData icon;
  final String title;
  final String detail;
}

/// A titled group of steps.
class GuideSection {
  const GuideSection(this.overline, this.title, this.steps);
  final String overline;
  final String title;
  final List<GuideStep> steps;
}

const List<GuideSection> guideSections = [
  GuideSection('SURFACE · MARKERLESS', 'Stand it on a table', [
    GuideStep(
      Icons.screen_rotation_alt_rounded,
      'Scan the surface',
      'Point at a table or floor and move the phone slowly. A lit, '
          'patterned surface is found fastest.',
    ),
    GuideStep(
      Icons.grid_on_rounded,
      'Wait for the grid',
      'Detected surfaces are outlined, and a ring shows where the volcano '
          'would stand.',
    ),
    GuideStep(
      Icons.touch_app_rounded,
      'Tap to place',
      'The volcano is anchored there. Walk around it; Move lets you place '
          'it again.',
    ),
    GuideStep(
      Icons.phonelink_erase_rounded,
      'No AR on your phone?',
      'The app switches to screen placement: tap anywhere to put the '
          'volcano there.',
    ),
  ]),
  GuideSection('MARKER · MARKER-BASED', 'Stand it on the marker', [
    GuideStep(
      Icons.print_rounded,
      'Get a marker',
      'Print one from the project, or open Markers in this app on a second '
          'screen.',
    ),
    GuideStep(
      Icons.center_focus_weak_rounded,
      'Point the camera at it',
      'Keep the whole code in view. An outline shows that it is recognised.',
    ),
    GuideStep(
      Icons.open_with_rounded,
      'Move the marker',
      'The volcano follows it. Cover the marker or take it away and the '
          'volcano fades until it is back.',
    ),
    GuideStep(
      Icons.filter_2_rounded,
      'Try the second marker',
      'Each marker shows its own content: marker 02 opens the cutaway.',
    ),
  ]),
  GuideSection('ONCE IT IS PLACED', 'Handle the volcano', [
    GuideStep(
      Icons.swipe_rounded,
      'Drag to turn it',
      'Slide one finger sideways to look at it from any side.',
    ),
    GuideStep(
      Icons.pinch_rounded,
      'Pinch to resize',
      'Two fingers make it larger or smaller.',
    ),
    GuideStep(
      Icons.rotate_90_degrees_cw_outlined,
      'Or use the view buttons',
      'Plus and minus zoom; the turn button shows the next side. The view '
          'also turns by itself to whatever you open or select.',
    ),
    GuideStep(
      Icons.play_circle_outline_rounded,
      'Set it off',
      'Erupt plays the sequence. Tap again to pause it.',
    ),
    GuideStep(
      Icons.pie_chart_outline_rounded,
      'Look inside',
      'Inside opens a cutaway down to the magma chamber.',
    ),
    GuideStep(
      Icons.sell_outlined,
      'Tap a label',
      'Each of the five components has a short explanation.',
    ),
  ]),
];

/// Instructions for every mode, as a single scrolling page.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GlassIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
              sliver: SliverToBoxAdapter(
                child: Text('How it\nworks', style: AppText.display),
              ),
            ),
            for (final section in guideSections)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                sliver: SliverToBoxAdapter(child: _SectionCard(section)),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(this.section);
  final GuideSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      decoration: BoxDecoration(
        color: Palette.basalt,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Palette.line(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.overline, style: AppText.overline),
          const SizedBox(height: 6),
          Text(section.title, style: AppText.headline),
          const SizedBox(height: 12),
          for (final (i, step) in section.steps.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 16,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Palette.slate,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(step.icon, color: Palette.bone, size: 24),
                      ),
                      Positioned(
                        right: -5,
                        top: -5,
                        child: Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Palette.ember,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${i + 1}',
                            style: AppText.label.copyWith(
                              fontSize: 10.5,
                              color: const Color(0xFF1A0E08),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        const SizedBox(height: 4),
                        Text(step.title, style: AppText.title),
                        Text(
                          step.detail,
                          style: AppText.body.copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
