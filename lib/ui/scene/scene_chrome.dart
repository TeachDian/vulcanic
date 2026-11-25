import 'package:flutter/material.dart';

import '../../engine/volcano_controller.dart';
import '../theme.dart';
import 'controls.dart';
import 'part_sheet.dart';

/// The controls every viewing mode shares, laid over a full-screen scene:
/// a top bar, the component rail, the eruption strip and dock, and the
/// detail card for the selected component.
class SceneChrome extends StatelessWidget {
  const SceneChrome({
    super.key,
    required this.controller,
    required this.scene,
    this.status,
    this.trailing = const [],
    this.modeAction,
    this.banner,
    this.sheetLeading,
    this.showControls = true,
  });

  final VolcanoController controller;

  /// The scene itself: camera or backdrop, the volcano, gesture handling.
  final Widget scene;

  /// Shown in the middle of the top bar (mode name, tracking state).
  final Widget? status;

  /// Extra buttons at the end of the top bar.
  final List<Widget> trailing;

  /// The mode-specific slot in the dock.
  final DockAction? modeAction;

  /// Guidance shown above the dock (e.g. "Move the phone slowly").
  final Widget? banner;

  /// Passed through to [PartSheet.leading].
  final Widget? sheetLeading;

  /// False hides the rail and the dock, e.g. before the model is placed.
  final bool showControls;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.ink,
      body: Stack(
        fit: StackFit.expand,
        children: [
          scene,
          // Keeps the top bar legible over a bright camera image.
          const IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 150,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x99000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // And the controls legible at the bottom.
          const IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 340,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xB3000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final selected = controller.selected;
                return Column(
                  children: [
                    Row(
                      spacing: 10,
                      children: [
                        GlassIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back',
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: status,
                          ),
                        ),
                        ...trailing,
                      ],
                    ),
                    // The dock or the detail card, pinned to the bottom. The
                    // card shrinks and scrolls on short screens.
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ?banner,
                          Flexible(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween(
                                        begin: const Offset(0, 0.12),
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
                                      leading: sheetLeading,
                                    )
                                  : Column(
                                      key: const ValueKey('dock'),
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        PartRail(controller: controller),
                                        const SizedBox(height: 14),
                                        PhaseStrip(controller: controller),
                                        ControlDock(
                                          controller: controller,
                                          modeAction: modeAction,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A small pill for the top bar: an optional status dot and a short label.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.color, this.icon});

  final String label;

  /// Colour of the leading dot; omitted when null.
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 9,
          children: [
            if (icon != null)
              Icon(icon, size: 17, color: color ?? Palette.bone),
            if (icon == null && color != null)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color!.withValues(alpha: 0.7),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
