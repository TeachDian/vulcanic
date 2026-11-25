import 'package:flutter/services.dart';

/// Saves pictures to the phone's gallery (Pictures/Vulcanic).
abstract final class Gallery {
  static const MethodChannel _channel = MethodChannel('vulcanic/media');

  /// Photographs what is on screen, camera image included. Returns the file
  /// name, or null if it could not be saved.
  static Future<String?> captureScreen() => _invoke('capture');

  /// Saves PNG [bytes] under [name]. Returns the file name, or null.
  static Future<String?> savePng(Uint8List bytes, String name) =>
      _invoke('saveImage', {'bytes': bytes, 'name': name});

  /// Turns the screen up to full brightness and keeps it awake, or puts
  /// both back. Used while this phone is standing in for a printed marker.
  static Future<void> present(bool on) async {
    try {
      await _channel.invokeMethod<void>('present', {'on': on});
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  static Future<String?> _invoke(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<String>(method, arguments);
    } on PlatformException catch (_) {
      return null;
    } on MissingPluginException catch (_) {
      return null;
    }
  }
}
