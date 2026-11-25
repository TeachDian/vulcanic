import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../ar/camera_start.dart';
import '../ar/gravity.dart';
import '../ar/marker_pose.dart';
import '../content/markers.dart';
import '../engine/scene_frame.dart';
import '../engine/scene_renderer.dart';
import '../engine/volcano_controller.dart';
import '../engine/volcano_geometry.dart';
import '../engine/volcano_view.dart';
import 'camera_gate.dart';
import 'marker_card_screen.dart';
import 'scene/controls.dart';
import 'scene/hint_banner.dart';
import 'scene/scene_chrome.dart';
import 'scene/scene_gestures.dart';
import 'theme.dart';

/// Marker-based mode: the volcano stands on a printed marker and follows it.
class MarkerScreen extends StatelessWidget {
  const MarkerScreen({super.key, required this.geometry});
  final VolcanoGeometry geometry;

  @override
  Widget build(BuildContext context) =>
      CameraGate(builder: (context) => _MarkerScene(geometry: geometry));
}

enum _Lock { searching, locked, lost }

class _MarkerScene extends StatefulWidget {
  const _MarkerScene({required this.geometry});
  final VolcanoGeometry geometry;

  @override
  State<_MarkerScene> createState() => _MarkerSceneState();
}

class _MarkerSceneState extends State<_MarkerScene> {
  /// Width of the volcano's base, in marker code widths.
  static const double _width = 1.6;

