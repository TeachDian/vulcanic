import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../content/parts.dart';
import '../engine/volcano_geometry.dart';
import 'voice_picker.dart';

/// Reads component descriptions aloud.
///
/// A recorded clip is used when the app ships one for the component
/// (`assets/narration/<component>.m4a`, see docs/narration.md). Otherwise
/// the phone's speech engine reads the same text.
class Narrator extends ChangeNotifier {
  Narrator._() {
    _clips.setMethodCallHandler((call) async {
      // A clip played to its end (stopping one does not report back).
      if (call.method == 'done') _set(null);
    });
  }

  /// One narrator for the whole app: there is only one speaker.
  static final Narrator instance = Narrator._();

  /// The voice used when there is no recording.
  static const VoiceGender fallbackVoice = VoiceGender.male;

  /// Audio formats a recording may be in, in order of preference.
  static const List<String> clipFormats = ['m4a', 'mp3', 'ogg', 'wav', 'aac'];

  static const MethodChannel _clips = MethodChannel('vulcanic/narration');

  final FlutterTts _tts = FlutterTts();
  Future<void>? _ready;
  Future<List<String>>? _bundled;
  VolcanoPart? _speaking;
  bool _playingClip = false;
  DateTime _spokeAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// The component being read, if any.
  VolcanoPart? get speaking => _speaking;

  /// What is said for [part]: its name, then the full explanation. This is
  /// also the script to record.
  static String scriptFor(VolcanoPart part) =>
      '${part.label}. ${part.info.tagline}. ${part.info.description}';

  /// The recording for [part] among the bundled [assets], if there is one.
  static String? clipIn(Iterable<String> assets, VolcanoPart part) {
    for (final format in clipFormats) {
      final path = 'assets/narration/${part.asset}.$format';
      if (assets.contains(path)) return path;
    }
    return null;
  }

  /// Replaces the bundled asset list, so tests can pretend a recording
  /// exists.
  @visibleForTesting
  set debugAssets(List<String>? assets) =>
      _bundled = assets == null ? null : Future.value(assets);

  Future<List<String>> _listAssets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest.listAssets();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _prepareSpeech() async {
    _tts.setCompletionHandler(_speechFinished);
    _tts.setCancelHandler(_speechFinished);
    _tts.setErrorHandler((dynamic _) => _speechFinished());
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5); // the engine's normal pace
    await _tts.setPitch(fallbackVoice == VoiceGender.male ? 0.96 : 1.05);
    await _tts.setVolume(1);

    final voices = <Map<String, String>>[
      for (final voice in (await _tts.getVoices as List<dynamic>? ?? const []))
        if (voice is Map)
          {for (final entry in voice.entries) '${entry.key}': '${entry.value}'},
    ];
    final voice = VoicePicker.pick(voices, gender: fallbackVoice);
    if (voice != null) {
      await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!});
    }
  }

  /// Starts reading [part], or stops if it is already being read.
  Future<void> toggle(VolcanoPart part) async {
    if (_speaking == part) return stop();
    await stop();
    _set(part);

    // A recording, if the app has one for this component.
    final clip = clipIn(await (_bundled ??= _listAssets()), part);
    if (_speaking != part) return; // stopped while looking
    if (clip != null && await _playClip(clip)) {
      _playingClip = true;
      return;
    }

    // Otherwise the phone's own voice.
    try {
      await (_ready ??= _prepareSpeech());
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

  Future<bool> _playClip(String asset) async {
    try {
      return await _clips.invokeMethod<bool>('play', {'asset': asset}) ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    if (_speaking == null) return;
    // Read the flag first: clearing the speaker clears it too.
    final wasClip = _playingClip;
    _set(null);
    if (wasClip) {
      try {
        await _clips.invokeMethod<void>('stop');
      } catch (_) {}
      return;
    }
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void _speechFinished() {
    if (_playingClip) return; // a stray callback from an earlier reading
    // Stopping one reading to start another reports the old one as
    // cancelled a moment after the new one has begun; ignore that.
    if (DateTime.now().difference(_spokeAt).inMilliseconds < 500) return;
    _set(null);
  }

  void _set(VolcanoPart? part) {
    if (part == null) _playingClip = false;
    if (_speaking == part) return;
    _speaking = part;
    notifyListeners();
  }
}
