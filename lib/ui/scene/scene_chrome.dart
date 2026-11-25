import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/volcano_controller.dart';
import '../../media/gallery.dart';
import '../theme.dart';
import 'controls.dart';
import 'hint_banner.dart';
import 'listen_button.dart';
import 'part_sheet.dart';

/// What every viewing mode shares, laid over a full-screen scene: a bare
/// top bar, the view rail, and at the bottom either the console or the
/// sheet for the selected component.
class SceneChrome extends StatefulWidget {
  const SceneChrome({
    super.key,
    required this.controller,
    required this.scene,
    this.status,
    this.trailing = const [],
    this.banner,
    this.viewActions = const [],
    this.showControls = true,
  });

  final VolcanoController controller;

  /// The scene itself: camera or backdrop, the volcano, gesture handling.
  final Widget scene;

  /// Shown beside the back button (tracking state).
  final Widget? status;

  /// Extra buttons at the end of the top bar.
  final List<Widget> trailing;

  /// Guidance shown above the console (e.g. "Move the phone slowly").
  final Widget? banner;

  /// Mode-specific buttons added to the view rail.
  final List<ViewAction> viewActions;

  /// False hides the rail and the console, e.g. before the model is placed.
  final bool showControls;

  @override
  State<SceneChrome> createState() => _SceneChromeState();
}

class _SceneChromeState extends State<SceneChrome> {
  /// True for the instant a picture is taken, so the controls are not in it.
  bool _capturing = false;
  String? _toast;
  int _toastSerial = 0;

  VolcanoController get controller => widget.controller;

  /// Saves what the scene shows, without the controls, to the gallery.
  Future<void> _capture() async {
    if (_capturing) return;
    HapticFeedback.mediumImpact();
    setState(() => _capturing = true);
    // Let the frame without controls reach the screen before copying it.
    // The surface lags the framework by a couple of frames, more on slow
    // devices, so wait generously; nobody minds a shutter this quick.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 320));
    final name = await Gallery.captureScreen();
    if (!mounted) return;
    setState(() => _capturing = false);
    _showToast(name == null ? 'Could not save the picture' : 'Saved');
  }

  Future<void> _showToast(String text) async {
    final serial = ++_toastSerial;
    setState(() => _toast = text);
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (mounted && serial == _toastSerial) setState(() => _toast = null);
  }

  @override
  Widget build(BuildContext context) {
    final showControls = widget.showControls;
    final shortScreen = MediaQuery.sizeOf(context).height < 720;
    final inset = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Palette.ink,
      body: Stack(
        fit: StackFit.expand,
        children: [
          widget.scene,
          Opacity(
            opacity: _capturing ? 0 : 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Scrims keep bare icons and text legible over a bright
                // camera image.
                const IgnorePointer(child: _Scrim(top: true, height: 130)),
                const IgnorePointer(child: _Scrim(top: false, height: 300)),

                // Top bar.
                Positioned(
                  top: inset.top + 6,
                  left: 6,
                  right: 6,
                  child: Row(
                    children: [
                      BarButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: widget.status,
                        ),
                      ),
                      ...widget.trailing,
                      BarButton(
                        icon: Icons.photo_camera_outlined,
                        tooltip: 'Save a picture',
                        onPressed: _capture,
                      ),
                    ],
                  ),
                ),

                // View rail, under the top bar where pins rarely reach.
                Positioned(
                  top: inset.top + 62,
                  right: 12,
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      // On a short screen the sheet reaches up to the
                      // rail, so the rail steps aside for it.
                      final showRail =
                          showControls &&
                          !(shortScreen && controller.selected != null);
                      return AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: showRail ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !showRail,
                          child: ViewRail(
                            controller: controller,
                            extra: widget.viewActions,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Bottom: guidance, then the console or the sheet.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  top: inset.top + 60,
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      final selected = controller.selected;
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (widget.banner != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: widget.banner,
                            ),
                          Flexible(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween(
                                        begin: const Offset(0, 0.14),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              layoutBuilder: (current, previous) => Stack(
                                alignment: Alignment.bottomCenter,
                                children: [...previous, ?current],
                              ),
                              child: !showControls
                                  ? const SizedBox(key: ValueKey('none'))
                                  : selected != null
                                  ? PartSheet(
                                      key: const ValueKey('sheet'),
                                      part: selected,
                                      controller: controller,
                                      bottomInset: inset.bottom,
                                      leading: ListenButton(part: selected),
                                    )
                                  : Padding(
                                      key: const ValueKey('console'),
                                      padding: EdgeInsets.fromLTRB(
                                        14,
                                        0,
                                        14,
                                        inset.bottom + 14,
                                      ),
                                      child: Console(controller: controller),
                                    ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_toast != null)
            Positioned(
              top: inset.top + 64,
              left: 0,
              right: 0,
              child: Center(
                child: HintBanner(
                  text: _toast!,
                  icon: Icons.check_rounded,
                  color: Palette.good,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.top, required this.height});
  final bool top;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: const [Color(0x99000000), Color(0x00000000)],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tracking state for the top bar: a dot and a word, nothing more.
class StatusText extends StatelessWidget {
  const StatusText({super.key, required this.label, this.color});

  final String label;

  /// Colour of the leading dot; omitted when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        if (color != null)
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label.copyWith(shadows: AppText.overCamera),
          ),
        ),
      ],
    );
  }
}
