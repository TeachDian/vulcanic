import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulcanic/ar/ar_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vulcanic/ar');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers the support check with [answers] in turn, repeating the last.
  void respond(List<String> answers) {
    var call = 0;
    messenger.setMockMethodCallHandler(channel, (request) async {
      if (request.method == 'install') return answers.last;
      final answer = answers[call < answers.length ? call : answers.length - 1];
      call++;
      return answer;
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('keeps asking while ARCore is still checking', () async {
    respond(['checking', 'checking', 'checking', 'supported']);
    expect(
      await ArSession.availability(patience: const Duration(seconds: 5)),
      ArAvailability.supported,
    );
  });

  test('a slow check is not mistaken for no support', () async {
    // Twenty "still checking" answers is five seconds of polling: longer
    // than the old three second limit, well inside the new one.
    respond([...List.filled(20, 'checking'), 'supported']);
    expect(await ArSession.availability(), ArAvailability.supported);
  });

  test('gives up once its patience runs out', () async {
    respond(['checking']);
    expect(
      await ArSession.availability(patience: const Duration(milliseconds: 600)),
      ArAvailability.unsupported,
    );
  });

  test('reports a phone that needs AR services installed', () async {
    respond(['installable']);
    expect(await ArSession.availability(), ArAvailability.installable);
  });

  test('maps the install outcome', () async {
    for (final (answer, outcome) in const [
      ('installed', ArInstall.installed),
      ('requested', ArInstall.requested),
      ('declined', ArInstall.declined),
    ]) {
      respond([answer]);
      expect(await ArSession.requestInstall(), outcome);
    }
  });

  test('without the platform side there is no AR', () async {
    expect(
      await ArSession.availability(patience: Duration.zero),
      ArAvailability.unsupported,
    );
    expect(await ArSession.requestInstall(), ArInstall.declined);
  });
}
