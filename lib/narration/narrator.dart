import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../content/parts.dart';
import '../engine/volcano_geometry.dart';
import 'voice_picker.dart';

/// Reads component descriptions aloud with the phone's speech engine.
class Narrator extends ChangeNotifier {
  Narrator._();

  /// One narrator for the whole app: there is only one speaker.
  static final Narrator instance = Narrator._();

  final FlutterTts _tts = FlutterTts();
  Future<void>? _ready;
  VolcanoPart? _speaking;
  DateTime _spokeAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// The component being read, if any.
  VolcanoPart? get speaking => _speaking;

  /// What is said for [part]: its name, then the card's text.
  static String scriptFor(VolcanoPart part) =>
      '${part.label}. ${part.info.tagline}. ${part.info.description}';

  Future<void> _prepare() async {
    _tts.setCompletionHandler(_finished);
    _tts.setCancelHandler(_finished);
    _tts.setErrorHandler((dynamic _) => _finished());
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5); // the engine's normal pace
    await _tts.setPitch(1.05);
    await _tts.setVolume(1);

    final voices = <Map<String, String>>[
      for (final voice in (await _tts.getVoices as List<dynamic>? ?? const []))
        if (voice is Map)
          {for (final entry in voice.entries) '${entry.key}': '${entry.value}'},
    ];
    final voice = VoicePicker.pick(voices);
    if (voice != null) {
      await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!});
    }
  }

  /// Starts reading [part], or stops if it is already being read.
  Future<void> toggle(VolcanoPart part) async {
    if (_speaking == part) return stop();
    await stop();
    _set(part);
    try {
      await (_ready ??= _prepare());
      if (_speaking != part) return; // stopped while getting ready
      _spokeAt = DateTime.now();
      final accepted = await _tts.speak(scriptFor(part));
      // The engine answers 1 when it has taken the text.
      if (accepted != 1 && _speaking == part) _set(null);
    } catch (_) {
      // No speech engine, or it refused: fall silent.
      _ready = null;
      _set(null);
    }
  }

  Future<void> stop() async {
    if (_speaking == null) return;
    _set(null);
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void _finished() {
    // Stopping one reading to start another reports the old one as
    // cancelled a moment after the new one has begun; ignore that.
    if (DateTime.now().difference(_spokeAt).inMilliseconds < 500) return;
    _set(null);
  }

  void _set(VolcanoPart? part) {
    if (_speaking == part) return;
    _speaking = part;
    notifyListeners();
  }
}
