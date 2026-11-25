/// The kind of voice the narrator should use when it falls back to the
/// phone's speech engine.
enum VoiceGender { male, female }

/// Chooses an English voice of the wanted gender from what the phone's
/// speech engine offers.
///
/// Android does not label voices with a gender, so this goes by name: first
/// names that say so outright, then the known voices of Google's and
/// Samsung's engines. When nothing matches, the engine's default English
/// voice is used.
abstract final class VoicePicker {
  /// Google speech engine voice codes by gender and locale.
  static const Map<VoiceGender, Map<String, List<String>>> _google = {
    VoiceGender.female: {
      'en-us': ['sfg', 'iob', 'tpc', 'tpf'],
      'en-gb': ['gba', 'gbc', 'gbg', 'fis'],
      'en-au': ['aua', 'auc'],
      'en-in': ['ahp', 'cxx', 'ena', 'enc'],
    },
    VoiceGender.male: {
      'en-us': ['iom', 'iol', 'iog', 'tpd'],
      'en-gb': ['rjs', 'gbb', 'gbd'],
      'en-au': ['aub', 'aud'],
      'en-in': ['end', 'ene'],
    },
  };

  /// Locales in order of preference.
  static const List<String> _locales = ['en-us', 'en-gb', 'en-au', 'en-in'];

  /// Scores [voice] for [gender]; higher is better, zero means "not a known
  /// English voice of that gender".
  static int score(
    Map<String, String> voice, {
    VoiceGender gender = VoiceGender.male,
  }) {
    final name = (voice['name'] ?? '').toLowerCase();
    final locale = (voice['locale'] ?? '').toLowerCase().replaceAll('_', '-');
    if (!locale.startsWith('en')) return 0;

    // "female" contains "male", so test for it first.
    final saysFemale = name.contains('female');
    final saysMale = !saysFemale && name.contains('male');
    final wanted = gender == VoiceGender.female ? saysFemale : saysMale;
    final other = gender == VoiceGender.female ? saysMale : saysFemale;

    var points = 0;
    if (wanted) {
      points = 60;
    } else if (other) {
      return 0;
    } else if (RegExp(
      gender == VoiceGender.female ? r'smt[a-z]*f\d' : r'smt[a-z]*m\d',
    ).hasMatch(name)) {
      points = 50; // Samsung: en-US-SMTf00, en-US-SMTm00
    } else {
      final codes = _google[gender]![locale] ?? const <String>[];
      // Google: en-us-x-iom-local, en-us-x-iom-network
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

  /// The best English voice of [gender] among [voices], or null if none is
  /// recognised.
  static Map<String, String>? pick(
    Iterable<Map<String, String>> voices, {
    VoiceGender gender = VoiceGender.male,
  }) {
    Map<String, String>? best;
    var bestScore = 0;
    for (final voice in voices) {
      final s = score(voice, gender: gender);
      if (s > bestScore) {
        best = voice;
        bestScore = s;
      }
    }
    return best;
  }
}
