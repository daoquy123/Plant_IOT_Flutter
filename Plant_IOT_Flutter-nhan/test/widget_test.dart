import 'package:flutter_test/flutter_test.dart';
import 'package:smart_garden/main.dart';
import 'package:smart_garden/providers/settings_provider.dart';

void main() {
  testWidgets('Smart Garden khởi động và hiện Giám sát', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(SmartGardenApp(settings: SettingsProvider()));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Giám sát'), findsWidgets);
  });
}