  late final SceneRenderer _renderer = SceneRenderer(widget.geometry);
  final VolcanoController _controller = VolcanoController();
  final MarkerTracker _tracker = MarkerTracker();
  final MarkerStabilizer _stabilizer = MarkerStabilizer();
  final GravitySensor _gravity = GravitySensor();
  double _lastFrameClock = 0;
  final MobileScannerController _scanner = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.unrestricted,
  );

  _Lock _lock = _Lock.searching;
  VulcanicMarker? _marker;
  bool _foreignCode = false;
  double _foreignSeenAt = 0;
  Size _imageSize = Size.zero;
  Size _viewSize = Size.zero;
  double _opacity = 0;
  double _lastClock = 0;

  @override
  void initState() {
    super.initState();
    _controller.frame.addListener(_onTick);
    _gravity.start();
    startCamera(_scanner, stillWanted: () => mounted);
  }

  @override
  void dispose() {
    _controller.frame.removeListener(_onTick);
    _gravity.stop();
    _scanner.dispose();
    _renderer.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Marker detection: identify the code, then hand its corners on.
  void _onDetect(BarcodeCapture capture) {
    if (_viewSize.isEmpty || capture.size.isEmpty) return;
    Barcode? found;
    VulcanicMarker? marker;
    for (final barcode in capture.barcodes) {
      final candidate = VulcanicMarker.identify(barcode.rawValue);
      if (candidate != null && barcode.corners.length == 4) {
        found = barcode;
        marker = candidate;
        break;
      }
    }
    if (found == null || marker == null) {
      // A code, but not one of ours.
      if (_tracker.lost && capture.barcodes.isNotEmpty) {
        _foreignSeenAt = _controller.clock;
        if (!_foreignCode) setState(() => _foreignCode = true);
      }
      return;
    }

    // The analysis image is reported upright; guard against a sideways one.
    var image = capture.size;
    if ((image.width > image.height) != (_viewSize.width > _viewSize.height)) {
      image = image.flipped;
    }
    _imageSize = image;
    _tracker.report(MarkerPose.toView(found.corners, image, _viewSize));

    if (marker != _marker) {
      HapticFeedback.mediumImpact();
      // Each marker brings up its own content, and it rises into place.
      _controller.arrive();
      _controller.cutaway = marker == VulcanicMarker.crossSection;
      setState(() {
        _marker = marker;
        _foreignCode = false;
      });
    }
  }

  /// Runs once per animation frame.
  void _onTick() {
    final dt = (_controller.clock - _lastClock).clamp(0.0, 0.1);
    _lastClock = _controller.clock;
    _tracker.advance(dt);
    final lock = _tracker.corners == null
        ? _Lock.searching
        : (_tracker.lost ? _Lock.lost : _Lock.locked);
    // Fade out when the marker is covered or leaves the view.
    final target = lock == _Lock.locked ? 1.0 : 0.0;
    _opacity += (target - _opacity) * (1 - 1 / (1 + dt * 14));
    // The warning about an unknown code clears once the code is gone.
    final foreign = _foreignCode && _controller.clock - _foreignSeenAt < 1.5;
    // A marker that comes back is taken where it is, not eased to from
    // where it was last seen.
    if (lock == _Lock.locked && _lock != _Lock.locked) _stabilizer.reset();
    if (lock != _lock || foreign != _foreignCode) {
      setState(() {
        _lock = lock;
        _foreignCode = foreign;
      });
    }
  }

  SceneFrame? _frame(Size size) {
    final corners = _tracker.corners;
    if (corners == null || _imageSize.isEmpty || _opacity < 0.01) return null;
    final focal = MarkerPose.focalLength(_imageSize, size);
    final raw = MarkerPose.estimate(corners, size, focal);
    if (raw == null) return null;
    // Level it and take the shake out before standing the model on it.
    final dt = _controller.clock - _lastFrameClock;
    _lastFrameClock = _controller.clock;
    final anchor = _stabilizer.update(raw, up: _gravity.up, dt: dt);
    return SceneFrame(
      view: Matrix4.identity(),
      projection: MarkerPose.projection(size, focal),
      model: placeVolcano(
        anchor: anchor,
        width: _width,
        lift: widget.geometry.restDepth(_controller.cutawayT),
        rotation: _controller.rotation,
        scale: _controller.scale * _controller.arrivalScale,
      ),
      opacity: _opacity,
    );
  }

  void _showMarker() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MarkerCardScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final marker = _marker;
    final (label, color) = switch (_lock) {
      _Lock.searching => ('Searching', Palette.caution),
      _Lock.locked => (marker?.title ?? 'Marker', Palette.good),
      _Lock.lost => ('Lost', Palette.caution),
    };
    return SceneChrome(
      controller: _controller,
      showControls: marker != null,
      status: StatusText(label: label, color: color),
      trailing: [
        BarButton(
          icon: Icons.qr_code_2_rounded,
          tooltip: 'Show the marker',
          onPressed: _showMarker,
        ),
      ],
      viewActions: [
        ViewAction(
          icon: Icons.filter_center_focus_rounded,
          tooltip: 'Straighten',
          onPressed: _controller.resetTransform,
        ),
      ],
      banner: switch (_lock) {
        _Lock.locked => null,
        _Lock.lost => const HintBanner(
          text: 'Bring the marker back into view',
          icon: Icons.warning_amber_rounded,
          color: Palette.caution,
        ),
        _Lock.searching => HintBanner(
          text: _foreignCode
              ? 'That code is not a Vulcanic marker'
              : 'Point the camera at the printed marker',
          icon: _foreignCode
              ? Icons.warning_amber_rounded
              : Icons.center_focus_weak_rounded,
          color: _foreignCode ? Palette.caution : Palette.bone,
          action: 'Marker',
          onAction: _showMarker,
        ),
      },
      scene: LayoutBuilder(
        builder: (context, constraints) {
          _viewSize = constraints.biggest;
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              MobileScanner(
                controller: _scanner,
                fit: BoxFit.cover,
                onDetect: _onDetect,
                placeholderBuilder: (context) =>
                    const ColoredBox(color: Colors.black),
              ),
              IgnorePointer(
                child: CustomPaint(
                  painter: _MarkerOutline(_tracker, _controller),
                ),
              ),
              SceneGestures(
                renderer: _renderer,
                controller: _controller,
                onDrag: (drag) => applyDragToModel(_controller, drag),
                child: VolcanoView(
                  renderer: _renderer,
                  controller: _controller,
                  frameFor: _frame,
                  labelStyle: AppText.label,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Outlines the recognised marker, so it is clear what is being tracked.
class _MarkerOutline extends CustomPainter {
  _MarkerOutline(this.tracker, this.controller)
    : super(repaint: controller.frame);

  final MarkerTracker tracker;
  final VolcanoController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final corners = tracker.corners;
    if (corners == null || tracker.lost) return;
    final path = Path()..addPolygon(corners, true);
    canvas.drawPath(
      path,
      Paint()..color = Palette.bone.withValues(alpha: 0.10),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..color = Palette.bone,
    );
    // The first corner is the code's top-left: it shows orientation.
    canvas.drawCircle(corners.first, 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_MarkerOutline old) => old.tracker != tracker;
}
