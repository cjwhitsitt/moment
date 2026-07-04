import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('PhotoBoothApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PhotoBoothApp());

    // Verify that the setup selection screen is displayed.
    expect(find.text('M O M E N T'), findsOneWidget);
  });
}
