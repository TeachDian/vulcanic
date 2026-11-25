import 'package:flutter/material.dart';

import '../content/markers.dart';
import 'marker_card.dart';
import 'scene/controls.dart';
import 'theme.dart';

/// Shows the markers full size, to scan from a second screen or to check
/// against a print.
class MarkerCardScreen extends StatefulWidget {
  const MarkerCardScreen({super.key});

  @override
  State<MarkerCardScreen> createState() => _MarkerCardScreenState();
}

class _MarkerCardScreenState extends State<MarkerCardScreen> {
  final PageController _pages = PageController(viewportFraction: 0.86);
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final marker = VulcanicMarker.values[_page];
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GlassIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Text('Markers', style: AppText.display),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Text(
                'Print one, or show it on another screen and point this '
                'phone at it.',
                style: AppText.body,
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  for (final m in VulcanicMarker.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 20,
                      ),
                      child: Center(child: MarkerCard(marker: m)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        Text(
                          'MARKER ${marker.number} OF '
                          '${VulcanicMarker.values.length.toString().padLeft(2, '0')}',
                          style: AppText.overline,
                        ),
                        Text(marker.caption, style: AppText.bodyStrong),
                      ],
                    ),
                  ),
                  Row(
                    spacing: 6,
                    children: [
                      for (var i = 0; i < VulcanicMarker.values.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: i == _page ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _page ? Palette.ember : Palette.slate,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
