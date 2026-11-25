import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../content/markers.dart';
import '../media/gallery.dart';
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
  final List<GlobalKey> _cards = [
    for (final _ in VulcanicMarker.values) GlobalKey(),
  ];
  String? _saved;

  /// Fills the screen with the marker on show.
  void _present() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) =>
            MarkerFullScreen(marker: VulcanicMarker.values[_page]),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  /// Saves the marker on show to the gallery, large enough to print.
  Future<void> _save() async {
    final marker = VulcanicMarker.values[_page];
    final boundary =
        _cards[_page].currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(
      pixelRatio: 1600 / boundary.size.width,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return;
    final name = await Gallery.savePng(
      data.buffer.asUint8List(),
      'vulcanic-marker-${marker.number}',
    );
    if (!mounted) return;
    setState(
      () => _saved = name == null
          ? 'Could not save the marker'
          : 'Saved to Pictures/Vulcanic',
    );
  }

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
              child: Row(
                children: [
                  BarButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  BarButton(
                    icon: Icons.fullscreen_rounded,
                    tooltip: 'Show this marker full screen',
                    onPressed: _present,
                  ),
                  BarButton(
                    icon: Icons.download_rounded,
                    tooltip: 'Save this marker to the gallery',
                    onPressed: _save,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Text('Markers', style: AppText.display),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Text(
                'Tap one to fill this screen with it, then point another '
                'phone at it. Or save it and print it.',
                style: AppText.body,
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (page) => setState(() {
                  _page = page;
                  _saved = null;
                }),
                children: [
                  for (final m in VulcanicMarker.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 20,
                      ),
                      child: Center(
                        child: GestureDetector(
                          onTap: _present,
                          child: RepaintBoundary(
                            key: _cards[m.index],
                            child: MarkerCard(marker: m),
                          ),
                        ),
                      ),
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
                          '${marker.number} / '
                          '${VulcanicMarker.values.length.toString().padLeft(2, '0')}',
                          style: AppText.caption,
                        ),
                        Text(
                          _saved ?? marker.caption,
                          style: AppText.bodyStrong,
                        ),
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
                            color: i == _page ? Palette.bone : Palette.raise,
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

/// The marker's code and nothing else, as large and as bright as the
/// screen allows, so this phone can stand in for a printout. Tap to leave.
class MarkerFullScreen extends StatefulWidget {
  const MarkerFullScreen({super.key, required this.marker});
  final VulcanicMarker marker;

  @override
  State<MarkerFullScreen> createState() => _MarkerFullScreenState();
}

class _MarkerFullScreenState extends State<MarkerFullScreen> {
  @override
  void initState() {
    super.initState();
    // Full brightness and no sleep. The system bars are left alone: hiding
    // them makes Android cover the code with its own "full screen" tip the
    // first time, and the code is as wide as the screen either way.
    Gallery.present(true);
  }

  @override
  void dispose() {
    Gallery.present(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Dark status icons, so the bar reads on white.
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        // White to the edges: it is the quiet zone a scanner looks for,
        // and it lights the code evenly.
        backgroundColor: Colors.white,
        body: Semantics(
          label:
              'Marker ${widget.marker.number}, ${widget.marker.title}. '
              'Tap to close.',
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: MarkerCode(marker: widget.marker),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
