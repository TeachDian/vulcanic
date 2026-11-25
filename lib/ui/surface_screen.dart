import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../ar/ar_session.dart';
import '../ar/camera_start.dart';
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

  /// The install prompt for AR services is offered once per visit.
  bool _offeredInstall = false;
  bool _waitingForInstall = false;

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
        (_waitingForInstall || _availability == ArAvailability.installable)) {
      _checkAvailability(initial: false);
    }
  }

  /// Surface tracking is always the first choice. The fallback is used
  /// only when the phone cannot do it, or the user turns it down.
  Future<void> _checkAvailability({required bool initial}) async {
    var availability = initial
        ? await ArSession.warmUp()
        : await ArSession.availability();
    // The early answer may be out of date (AR services installed since) or
    // a check that timed out. Anything short of "supported" is asked again;
    // a settled answer comes back at once.
    if (initial && availability != ArAvailability.supported) {
      availability = await ArSession.availability();
    }
    if (!mounted) return;

    // Capable, but Google's AR services are missing or out of date: offer
    // to install them before settling for less.
    if (availability == ArAvailability.installable && !_offeredInstall) {
      _offeredInstall = true;
      final install = await ArSession.requestInstall();
      if (!mounted) return;
      switch (install) {
        case ArInstall.installed:
          availability = ArAvailability.supported;
        case ArInstall.requested:
          // The store prompt is up. The answer comes when the app resumes.
          setState(() => _availability = null);
          _waitingForInstall = true;
          return;
        case ArInstall.declined:
          break;
      }
    }

    setState(() {
      _waitingForInstall = false;
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
        if (availability == null) return const _CheckingSupport();
        if (_useAr) {
          return _TrackedSurface(
            geometry: widget.geometry,
            onSwitch: () => _fallBack('Tap anywhere to move the volcano'),
            onGiveUp: () => _fallBack(
              'No surface found. Tap anywhere to place the volcano',
            ),
            onFailed: () => _fallBack(
              'Surface tracking could not start. Tap to place instead',
            ),
          );
        }
        return _ScreenSurface(
          geometry: widget.geometry,
          notice: _notice,
          onInstall: availability == ArAvailability.installable
              ? () {
                  _offeredInstall = false;
                  _checkAvailability(initial: false);
                }
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
    required this.onGiveUp,
    required this.onFailed,
  });

  final VolcanoGeometry geometry;

  /// The user chose screen placement from the top bar.
  final VoidCallback onSwitch;

  /// The user gave up waiting for a surface to be found.
  final VoidCallback onGiveUp;
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

  /// How long to look for a surface before offering the fallback.
  static const Duration _searchPatience = Duration(seconds: 20);

  late final SceneRenderer _renderer = SceneRenderer(widget.geometry);
  final VolcanoController _controller = VolcanoController();
  final ArSession _session = ArSession();

  _Tracking _tracking = _Tracking.starting;
  TrackingIssue _issue = TrackingIssue.none;
  bool _placing = true;
  bool _placed = false;
  bool _showSurfaces = true;
  String? _notice;

  /// Set when no surface has been found for a while.
  bool _searchIsSlow = false;
  Timer? _searchTimer;

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
    _searchTimer = Timer(_searchPatience, () {
      if (mounted && !_placed && _tracking != _Tracking.ready) {
        setState(() => _searchIsSlow = true);
      }
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
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
    if (_placed && !_placing && frame.anchorState == AnchorState.none) {
      // ARCore gave up on the anchor for good; ask for a new spot.
      setState(() {
        _placed = false;
        _placing = true;
        _anchor = null;
        _showSurfaces = true;
        _notice = 'The surface was lost. Tap to place again';
      });
      return;
    }
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
        // A surface turned up after all.
        if (tracking == _Tracking.ready) _searchIsSlow = false;
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
      // A fresh placement faces the viewer again.
      _controller
        ..holdStill()
        ..rotation = 0;
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
        lift: widget.geometry.restDepth(_controller.cutawayT),
        rotation: _yaw + _controller.rotation,
        scale: _controller.scale,
      ),
      opacity: _opacity,
      exposure: light == null ? 1 : (0.62 + light * 0.9).clamp(0.65, 1.2),
    );
  }

  (String, Color) get _status => switch (_tracking) {
    _Tracking.starting => ('Starting', Palette.caution),
    _Tracking.limited => ('Scanning', Palette.caution),
    _Tracking.searching => ('Scanning', Palette.caution),
    _Tracking.ready => ('Surface found', Palette.good),
    _Tracking.anchored => ('Anchored', Palette.good),
    _Tracking.lost => ('Lost', Palette.caution),
  };

  Widget? get _banner {
    if (_notice != null) {
      return HintBanner(text: _notice!, icon: Icons.touch_app_rounded);
    }
    final searching =
        _tracking == _Tracking.starting ||
        _tracking == _Tracking.limited ||
        _tracking == _Tracking.searching;
    if (_searchIsSlow && searching) {
      // Still nothing: say why if ARCore knows, and offer the way out.
      return HintBanner(
        text: _issue == TrackingIssue.none
            ? 'Still looking. Try a lit, patterned surface'
            : _issue.advice,
        icon: Icons.warning_amber_rounded,
        color: Palette.caution,
        action: 'Place on screen',
        onAction: widget.onGiveUp,
      );
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
      status: StatusText(label: label, color: color),
      banner: _banner,
      trailing: [
        BarButton(
          icon: _showSurfaces ? Icons.grid_on_rounded : Icons.grid_off_rounded,
          tooltip: 'Show detected surfaces',
          onPressed: () => setState(() => _showSurfaces = !_showSurfaces),
        ),
        BarButton(
          icon: Icons.touch_app_rounded,
          tooltip: 'Use screen placement',
          onPressed: widget.onSwitch,
        ),
      ],
      viewActions: [
        ViewAction(
          icon: Icons.open_with_rounded,
          tooltip: 'Move',
          active: _placing,
          onPressed: () => setState(() {
            _placing = !_placing;
            if (_placing) _showSurfaces = true;
          }),
        ),
      ],
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
    startCamera(_preview, stillWanted: () => mounted);
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
        lift: widget.geometry.restDepth(_controller.cutawayT),
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
      status: const StatusText(label: 'On screen'),
      trailing: [
        if (widget.onSwitch != null)
          BarButton(
            icon: Icons.view_in_ar_rounded,
            tooltip: 'Use surface tracking',
            onPressed: widget.onSwitch,
          ),
      ],
      viewActions: [
        ViewAction(
          icon: Icons.filter_center_focus_rounded,
          tooltip: 'Recentre',
          onPressed: () {
            _anchor = null;
            _controller.resetTransform();
          },
        ),
      ],
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

/// Shown while the phone is asked whether it supports surface tracking.
class _CheckingSupport extends StatelessWidget {
  const _CheckingSupport();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.ink,
      body: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BarButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const Spacer(),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 18,
                children: [
                  const SizedBox.square(
                    dimension: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Palette.bone,
                    ),
                  ),
                  Text('Checking this phone', style: AppText.label),
                ],
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
