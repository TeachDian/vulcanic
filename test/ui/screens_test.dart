// Pumps the real screens at phone size. Besides checking that they build and
// respond, each test writes a PNG to build/renders/ for a visual check.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulcanic/engine/volcano_controller.dart';
import 'package:vulcanic/engine/volcano_geometry.dart';
import 'package:vulcanic/engine/volcano_view.dart';
import 'package:vulcanic/ui/explorer_screen.dart';
import 'package:vulcanic/ui/guide_screen.dart';
import 'package:vulcanic/content/markers.dart';
import 'package:vulcanic/ui/home_screen.dart';
import 'package:vulcanic/ui/marker_card.dart';
import 'package:vulcanic/ui/marker_card_screen.dart';
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
  await (FontLoader(
    'Archivo',
  )..addFont(bytes('assets/fonts/Archivo.ttf'))).load();
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

/// The controller of the scene on screen.
VolcanoController controllerOf(WidgetTester tester) =>
    tester.widget<VolcanoView>(find.byType(VolcanoView)).controller;

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
    expect(find.text('Place on a surface'), findsOneWidget);
    expect(find.text('On a marker'), findsOneWidget);
    expect(find.text('Just the model'), findsOneWidget);

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
    await advance(tester, 3.6);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Eruption'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Inside'));
    await advance(tester, 4);
    await save(tester, 'screen_explorer_erupting');

    // The view rail steers without gestures.
    for (final tip in ['Zoom in', 'Zoom out', 'Turn to the next side']) {
      expect(find.byTooltip(tip), findsOneWidget);
    }
    await tester.tap(find.byTooltip('View from above'));
    await advance(tester, 1);
    expect(find.byTooltip('View from the side'), findsOneWidget);
    await tester.tap(find.byTooltip('View from the side'));
    await tester.tap(find.byTooltip('Turn to the next side'));
    await advance(tester, 1.5);
    await save(tester, 'screen_explorer_turned');
    await tester.tap(find.byTooltip('Recentre'));
    await advance(tester, 1.5);

    // Selecting a component (a tap on its pin) opens its sheet.
    controllerOf(tester).select(VolcanoPart.chamber);
    await advance(tester, 1);
    expect(find.text('Magma chamber'), findsOneWidget);
    expect(find.text('03 / 05'), findsOneWidget);
    expect(find.text('Listen'), findsOneWidget);
    await save(tester, 'screen_explorer_part');

    await tester.tap(find.byTooltip('Next component'));
    await advance(tester, 1);
    expect(find.text('04 / 05'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await advance(tester, 1);
    expect(find.text('04 / 05'), findsNothing);
    expect(find.byTooltip('Reset'), findsOneWidget);
  });

  testWidgets('the detail card fits a short screen', (tester) async {
    // 360 x 592 logical pixels; an overflow would fail the test.
    await pumpScreen(
      tester,
      ExplorerScreen(geometry: geometry),
      size: const Size(720, 1184),
    );
    await advance(tester, 1);
    controllerOf(tester).select(VolcanoPart.cone);
    await advance(tester, 1);
    expect(find.text('01 / 05'), findsOneWidget);
    await save(tester, 'screen_explorer_short');
  });

  testWidgets('the marker gallery shows both markers', (tester) async {
    await pumpScreen(tester, const MarkerCardScreen());
    await advance(tester, 1);
    expect(find.text('01 / 02'), findsOneWidget);
    expect(find.text('Volcano'), findsOneWidget);
    await save(tester, 'screen_markers');

    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await advance(tester, 1);
    expect(find.text('02 / 02'), findsOneWidget);
  });

  testWidgets('a marker fills the screen and a tap leaves', (tester) async {
    await pumpScreen(tester, const MarkerCardScreen());
    await advance(tester, 1);
    await tester.tap(find.byTooltip('Show this marker full screen'));
    await advance(tester, 1);
    expect(find.byType(MarkerFullScreen), findsOneWidget);
    // Only the code: the square is as wide as the screen allows.
    final code = tester.getSize(
      find.descendant(
        of: find.byType(MarkerFullScreen),
        matching: find.byType(MarkerCode),
      ),
    );
    expect(code.width, code.height);
    expect(code.width, greaterThan(380));
    await save(tester, 'screen_marker_full');

    await tester.tap(find.byType(MarkerFullScreen));
    await advance(tester, 1);
    expect(find.byType(MarkerFullScreen), findsNothing);
    expect(find.text('Markers'), findsOneWidget);
  });

  // Writes the printable markers when asked to:
  //   flutter test test/ui/screens_test.dart --dart-define=PRINT_MARKERS=true
  testWidgets('renders the printable markers', (tester) async {
    for (final marker in VulcanicMarker.values) {
      tester.view
        ..physicalSize = const Size(1500, 1920)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: Colors.white,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(width: 1500, child: MarkerCard(marker: marker)),
              ),
            ),
          ),
        ),
      );
      expect(find.text(marker.title), findsOneWidget);
      if (!const bool.fromEnvironment('PRINT_MARKERS')) continue;
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('docs/markers')..createSync(recursive: true);
        File('${dir.path}/marker-${marker.number}-${marker.slug}.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
      });
    }
  });
}
