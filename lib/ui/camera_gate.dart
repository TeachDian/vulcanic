import 'package:flutter/material.dart';

import '../ar/ar_session.dart';
import 'scene/controls.dart';
import 'theme.dart';

/// Shows [builder]'s content once the camera may be used, and a request for
/// permission until then.
class CameraGate extends StatefulWidget {
  const CameraGate({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  State<CameraGate> createState() => _CameraGateState();
}

class _CameraGateState extends State<CameraGate> with WidgetsBindingObserver {
  CameraAccess? _access;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check(request: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the settings page. A passive check cannot tell
    // "denied" from "blocked", so it is only allowed to report good news.
    if (state == AppLifecycleState.resumed &&
        _access != null &&
        _access != CameraAccess.granted) {
      _check(request: false, onlyIfGranted: true);
    }
  }

  Future<void> _check({
    required bool request,
    bool onlyIfGranted = false,
  }) async {
    final access = await CameraPermission.check(request: request);
    if (!mounted) return;
    if (onlyIfGranted && access != CameraAccess.granted) return;
    setState(() => _access = access);
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (access == CameraAccess.granted) return widget.builder(context);
    return Scaffold(
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
            if (access != null) ...[
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.photo_camera_outlined,
                      color: Palette.bone,
                      size: 34,
                    ),
                    const SizedBox(height: 22),
                    Text('Camera access', style: AppText.display),
                    const SizedBox(height: 14),
                    Text(
                      'The volcano is shown on top of what the camera sees. '
                      'Nothing is recorded.',
                      style: AppText.body.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: access == CameraAccess.blocked
                          ? CameraPermission.openSettings
                          : () => _check(request: true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Palette.bone,
                        foregroundColor: Palette.onBone,
                        minimumSize: const Size.fromHeight(58),
                        textStyle: AppText.title.copyWith(
                          color: Palette.onBone,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        access == CameraAccess.blocked
                            ? 'Open settings'
                            : 'Allow camera',
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
            ],
          ],
        ),
      ),
    );
  }
}
