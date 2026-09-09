import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/emulator_config_service.dart';

void main() {
  setUp(() {
    EmulatorConfigService.resetForTesting();
  });

  group('EmulatorConfigService', () {
    test('isCloudForced matches USE_CLOUD_RESOURCES compile-time environment flag', () {
      const expectedFlag = bool.fromEnvironment('USE_CLOUD_RESOURCES', defaultValue: false);
      expect(EmulatorConfigService.isCloudForced, equals(expectedFlag));
    });

    test('shouldUseEmulators respects debug mode and USE_CLOUD_RESOURCES flag', () {
      const expectedFlag = bool.fromEnvironment('USE_CLOUD_RESOURCES', defaultValue: false);
      final expectedUse = !kReleaseMode && !expectedFlag;
      expect(EmulatorConfigService.shouldUseEmulators, equals(expectedUse));
    });

    test('resetForTesting clears isConfigured state', () {
      EmulatorConfigService.resetForTesting();
      expect(EmulatorConfigService.isConfigured, isFalse);
    });
  });
}
