// Pumps the real screens at phone size. Besides checking that they build and
// respond, each test writes a PNG to build/renders/ for a visual check.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulcanic/engine/volcano_geometry.dart';
import 'package:vulcanic/ui/explorer_screen.dart';
import 'package:vulcanic/ui/guide_screen.dart';
import 'package:vulcanic/ui/home_screen.dart';
import 'package:vulcanic/ui/theme.dart';

final _shot = GlobalKey();

VolcanoGeometry loadGeometry() => VolcanoGeometry.fromSources({
  for (final part in VolcanoPart.values)
    part: File('assets/models/${part.asset}.obj').readAsStringSync(),
});

/// Loads the fonts the app ships with, so renders show real text and icons.
Future<void> loadFonts() async {
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(File(path).readAsBytesSync());
  await (FontLoader('Sora')..addFont(bytes('assets/fonts/Sora.ttf'))).load();
  final flutter = Platform.environment['FLUTTER_ROOT'];
  final icons = File(
    '$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (flutter != null && icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(bytes(icons.path))).load();
  }
}

Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(824, 1830),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _shot,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: screen,
      ),
    ),
  );
}

Future<void> advance(WidgetTester tester, double seconds) async {
  for (var i = 0; i < seconds * 30; i++) {
    await tester.pump(const Duration(milliseconds: 33));
  }
}

Future<void> save(WidgetTester tester, String name) async {
  final boundary =
      _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/renders')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  final geometry = loadGeometry();
  setUpAll(loadFonts);

  testWidgets('home offers the explorer and the guide', (tester) async {
    await pumpScreen(tester, HomeScreen(geometry: geometry));
    await advance(tester, 2);
    await save(tester, 'screen_home');
    expect(find.text('Explore in 3D'), findsOneWidget);
    expect(find.text('Surface'), findsOneWidget);
    expect(find.text('Marker'), findsOneWidget);

    await tester.tap(find.byTooltip('How it works'));
    await advance(tester, 1);
    expect(find.byType(GuideScreen), findsOneWidget);
    await save(tester, 'screen_guide');
  });

  testWidgets('explorer erupts, opens the cutaway and shows a component', (
    tester,
  ) async {
    await pumpScreen(tester, ExplorerScreen(geometry: geometry));
    await advance(tester, 1);
    await save(tester, 'screen_explorer');

    await tester.tap(find.bySemanticsLabel('Erupt eruption'));
    await advance(tester, 6);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Eruption'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Inside'));
    await advance(tester, 4);
    await save(tester, 'screen_explorer_erupting');

    // The rail opens the detail card for a component.
    await tester.tap(find.text('03'));
    await advance(tester, 1);
    expect(find.text('Magma chamber'), findsWidgets);
    expect(find.text('COMPONENT 03 OF 05'), findsOneWidget);
    await save(tester, 'screen_explorer_part');

    await tester.tap(find.byTooltip('Next component'));
    await advance(tester, 1);
    expect(find.text('COMPONENT 04 OF 05'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await advance(tester, 1);
    expect(find.text('COMPONENT 04 OF 05'), findsNothing);
    expect(find.text('Reset'), findsOneWidget);
  });

  testWidgets('the detail card fits a short screen', (tester) async {
    // 360 x 592 logical pixels; an overflow would fail the test.
    await pumpScreen(
      tester,
      ExplorerScreen(geometry: geometry),
      size: const Size(720, 1184),
    );
    await advance(tester, 1);
    await tester.tap(find.text('01'));
    await advance(tester, 1);
    expect(find.text('COMPONENT 01 OF 05'), findsOneWidget);
    await save(tester, 'screen_explorer_short');
  });
}
