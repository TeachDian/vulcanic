import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ar/ar_session.dart';
import '../engine/scene_frame.dart';
import '../engine/scene_renderer.dart';
import '../engine/volcano_controller.dart';
import '../engine/volcano_geometry.dart';
import '../engine/volcano_view.dart';
import 'explorer_screen.dart';
import 'guide_screen.dart';
import 'marker_card_screen.dart';
import 'marker_screen.dart';
import 'scene/controls.dart';
import 'surface_screen.dart';
import 'theme.dart';

/// The main interface: the volcano, one main action, and two other ways in.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.geometry});
  final VolcanoGeometry geometry;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SceneRenderer _renderer = SceneRenderer(widget.geometry);
  final VolcanoController _hero = VolcanoController()
    ..labels = false
    ..labelsT = 0;
  final OrbitCamera _camera = OrbitCamera(elevation: 17 * math.pi / 180);

  /// Asked now, so Surface can go straight to tracking, and so the button
  /// can show whether this phone has AR.
  late final Future<ArAvailability> _support = ArSession.warmUp();

  @override
  void dispose() {
    _renderer.dispose();
    _hero.dispose();
    super.dispose();
  }

  SceneFrame _frame(Size size) {
    // A slow turntable.
    _camera
      ..azimuth = 1.25 + _hero.clock * 0.10
      ..target.y = 0.02
      ..distance = _camera.distanceToFit(size, radius: 1.12);
    return _camera.frame(size);
  }

  void _open(Widget screen) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.5),
                radius: 0.95,
                colors: [Color(0xFF1C2630), Palette.ink],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: height * 0.60,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: VolcanoView(
                  renderer: _renderer,
                  controller: _hero,
                  frameFor: _frame,
                ),
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(22, 8, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('VULCANIC', style: AppText.wordmark),
                    const Spacer(),
                    BarButton(
                      icon: Icons.qr_code_2_rounded,
                      tooltip: 'Markers',
                      onPressed: () => _open(const MarkerCardScreen()),
                    ),
                    Transform.translate(
                      offset: const Offset(10, 0),
                      child: BarButton(
                        icon: Icons.help_outline_rounded,
                        tooltip: 'How it works',
                        onPressed: () => _open(const GuideScreen()),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text('A volcano\non your desk', style: AppText.display),
                const SizedBox(height: 22),
                _PrimaryAction(
                  label: 'Place on a surface',
                  support: _support,
                  onTap: () => _open(SurfaceScreen(geometry: widget.geometry)),
                ),
                const SizedBox(height: 6),
                _Row(
                  label: 'On a marker',
                  onTap: () => _open(MarkerScreen(geometry: widget.geometry)),
                ),
                Container(height: 1, color: Palette.line()),
                _Row(
                  label: 'Just the model',
                  onTap: () => _open(ExplorerScreen(geometry: widget.geometry)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one filled button. A green dot at its end means this phone can
/// track surfaces.
class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.support,
    required this.onTap,
  });

  final String label;
  final Future<ArAvailability> support;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.bone,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppText.title.copyWith(color: Palette.onBone),
                  ),
                ),
                FutureBuilder<ArAvailability>(
                  future: support,
                  builder: (context, snapshot) => AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: snapshot.data == ArAvailability.supported ? 1 : 0,
                    child: Semantics(
                      label: 'Surface tracking available',
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2C8F5C),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet way in: a name and a chevron.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppText.title)),
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: Palette.ash,
            ),
          ],
        ),
      ),
    );
  }
}
