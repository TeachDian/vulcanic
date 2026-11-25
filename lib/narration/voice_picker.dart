/// Chooses a female English voice from what the phone's speech engine offers.
///
/// Android does not label voices with a gender, so this goes by name: first
/// names that say so outright, then the known female voices of Google's and
/// Samsung's engines. When nothing matches, the engine's default English
/// voice is used, which is female on both.
abstract final class VoicePicker {
  /// Google speech engine voice codes that are female, by locale.
  static const Map<String, List<String>> _googleFemale = {
    'en-us': ['sfg', 'iob', 'tpc', 'tpf'],
    'en-gb': ['gba', 'gbc', 'gbg', 'fis'],
    'en-au': ['aua', 'auc'],
    'en-in': ['ahp', 'cxx', 'ena', 'enc'],
  };

  /// Locales in order of preference.
  static const List<String> _locales = ['en-us', 'en-gb', 'en-au', 'en-in'];

  /// Scores [voice]; higher is better, zero means "not a known female
  /// English voice".
  static int score(Map<String, String> voice) {
    final name = (voice['name'] ?? '').toLowerCase();
    final locale = (voice['locale'] ?? '').toLowerCase().replaceAll('_', '-');
    if (!locale.startsWith('en')) return 0;

    var points = 0;
    if (name.contains('female')) {
      points = 60;
    } else if (name.contains('male')) {
      return 0;
    } else if (RegExp(r'smt[a-z]*f\d').hasMatch(name)) {
      points = 50; // Samsung: en-US-SMTf00
    } else {
      final codes = _googleFemale[locale] ?? const <String>[];
      // Google: en-us-x-sfg-local, en-us-x-sfg-network
      final match = RegExp(r'-x-([a-z]{3})').firstMatch(name);
      if (match != null && codes.contains(match.group(1))) points = 40;
    }
    if (points == 0) return 0;

    // Prefer the preferred locales, and voices that work offline.
    final rank = _locales.indexOf(locale);
    points += rank < 0 ? 0 : (_locales.length - rank) * 4;
    if (name.contains('local')) points += 2;
    if (voice['network_required'] == '1') points -= 1;
    return points;
  }

  /// The best female English voice among [voices], or null if none is
  /// recognised.
  static Map<String, String>? pick(Iterable<Map<String, String>> voices) {
    Map<String, String>? best;
    var bestScore = 0;
    for (final voice in voices) {
      final s = score(voice);
      if (s > bestScore) {
        best = voice;
        bestScore = s;
      }
    }
    return best;
  }
}
