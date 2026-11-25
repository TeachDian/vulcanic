import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vulcanic/ar/ar_session.dart';

/// Builds a packet the way `ArSessionRunner.buildPacket` does.
Float32List packet({
  bool tracking = true,
  int issue = 0,
  double light = 0.5,
  int anchor = 0,
  bool reticle = false,
  List<List<double>> planes = const [],
  List<double> points = const [],
}) {
  final out = <double>[
    tracking ? 1 : 0,
    issue.toDouble(),
    light,
    anchor.toDouble(),
    reticle ? 1 : 0,
    planes.length.toDouble(),
    points.length / 3,
    0,
  ];
  // view, projection, anchor, reticle: identity scaled 1..4 to tell apart.
  for (var k = 1; k <= 4; k++) {
    for (var i = 0; i < 16; i++) {
      out.add(i % 5 == 0 ? k.toDouble() : 0);
    }
  }
  for (final plane in planes) {
    out
      ..add(plane.length / 3)
      ..addAll(plane);
  }
  out.addAll(points);
  return Float32List.fromList(out);
}

void main() {
  test('decodes the header and matrices', () {
    final f = ArFrame.parse(packet(anchor: 1, reticle: true, issue: 3));
    expect(f.tracking, isTrue);
    expect(f.issue, TrackingIssue.excessiveMotion);
    expect(f.light, closeTo(0.5, 1e-6));
    expect(f.anchorState, AnchorState.tracking);
    expect(f.view.entry(0, 0), 1);
    expect(f.projection.entry(1, 1), 2);
    expect(f.anchor!.entry(2, 2), 3);
    expect(f.reticle!.entry(3, 3), 4);
  });

  test('omits poses that are not valid', () {
    final f = ArFrame.parse(packet(tracking: false, light: -1, anchor: 2));
    expect(f.tracking, isFalse);
    expect(f.light, isNull);
    expect(f.anchorState, AnchorState.lost);
    expect(f.anchor, isNull);
    expect(f.reticle, isNull);
    expect(f.planes, isEmpty);
    expect(f.points, isEmpty);
  });

  test('decodes planes of different sizes, then feature points', () {
    final f = ArFrame.parse(
      packet(
        planes: [
          [0, 0, 0, 1, 0, 0, 1, 0, 1],
          [5, 1, 5, 6, 1, 5, 6, 1, 6, 5, 1, 6],
        ],
        points: [9, 8, 7, 6, 5, 4],
      ),
    );
    expect(f.planes, hasLength(2));
    expect(f.planes[0], hasLength(9));
    expect(f.planes[1], hasLength(12));
    expect(f.planes[1].last, 6);
    expect(f.points, [9, 8, 7, 6, 5, 4]);
  });

  test('tolerates unknown codes from a newer ARCore', () {
    final f = ArFrame.parse(packet(issue: 99, anchor: 7));
    expect(f.issue, TrackingIssue.cameraUnavailable);
    expect(f.anchorState, AnchorState.lost);
  });
}
