import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../ar/ar_session.dart';
import '../ar/placement.dart';
import '../ar/tracking_painter.dart';
import '../engine/scene_frame.dart';
import '../engine/scene_renderer.dart';
import '../engine/volcano_controller.dart';
import '../engine/volcano_geometry.dart';
import '../engine/volcano_view.dart';
import 'camera_gate.dart';
import 'scene/controls.dart';
import 'scene/hint_banner.dart';
import 'scene/scene_chrome.dart';
import 'scene/scene_gestures.dart';
import 'theme.dart';

/// Markerless mode: the volcano stands on a real surface.
///
/// On phones with ARCore the surface is detected and the model is anchored
/// to it. On phones without, the model is placed by tapping the screen.
class SurfaceScreen extends StatefulWidget {
  const SurfaceScreen({super.key, required this.geometry});
  final VolcanoGeometry geometry;

  @override
  State<SurfaceScreen> createState() => _SurfaceScreenState();
}

class _SurfaceScreenState extends State<SurfaceScreen>
    with WidgetsBindingObserver {
  ArAvailability? _availability;
  bool _useAr = false;

  /// Explains why the app is not using surface tracking, when it is not.
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAvailability(initial: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the store after installing AR services.
    if (state == AppLifecycleState.resumed &&
        _availability == ArAvailability.installable) {
      _checkAvailability(initial: false);
    }
  }

  Future<void> _checkAvailability({required bool initial}) async {
    final availability = await ArSession.availability();
    if (!mounted) return;
    setState(() {
      _availability = availability;
      if (initial || availability == ArAvailability.supported) {
        _useAr = availability == ArAvailability.supported;
      }
      _notice = switch (availability) {
        ArAvailability.supported => null,
        ArAvailability.installable =>
          'Surface tracking needs Google Play Services for AR',
        ArAvailability.unsupported =>
          'No surface tracking on this phone. Tap to place instead',
      };
    });
  }

  void _fallBack(String reason) {
    if (!mounted) return;
    setState(() {
      _useAr = false;
      _notice = reason;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CameraGate(
      builder: (context) {
        final availability = _availability;
        if (availability == null) {
          return const Scaffold(backgroundColor: Colors.black);
        }
        if (_useAr) {
          return _TrackedSurface(
            geometry: widget.geometry,
            onSwitch: () => _fallBack('Tap anywhere to move the volcano'),
            onFailed: () => _fallBack(
              'Surface tracking could not start. Tap to place instead',
            ),
          );
        }
        return _ScreenSurface(
          geometry: widget.geometry,
          notice: _notice,
          onInstall: availability == ArAvailability.installable
              ? ArSession.requestInstall
              : null,
          onSwitch: availability == ArAvailability.supported
              ? () => setState(() => _useAr = true)
              : null,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// ARCore: plane detection, hit testing and anchoring
// ---------------------------------------------------------------------------

enum _Tracking { starting, limited, searching, ready, anchored, lost }

class _TrackedSurface extends StatefulWidget {
  const _TrackedSurface({
    required this.geometry,
    required this.onSwitch,
    required this.onFailed,
  });

  final VolcanoGeometry geometry;
  final VoidCallback onSwitch;
  final VoidCallback onFailed;

  @override
  State<_TrackedSurface> createState() => _TrackedSurfaceState();
}

class _TrackedSurfaceState extends State<_TrackedSurface> {
  /// Diameter of the volcano's base on the surface, in metres.
  static const double _width = 0.34;

  /// Where the reticle looks, as a fraction of the view height. Must match
  /// `ArSessionRunner.RETICLE_Y`.
  static const double _reticleFraction = 0.46;

  late final SceneRenderer _renderer = SceneRenderer(widget.geometry);
  final VolcanoController _controller = VolcanoController();
  final ArSession _session = ArSession();

  _Tracking _tracking = _Tracking.starting;
  TrackingIssue _issue = TrackingIssue.none;
  bool _placing = true;
  bool _placed = false;
  bool _showSurfaces = true;
  String? _notice;

  Size? _textureSize;
  double _textureScale = 1;
  bool _starting = false;

  Matrix4? _anchor;
  double _yaw = 0;
  bool _yawPending = false;
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    _session.frame.addListener(_onFrame);
    _session.failure.addListener(_onFailure);
  }

  @override
  void dispose() {
    _session.frame.removeListener(_onFrame);
    _session.failure.removeListener(_onFailure);
    _session.dispose();
    _renderer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFailure() {
    if (_session.failure.value != null) widget.onFailed();
  }

  Future<void> _start(Size size, double pixelRatio) async {
    if (_starting || _textureSize == size) return;
    _starting = true;
    // Full resolution, capped so the long side stays within 1080p video.
    final scale =
        pixelRatio *
        math.min(1.0, 1920 / (math.max(size.width, size.height) * pixelRatio));
    final w = (size.width * scale).round(), h = (size.height * scale).round();
    try {
      if (_session.textureId == null) {
        await _session.start(w, h);
      } else {
        await _session.resize(w, h);
      }
      if (!mounted) return;
      setState(() {
        _textureSize = size;
        _textureScale = scale;
      });
    } on PlatformException catch (_) {
      widget.onFailed();
    } finally {
      _starting = false;
    }
  }

  /// Runs once per camera frame. Rebuilds only when the summary changes.
  void _onFrame() {
    final frame = _session.frame.value;
    if (frame == null) return;
    if (frame.anchor != null) {
      _anchor = frame.anchor;
      if (_yawPending) {
        _yaw = facingYaw(frame.anchor!, frame.view);
        _yawPending = false;
      }
    }
    final _Tracking tracking;
    if (!frame.tracking) {
      tracking = _placed ? _Tracking.lost : _Tracking.limited;
    } else if (_placed && !_placing) {
      tracking = frame.anchorState == AnchorState.tracking
          ? _Tracking.anchored
          : _Tracking.lost;
    } else if (frame.planes.isEmpty) {
      tracking = _Tracking.searching;
    } else {
      tracking = _Tracking.ready;
    }
    if (tracking != _tracking || frame.issue != _issue) {
      setState(() {
        _tracking = tracking;
        _issue = frame.issue;
      });
    }
  }

  Future<void> _place(Offset position) async {
    final placed = await _session.placeAt(
      position.dx * _textureScale,
      position.dy * _textureScale,
    );
    if (!mounted) return;
    if (placed) {
      HapticFeedback.mediumImpact();
      setState(() {
        _placing = false;
        _yawPending = true;
        _notice = null;
        // Detected surfaces have done their job once the model stands.
        if (!_placed) _showSurfaces = false;
        _placed = true;
      });
      _controller.rotation = 0;
    } else {
      setState(() => _notice = 'No surface found there yet. Try the grid');
    }
  }

  SceneFrame? _frame(Size size) {
    final frame = _session.frame.value;
    final anchor = _anchor;
    if (frame == null || anchor == null || !_placed) return null;
    // Fade rather than pop when tracking comes and goes.
    final target = frame.anchorState == AnchorState.tracking ? 1.0 : 0.45;
    _opacity += (target - _opacity) * 0.18;
    final light = frame.light;
    return SceneFrame(
      view: frame.view,
      projection: frame.projection,
      model: placeVolcano(
        anchor: anchor,
        width: _width,
        blockDepth: widget.geometry.blockDepth,
        rotation: _yaw + _controller.rotation,
        scale: _controller.scale,
      ),
      opacity: _opacity,
      exposure: light == null ? 1 : (0.62 + light * 0.9).clamp(0.65, 1.2),
    );
  }

  (String, Color) get _status => switch (_tracking) {
    _Tracking.starting => ('Starting camera', Palette.caution),
    _Tracking.limited => ('Finding the room', Palette.caution),
    _Tracking.searching => ('Looking for a surface', Palette.caution),
    _Tracking.ready => ('Surface found', Palette.good),
    _Tracking.anchored => ('Anchored', Palette.good),
    _Tracking.lost => ('Tracking lost', Palette.caution),
  };

  Widget? get _banner {
    if (_notice != null) {
      return HintBanner(text: _notice!, icon: Icons.touch_app_rounded);
    }
    if (_issue != TrackingIssue.none && _tracking != _Tracking.anchored) {
      return HintBanner(
        text: _issue.advice,
        icon: Icons.warning_amber_rounded,
        color: Palette.caution,
      );
    }
    return switch (_tracking) {
      _Tracking.starting ||
      _Tracking.limited ||
      _Tracking.searching => const HintBanner(
        text: 'Move the phone slowly over a table or floor',
        icon: Icons.screen_rotation_alt_rounded,
      ),
      _Tracking.ready => const HintBanner(
        text: 'Tap where the volcano should stand',
        icon: Icons.touch_app_rounded,
      ),
      _Tracking.lost => const HintBanner(
        text: 'Point the camera back at the surface',
        icon: Icons.warning_amber_rounded,
        color: Palette.caution,
      ),
      _Tracking.anchored => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = _status;
    final textureId = _session.textureId;
    return SceneChrome(
      controller: _controller,
      showControls: _placed,
      status: StatusPill(label: label, color: color),
      banner: _banner,
      trailing: [
        GlassIconButton(
          icon: _showSurfaces ? Icons.grid_on_rounded : Icons.grid_off_rounded,
          tooltip: 'Show detected surfaces',
          onPressed: () => setState(() => _showSurfaces = !_showSurfaces),
        ),
        GlassIconButton(
          icon: Icons.touch_app_rounded,
          tooltip: 'Use screen placement',
          onPressed: widget.onSwitch,
        ),
      ],
      modeAction: DockAction(
        icon: Icons.open_with_rounded,
        label: 'Move',
        active: _placing,
        onPressed: () => setState(() {
          _placing = !_placing;
          if (_placing) _showSurfaces = true;
        }),
      ),
      scene: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final pixelRatio = MediaQuery.devicePixelRatioOf(context);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _start(size, pixelRatio);
          });
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (textureId != null) Texture(textureId: textureId),
              IgnorePointer(
                child: CustomPaint(
                  painter: TrackingPainter(
                    frame: _session.frame,
                    showSurfaces: _showSurfaces || _placing,
                    showReticle: _placing,
                    reticleFraction: _reticleFraction,
                  ),
                ),
              ),
              SceneGestures(
                renderer: _renderer,
                controller: _controller,
                onDrag: (drag) => applyDragToModel(_controller, drag),
                onTapEmpty: (position) {
                  if (_placing) {
                    _place(position);
                  } else {
                    _controller.select(null);
                  }
                },
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

// ---------------------------------------------------------------------------
// Fallback: tap the screen to place
// ---------------------------------------------------------------------------

class _ScreenSurface extends StatefulWidget {
  const _ScreenSurface({
    required this.geometry,
    this.notice,
    this.onInstall,
    this.onSwitch,
  });

  final VolcanoGeometry geometry;
  final String? notice;

  /// Offers to install AR services, when that would enable tracking.
  final VoidCallback? onInstall;

  /// Switches to surface tracking, when the phone supports it.
  final VoidCallback? onSwitch;

  @override
  State<_ScreenSurface> createState() => _ScreenSurfaceState();
}

class _ScreenSurfaceState extends State<_ScreenSurface> {
  static const double _width = 0.22;
  static const ScreenPlacementCamera _camera = ScreenPlacementCamera();

  late final SceneRenderer _renderer = SceneRenderer(widget.geometry);
  final VolcanoController _controller = VolcanoController();
  final MobileScannerController _preview = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
    detectionTimeoutMs: 1000,
  );

  @override
  void initState() {
    super.initState();
    _startPreview();
  }

  /// Opens the camera, allowing a moment for an AR session that was just
  /// closed to let go of it.
  Future<void> _startPreview() async {
    for (final wait in const [350, 900, 1800]) {
      await Future<void>.delayed(Duration(milliseconds: wait));
      if (!mounted) return;
      try {
        await _preview.start();
        return;
      } on MobileScannerException catch (_) {
        // Still busy; try again.
      }
    }
  }

  /// Where the volcano stands on the assumed surface; null until laid out.
  Matrix4? _anchor;
  bool _moved = false;

  @override
  void dispose() {
    _preview.dispose();
    _renderer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _place(Offset position, Size size) {
    HapticFeedback.selectionClick();
    final point = _camera.groundPoint(position, size);
    _anchor = Matrix4.translation(point);
    if (!_moved) setState(() => _moved = true);
  }

  SceneFrame _frame(Size size) {
    final anchor = _anchor ??= Matrix4.translation(
      _camera.groundPoint(size.center(Offset.zero), size),
    );
    final view = _camera.view;
    return SceneFrame(
      view: view,
      projection: _camera.projection(size),
      model: placeVolcano(
        anchor: anchor,
        width: _width,
        blockDepth: widget.geometry.blockDepth,
        rotation: facingYaw(anchor, view) + _controller.rotation,
        scale: _controller.scale,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    return SceneChrome(
      controller: _controller,
      status: const StatusPill(
        label: 'Screen placement',
        icon: Icons.touch_app_rounded,
      ),
      trailing: [
        if (widget.onSwitch != null)
          GlassIconButton(
            icon: Icons.view_in_ar_rounded,
            tooltip: 'Use surface tracking',
            onPressed: widget.onSwitch,
          ),
      ],
      modeAction: DockAction(
        icon: Icons.filter_center_focus_rounded,
        label: 'Recentre',
        onPressed: () {
          _anchor = null;
          _controller.resetTransform();
        },
      ),
      banner: _moved && widget.onInstall == null
          ? null
          : HintBanner(
              text: _moved || notice == null
                  ? 'Tap anywhere to move the volcano'
                  : notice,
              icon: Icons.touch_app_rounded,
              action: widget.onInstall == null ? null : 'Install',
              onAction: widget.onInstall,
            ),
      scene: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              MobileScanner(
                controller: _preview,
                fit: BoxFit.cover,
                errorBuilder: (context, error) => const _CameraError(),
                placeholderBuilder: (context) =>
                    const ColoredBox(color: Colors.black),
              ),
              SceneGestures(
                renderer: _renderer,
                controller: _controller,
                onDrag: (drag) => applyDragToModel(_controller, drag),
                onTapEmpty: (position) => _place(position, size),
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

class _CameraError extends StatelessWidget {
  const _CameraError();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Palette.ink,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            const Icon(
              Icons.videocam_off_rounded,
              color: Palette.smoke,
              size: 40,
            ),
            Text('The camera is not available', style: AppText.caption),
          ],
        ),
      ),
    );
  }
}
