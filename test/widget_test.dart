import 'package:flutter_test/flutter_test.dart';
import 'package:vulcanic/main.dart';

void main() {
  testWidgets('app boots to the home screen', (tester) async {
    await tester.pumpWidget(const VulcanicApp());
    // The models load through the real asset bundle, off the fake clock.
    for (
      var i = 0;
      i < 50 && find.text('Explore in 3D').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Explore in 3D'), findsOneWidget);
  });
}
