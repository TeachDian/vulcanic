// Renders the scene off screen. Besides guarding against regressions in the
// painter, it writes PNGs to build/renders/ for a quick visual check.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulcanic/engine/scene_frame.dart';
import 'package:vulcanic/engine/scene_renderer.dart';
import 'package:vulcanic/engine/volcano_controller.dart';
import 'package:vulcanic/engine/volcano_geometry.dart';

VolcanoGeometry loadGeometry() => VolcanoGeometry.fromSources({
  for (final part in VolcanoPart.values)
    part: File('assets/models/${part.asset}.obj').readAsStringSync(),
});

Future<ui.Image> render(
  WidgetTester tester,
  SceneRenderer renderer,
  VolcanoController controller,
  OrbitCamera camera, {
  Size size = const Size(540, 720),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF14161A));
  renderer.paint(canvas, size, camera.frame(size), controller);
  final picture = recorder.endRecording();
  return picture.toImageSync(size.width.toInt(), size.height.toInt());
}

Future<void> save(WidgetTester tester, ui.Image image, String name) async {
  await tester.runAsync(() async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/renders')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<int> litPixels(WidgetTester tester, ui.Image image) async {
  var lit = 0;
  await tester.runAsync(() async {
    final data = (await image.toByteData())!;
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      if (data.getUint8(i) > 0x30 || data.getUint8(i + 1) > 0x30) lit++;
    }
  });
  return lit;
}

void main() {
  final geometry = loadGeometry();

  testWidgets('dormant volcano covers a good part of the frame', (
    tester,
  ) async {
    final renderer = SceneRenderer(geometry);
    final controller = VolcanoController();
    for (var i = 0; i < 120; i++) {
      controller.tick(1 / 60, geometry.vent);
    }
    final image = await render(tester, renderer, controller, OrbitCamera());
    await save(tester, image, 'dormant');
    expect(await litPixels(tester, image), greaterThan(540 * 720 * 0.12));
    expect(renderer.bounds, isNotNull);
    expect(renderer.partAt(Offset.zero), isNull);
  });

  testWidgets('cutaway and eruption render', (tester) async {
    final renderer = SceneRenderer(geometry);
    final controller = VolcanoController()..cutaway = true;
    controller.toggleEruption();
    final shots = {5.0: 'erupting', 10.0: 'flowing', 17.5: 'cooling'};
    var time = 0.0;
    for (final entry in shots.entries) {
      while (time < entry.key) {
        controller.tick(1 / 30, geometry.vent);
        time += 1 / 30;
      }
      final image = await render(tester, renderer, controller, OrbitCamera());
      await save(tester, image, entry.value);
      expect(await litPixels(tester, image), greaterThan(540 * 720 * 0.12));
    }
    expect(controller.eruption.phase, isNotNull);

    // From the far side, and from above.
    final back = await render(
      tester,
      renderer,
      controller,
      OrbitCamera(azimuth: 4.2, elevation: 0.5),
    );
    await save(tester, back, 'back');
    final top = await render(
      tester,
      renderer,
      controller,
      OrbitCamera(azimuth: 0.8, elevation: 1.2),
    );
    await save(tester, top, 'top');
  });

  testWidgets('labels are hit-testable', (tester) async {
    final renderer = SceneRenderer(geometry);
    final controller = VolcanoController()..cutaway = true;
    for (var i = 0; i < 60; i++) {
      controller.tick(1 / 30, geometry.vent);
    }
    final image = await render(tester, renderer, controller, OrbitCamera());
    await save(tester, image, 'labels');
    final anchor = renderer.bounds!.center;
    // Every part has a label in the default view with the cutaway open.
    var found = 0;
    for (var y = 0.0; y < 720; y += 6) {
      for (var x = 0.0; x < 540; x += 6) {
        if (renderer.partAt(Offset(x, y)) != null) found++;
      }
    }
    expect(found, greaterThan(40));
    expect(anchor.dx, inInclusiveRange(100, 440));
  });
}
