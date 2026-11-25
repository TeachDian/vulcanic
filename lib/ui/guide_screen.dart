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
  GuideSection('Surface', 'On a surface', [
    GuideStep(
      Icons.screen_rotation_alt_rounded,
      'Scan',
      'Point at a table or floor and move the phone slowly.',
    ),
    GuideStep(
      Icons.touch_app_rounded,
      'Tap to place',
      'A ring shows where it will stand. Walk around it once it is down.',
    ),
    GuideStep(
      Icons.phonelink_erase_rounded,
      'No AR on this phone',
      'Tap anywhere on the camera view to put the volcano there.',
    ),
  ]),
  GuideSection('Marker', 'On a marker', [
    GuideStep(
      Icons.qr_code_2_rounded,
      'Get a marker',
      'Print one, or open Markers on a second screen.',
    ),
    GuideStep(
      Icons.center_focus_weak_rounded,
      'Point the camera at it',
      'The volcano stands on the marker and follows it. Marker 02 opens '
          'the cutaway.',
    ),
  ]),
  GuideSection('Controls', 'The volcano', [
    GuideStep(
      Icons.swipe_rounded,
      'Drag and pinch',
      'Drag to turn it, pinch to resize. The buttons at the side do the '
          'same.',
    ),
    GuideStep(
      Icons.play_arrow_rounded,
      'Erupt',
      'Plays the sequence. Tap again to pause.',
    ),
    GuideStep(
      Icons.pie_chart_outline_rounded,
      'Look inside',
      'Opens a cutaway down to the magma chamber.',
    ),
    GuideStep(
      Icons.radio_button_checked_rounded,
      'Tap a pin',
      'Each of the five components has a short explanation you can hear.',
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
                  child: BarButton(
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
                child: Text('How it works', style: AppText.display),
              ),
            ),
            for (final section in guideSections)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 0),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(section.title, style: AppText.headline),
        const SizedBox(height: 6),
        for (final step in section.steps)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Palette.line())),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(step.icon, color: Palette.bone, size: 22),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 3,
                    children: [
                      Text(step.title, style: AppText.title),
                      Text(step.detail, style: AppText.body),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
