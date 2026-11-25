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

  test('falls silent when the phone has no speech engine', () async {
    final narrator = Narrator.instance;
    // No platform implementation is registered in tests.
    await narrator.toggle(VolcanoPart.lava);
    expect(narrator.speaking, isNull);
  });
}
