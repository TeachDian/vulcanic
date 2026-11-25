import 'package:flutter_test/flutter_test.dart';
import 'package:vulcanic/main.dart';

void main() {
  testWidgets('app boots into the engine preview', (tester) async {
    await tester.pumpWidget(const VulcanicApp());
    await tester.pump();
    expect(find.text('Erupt'), findsOneWidget);
    expect(find.text('See inside'), findsOneWidget);
  });
}
