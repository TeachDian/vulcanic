import 'package:flutter_test/flutter_test.dart';
import 'package:vulcanic/main.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(const VulcanicApp());
    expect(find.text('Vulcanic'), findsOneWidget);
  });
}
