import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vulcanic/content/parts.dart';
import 'package:vulcanic/engine/volcano_geometry.dart';
import 'package:vulcanic/narration/narrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads the name, the tagline and the description', () {
    for (final part in VolcanoPart.values) {
      final script = Narrator.scriptFor(part);
      expect(script, startsWith('${part.label}. '));
      expect(script, contains(part.info.tagline));
      expect(script, endsWith(part.info.description));
    }
  });

  test('every description is a few full sentences', () {
    for (final part in VolcanoPart.values) {
      final text = part.info.description;
      expect(text.split(' ').length, inInclusiveRange(30, 70));
      expect(text, endsWith('.'));
      expect(part.info.facts, isNotEmpty);
    }
  });

  group('recordings', () {
    test('a clip named after the component is used', () {
      const assets = [
        'assets/models/lava.obj',
        'assets/narration/lava.m4a',
        'assets/narration/chamber.mp3',
      ];
      expect(
        Narrator.clipIn(assets, VolcanoPart.lava),
        'assets/narration/lava.m4a',
      );
      expect(
        Narrator.clipIn(assets, VolcanoPart.chamber),
        'assets/narration/chamber.mp3',
      );
      expect(Narrator.clipIn(assets, VolcanoPart.cone), isNull);
    });

    test('m4a wins when a component has more than one recording', () {
      const assets = ['assets/narration/cone.wav', 'assets/narration/cone.m4a'];
      expect(
        Narrator.clipIn(assets, VolcanoPart.cone),
        'assets/narration/cone.m4a',
      );
    });

    // Rewrites the guide when asked to:
    //   flutter test test/narration --dart-define=WRITE_NARRATION_GUIDE=true
    test('the recording guide carries the current script', () {
      final guide = File('docs/narration.md');
      if (const bool.fromEnvironment('WRITE_NARRATION_GUIDE')) {
        final out = StringBuffer()
          ..writeln('# Recording the narration')
          ..writeln()
          ..writeln(
            'The app reads each component aloud. Out of the box it uses the '
            "phone's speech engine with a male voice. To use a real voice "
            'instead, record the five passages below and add them to the '
            'app. Any passage without a recording keeps the phone voice, so '
            'you can add them one at a time.',
          )
          ..writeln()
          ..writeln('## How')
          ..writeln()
          ..writeln(
            '1. Record each passage as its own file. A phone voice memo in a '
            'quiet room is enough. Leave half a second of silence at each '
            'end.',
          )
          ..writeln(
            '2. Save it as `.m4a` (or `.mp3`, `.ogg`, `.wav`, `.aac`) with '
            'the file name shown above its passage.',
          )
          ..writeln('3. Put the files in `assets/narration/`.')
          ..writeln('4. Rebuild the app. Nothing else needs changing.')
          ..writeln()
          ..writeln(
            'The words do not have to match exactly: the recording is '
            'played as it is.',
          )
          ..writeln()
          ..writeln('## Script');
        for (final part in VolcanoPart.values) {
          out
            ..writeln()
            ..writeln('### ${part.number} ${part.label}')
            ..writeln()
            ..writeln('File: `assets/narration/${part.asset}.m4a`')
            ..writeln()
            ..writeln('> ${Narrator.scriptFor(part)}');
        }
        guide.writeAsStringSync(out.toString());
      }
      final text = guide.readAsStringSync();
      for (final part in VolcanoPart.values) {
        expect(text, contains(Narrator.scriptFor(part)), reason: part.label);
        expect(text, contains('assets/narration/${part.asset}.m4a'));
      }
    });
  });

  test('falls silent when the phone has no speech engine', () async {
    final narrator = Narrator.instance;
    // No platform implementation is registered in tests.
    await narrator.toggle(VolcanoPart.lava);
    expect(narrator.speaking, isNull);
  });
}
