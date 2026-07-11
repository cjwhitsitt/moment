import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class EmulatorConfigService {
  static bool _configured = false;

  static void configure(String wsUrl) {
    if (_configured || kReleaseMode) return;

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
}
