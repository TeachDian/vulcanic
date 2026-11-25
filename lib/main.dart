import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/scene_frame.dart';
import 'engine/scene_renderer.dart';
import 'engine/volcano_controller.dart';
import 'engine/volcano_geometry.dart';
import 'engine/volcano_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const VulcanicApp());
}

class VulcanicApp extends StatelessWidget {
  const VulcanicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vulcanic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const EnginePreview(),
    );
  }
}

/// Bare preview of the 3D engine: drag to orbit, pinch to zoom.
class EnginePreview extends StatefulWidget {
  const EnginePreview({super.key});

  @override
  State<EnginePreview> createState() => _EnginePreviewState();
}

class _EnginePreviewState extends State<EnginePreview> {
  final VolcanoController _controller = VolcanoController();
  final OrbitCamera _camera = OrbitCamera();
  SceneRenderer? _renderer;
  double _startDistance = 0;

  @override
  void initState() {
    super.initState();
    VolcanoGeometry.load().then((geometry) {
      if (mounted) setState(() => _renderer = SceneRenderer(geometry));
    });
  }

  @override
  void dispose() {
    _renderer?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    return Scaffold(
      backgroundColor: const Color(0xFF14161A),
      body: renderer == null
          ? const SizedBox.shrink()
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) =>
                  _controller.select(renderer.partAt(d.localPosition)),
              onScaleStart: (_) => _startDistance = _camera.distance,
              onScaleUpdate: (d) {
                _camera
                  ..orbit(
                    -d.focalPointDelta.dx * 0.008,
                    d.focalPointDelta.dy * 0.006,
                  )
                  ..distance = (_startDistance / d.scale).clamp(2.6, 9.0);
              },
              child: VolcanoView(
                renderer: renderer,
                controller: _controller,
                frameFor: _camera.frame,
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            FilledButton.tonal(
              onPressed: () => _controller.cutaway = !_controller.cutaway,
              child: Text(_controller.cutaway ? 'Close' : 'See inside'),
            ),
            FilledButton(
              onPressed: _controller.toggleEruption,
              child: Text(_controller.eruption.running ? 'Pause' : 'Erupt'),
            ),
            FilledButton.tonal(
              onPressed: _controller.reset,
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}
