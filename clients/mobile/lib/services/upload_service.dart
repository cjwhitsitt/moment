import 'dart:io';
import 'package:camera/camera.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;

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

    // Physically bake the orientation into the captured JPEG file
    try {
      final File imageFile = File(file.path);
      final bytes = await imageFile.readAsBytes();
      final img.Image? decodedImage = img.decodeImage(bytes);
      if (decodedImage != null) {
        final orientedImage = img.bakeOrientation(decodedImage);
        final rotatedBytes = img.encodeJpg(orientedImage);
        await imageFile.writeAsBytes(rotatedBytes);
      }
    } catch (e) {
      // Fallback: If rotation fails, log the error but still upload the unrotated frame
      // to avoid breaking the stitching pipeline completeness trigger.
    }

    // Asynchronous upload path
    final String storagePath = 'raw/$sessionId/cam$cameraIndex.jpg';
    final ref = FirebaseStorage.instance.ref().child(storagePath);
    
    await ref.putFile(File(file.path));
    return storagePath;
  }
}
