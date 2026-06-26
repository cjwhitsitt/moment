import 'package:cloud_firestore/cloud_firestore.dart';

class SessionService {
  /// Connects the Firestore SDK to the local emulator running on the coordinator host.
  static void configureEmulator(String host, int port) {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );
      FirebaseFirestore.instance.useFirestoreEmulator(host, port);
    } catch (e) {
      // Ignored if already connected
    }
  }

  /// Updates the Firestore session document with the newly uploaded camera frame path.
  /// If the document doesn't exist, it creates it.
  static Future<void> updateFrameUpload(
    String sessionId,
    int cameraIndex,
    String storagePath,
    int expectedFrames,
  ) async {
    final docRef = FirebaseFirestore.instance.collection('sessions').doc(sessionId);
    await docRef.set({
      'id': sessionId,
      'status': 'uploading',
      'expectedFrames': expectedFrames,
      'uploadedFrames': {
        cameraIndex.toString(): storagePath,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
