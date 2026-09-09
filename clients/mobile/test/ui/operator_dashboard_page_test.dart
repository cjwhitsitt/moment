import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/emulator_config_service.dart';
import 'package:mobile/ui/operator_dashboard_page.dart';

void main() {
  testWidgets('OperatorAppBarTitle displays title and conditionally renders EMULATOR badge', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const OperatorAppBarTitle(),
          ),
        ),
      ),
    );

    expect(find.text('OPERATOR DASHBOARD'), findsOneWidget);

    if (EmulatorConfigService.shouldUseEmulators) {
      expect(find.byKey(const Key('emulator_badge')), findsOneWidget);
      expect(find.text('EMULATOR'), findsOneWidget);
    } else {
      expect(find.byKey(const Key('emulator_badge')), findsNothing);
    }
  });
}
