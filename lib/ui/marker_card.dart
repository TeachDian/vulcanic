import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../content/markers.dart';
import 'theme.dart';

/// The printable marker: a card with the code the camera tracks.
///
/// Drawn in the app so the screen and the printed sheet are the same
/// artwork. It is always black on white, whatever the app theme, because
/// that is what a scanner reads best.
class MarkerCard extends StatelessWidget {
  const MarkerCard({super.key, required this.marker});
  final VulcanicMarker marker;

  static const Color _paper = Color(0xFFFFFFFF);
  static const Color _inkColor = Color(0xFF0B0C0E);

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1 / 1.28,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Everything scales with the card, so it prints at any size.
          final u = constraints.maxWidth / 100;
          TextStyle text(double size, double weight, {double spacing = 0}) =>
              TextStyle(
                fontFamily: AppText.family,
                fontSize: size * u,
                height: 1.15,
                letterSpacing: spacing * u,
                color: _inkColor,
                fontVariations: [FontVariation('wght', weight)],
              );
          return Container(
            decoration: BoxDecoration(
              color: _paper,
              borderRadius: BorderRadius.circular(5 * u),
            ),
            padding: EdgeInsets.all(7 * u),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.change_history_rounded,
                      size: 5 * u,
                      color: _inkColor,
                    ),
                    SizedBox(width: 2 * u),
                    Text('VULCANIC', style: text(3.2, 700, spacing: 0.9)),
                    const Spacer(),
                    Text(
                      'MARKER ${marker.number}',
                      style: text(3.2, 600, spacing: 0.6),
                    ),
                  ],
                ),
                SizedBox(height: 6 * u),
                MarkerCode(marker: marker),
                const Spacer(),
                Text(marker.title, style: text(7.5, 700, spacing: -0.2)),
                SizedBox(height: 1.2 * u),
                Text(
                  'Lay flat. Keep the whole code in view.',
                  style: text(
                    3.3,
                    450,
                  ).copyWith(color: _inkColor.withValues(alpha: 0.62)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The marker's code on its own, with the quiet zone a scanner needs and
/// nothing else. Fills the square it is given.
class MarkerCode extends StatelessWidget {
  const MarkerCode({super.key, required this.marker});
  final VulcanicMarker marker;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: CustomPaint(painter: _CodePainter(marker.payload)),
  );
}

/// Draws the QR code for [payload], with the quiet zone a scanner needs.
class _CodePainter extends CustomPainter {
  _CodePainter(this.payload)
    : _image = QrImage(
        QrCode(
          payload: QrPayload.fromString(payload),
          errorCorrectLevel: QrErrorCorrectLevel.high,
        ),
      );

  final String payload;
  final QrImage _image;

  @override
  void paint(Canvas canvas, Size size) {
    const quiet = 2; // modules of margin on each side
    final count = _image.moduleCount;
    final module = size.shortestSide / (count + quiet * 2);
    final paint = Paint()
      ..color = MarkerCard._inkColor
      ..isAntiAlias = false;
    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (!_image.isDark(row, col)) continue;
        // Overlap by a hair so no seams show between modules.
        canvas.drawRect(
          Rect.fromLTWH(
            (col + quiet) * module,
            (row + quiet) * module,
            module + 0.5,
            module + 0.5,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CodePainter old) => old.payload != payload;
}
