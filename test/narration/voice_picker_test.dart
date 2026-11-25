import 'package:flutter_test/flutter_test.dart';
import 'package:vulcanic/narration/voice_picker.dart';

Map<String, String> v(String name, String locale, {bool network = false}) => {
  'name': name,
  'locale': locale,
  'network_required': network ? '1' : '0',
};

void main() {
  const female = VoiceGender.female, male = VoiceGender.male;

  test('picks a male voice by default', () {
    final voice = VoicePicker.pick([
      v('en-us-x-tpf-local', 'en-US'), // female
      v('en-gb-x-rjs-local', 'en-GB'), // male, but British
      v('en-us-x-iom-local', 'en-US'), // male
      v('es-us-x-sfb-local', 'es-US'),
    ]);
    expect(voice!['name'], 'en-us-x-iom-local');
  });

  test('picks a female voice when asked', () {
    final voice = VoicePicker.pick([
      v('en-us-x-iom-local', 'en-US'),
      v('en-gb-x-gba-local', 'en-GB'),
      v('en-us-x-tpf-local', 'en-US'),
    ], gender: female);
    expect(voice!['name'], 'en-us-x-tpf-local');
  });

  test('a name that says the gender outright decides it', () {
    final f = v('en-us-x-sfg#female_1-local', 'en-US');
    final m = v('en-us-x-sfg#male_1-local', 'en-US');
    expect(VoicePicker.score(f, gender: female), 78);
    expect(VoicePicker.score(f, gender: male), 0);
    expect(VoicePicker.score(m, gender: male), 78);
    expect(VoicePicker.score(m, gender: female), 0);
  });

  test('recognises Samsung voices', () {
    final voices = [v('en-US-SMTm00', 'en_US'), v('en-US-SMTf00', 'en_US')];
    expect(VoicePicker.pick(voices)!['name'], 'en-US-SMTm00');
    expect(VoicePicker.pick(voices, gender: female)!['name'], 'en-US-SMTf00');
  });

  test('falls back to another English locale', () {
    final voice = VoicePicker.pick([
      v('en-us-x-tpf-local', 'en-US'), // female
      v('en-au-x-aub-local', 'en-AU'), // male
      v('fil-ph-x-fie-local', 'fil-PH'),
    ]);
    expect(voice!['name'], 'en-au-x-aub-local');
  });

  test('prefers an offline voice over the same one online', () {
    final voice = VoicePicker.pick([
      v('en-us-x-iom-network', 'en-US', network: true),
      v('en-us-x-iom-local', 'en-US'),
    ]);
    expect(voice!['name'], 'en-us-x-iom-local');
  });

  test('returns null when nothing is recognised', () {
    final voices = [
      v('en-US-language', 'en-US'),
      v('ja-jp-x-jab-local', 'ja-JP'),
    ];
    expect(VoicePicker.pick(voices), isNull);
    expect(VoicePicker.pick(voices, gender: female), isNull);
  });
}
