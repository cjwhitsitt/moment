import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class EmulatorConfigService {
  static bool _configured = false;

  /// Returns true if live cloud resources are forced via compile-time flag.
  static bool get isCloudForced =>
      const bool.fromEnvironment('USE_CLOUD_RESOURCES', defaultValue: false);

  /// Returns true if local Firebase emulators should be used.
  /// Emulators are used ONLY when running in debug/profile mode (!kReleaseMode)
  /// AND USE_CLOUD_RESOURCES is NOT true.
  static bool get shouldUseEmulators => !kReleaseMode && !isCloudForced;

  /// Returns true if the service has successfully configured emulators in this session.
  static bool get isConfigured => _configured;

  static void configure(String wsUrl) {
    if (_configured || !shouldUseEmulators) return;

    try {
      final uri = Uri.parse(wsUrl.replaceFirst('ws://', 'http://'));
      final host = uri.host;

      // 1. Configure Firestore (8082)
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8082);

      // 2. Configure Storage (9199)
      FirebaseStorage.instance.useStorageEmulator(host, 9199);

      // 3. Configure Functions (5001)
      FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);

      _configured = true;
    } catch (e) {
      // Ignored if already configured or connected
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _configured = false;
  }
}

