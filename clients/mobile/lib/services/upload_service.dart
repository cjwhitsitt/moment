import 'dart:io';
import 'package:camera/camera.dart';
import 'package:firebase_storage/firebase_storage.dart';

class UploadService {
  /// Connects the Firebase Storage SDK to the local emulator running on the coordinator host.
  static void configureEmulator(String host, int port) {
    try {
      FirebaseStorage.instance.useStorageEmulator(host, port);
    } catch (e) {
      // Ignored if already connected
    }
  }

  /// Captures a frame using the camera controller and uploads it directly to Firebase Storage.
  static Future<String> takeAndUploadPicture(
    CameraController controller,
    String sessionId,
    int cameraIndex,
  ) async {
    // Shutter capture (hot path, keep fast)
    final XFile file = await controller.takePicture();

    // Asynchronous upload path
    final String storagePath = 'raw/$sessionId/cam$cameraIndex.jpg';
    final ref = FirebaseStorage.instance.ref().child(storagePath);
    
    await ref.putFile(File(file.path));
    return storagePath;
  }
}
