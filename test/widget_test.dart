import 'package:flutter_test/flutter_test.dart';
import 'package:smart_garden/main.dart';

void main() {
  testWidgets('Smart Garden khởi động và hiện Giám sát', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartGardenApp());
    await tester.pumpAndSettle();
    expect(find.text('Giám sát'), findsWidgets);
  });
}
