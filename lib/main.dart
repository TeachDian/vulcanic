import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/volcano_geometry.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const VulcanicApp());
}

class VulcanicApp extends StatefulWidget {
  const VulcanicApp({super.key});

  @override
  State<VulcanicApp> createState() => _VulcanicAppState();
}

class _VulcanicAppState extends State<VulcanicApp> {
  /// The model is parsed once and shared by every screen.
  late final Future<VolcanoGeometry> _geometry = VolcanoGeometry.load();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vulcanic',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: FutureBuilder<VolcanoGeometry>(
        future: _geometry,
        builder: (context, snapshot) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: snapshot.hasData
              ? HomeScreen(geometry: snapshot.data!)
              : const ColoredBox(
                  key: ValueKey('loading'),
                  color: Palette.ink,
                  child: SizedBox.expand(),
                ),
        ),
      ),
    );
  }
}
