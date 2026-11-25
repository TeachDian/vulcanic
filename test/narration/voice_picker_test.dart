import 'package:flutter_test/flutter_test.dart';
import 'package:vulcanic/narration/voice_picker.dart';

Map<String, String> v(String name, String locale, {bool network = false}) => {
  'name': name,
  'locale': locale,
  'network_required': network ? '1' : '0',
};

void main() {
  test('prefers a known female Google voice in US English', () {
    final voice = VoicePicker.pick([
      v('en-us-x-iom-local', 'en-US'), // male
      v('en-gb-x-gba-local', 'en-GB'), // female, but British
      v('en-us-x-tpf-local', 'en-US'), // female
      v('es-us-x-sfb-local', 'es-US'),
    ]);
    expect(voice!['name'], 'en-us-x-tpf-local');
  });

  test('"female" in the name wins, "male" loses', () {
    expect(VoicePicker.score(v('en-us-x-sfg#female_1-local', 'en-US')), 78);
    expect(VoicePicker.score(v('en-us-x-sfg#male_1-local', 'en-US')), 0);
  });

  test('recognises Samsung voices', () {
    final voice = VoicePicker.pick([
      v('en-US-SMTm00', 'en_US'),
      v('en-US-SMTf00', 'en_US'),
    ]);
    expect(voice!['name'], 'en-US-SMTf00');
  });

  test('falls back to another English locale', () {
    final voice = VoicePicker.pick([
      v('en-us-x-iol-local', 'en-US'), // male
      v('en-au-x-aua-local', 'en-AU'), // female
      v('fil-ph-x-fie-local', 'fil-PH'),
    ]);
    expect(voice!['name'], 'en-au-x-aua-local');
  });

  test('prefers an offline voice over the same one online', () {
    final voice = VoicePicker.pick([
      v('en-us-x-sfg-network', 'en-US', network: true),
      v('en-us-x-sfg-local', 'en-US'),
    ]);
    expect(voice!['name'], 'en-us-x-sfg-local');
  });

  test('returns null when nothing is recognised', () {
    expect(
      VoicePicker.pick([
        v('en-US-language', 'en-US'),
        v('ja-jp-x-jab-local', 'ja-JP'),
      ]),
      isNull,
    );
  });
}
