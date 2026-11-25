import 'package:mobile_scanner/mobile_scanner.dart';

/// Opens the camera behind [controller], retrying for a moment.
///
/// Only one thing can hold the camera at a time. When a screen opens right
/// after another one closed (for instance marker mode straight after an
/// ARCore session), the previous owner may still be letting go, and the
/// first attempt fails.
Future<void> startCamera(
  MobileScannerController controller, {
  required bool Function() stillWanted,
}) async {
  for (final wait in const [0, 400, 900, 1800]) {
    await Future<void>.delayed(Duration(milliseconds: wait));
    if (!stillWanted()) return;
    try {
      await controller.start();
    } on MobileScannerException catch (_) {
      // Still busy; try again.
    }
    // A failed start is also reported through the controller's value
    // rather than thrown, so check that it is really running.
    if (!stillWanted() || controller.value.isRunning) return;
  }
}
