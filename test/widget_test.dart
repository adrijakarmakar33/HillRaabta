import 'package:flutter_test/flutter_test.dart';
import 'package:hill_raabta/main.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    await tester.pumpWidget(const HillRaabtaApp());
  });
}
