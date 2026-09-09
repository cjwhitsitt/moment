import 'emulator_config_service.dart';

class ShareUrlHelper {
  static bool isLocalHost(String host) {
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.');
  }

  static String getGifUrl({
    required String host,
    required String sessionId,
    bool? useEmulators,
  }) {
    final emulators = useEmulators ?? EmulatorConfigService.shouldUseEmulators;
    if (emulators && isLocalHost(host)) {
      return 'http://$host:9199/v0/b/moment-aad8b.firebasestorage.app/o/stitched%2F$sessionId.gif?alt=media';
    }
    return 'https://firebasestorage.googleapis.com/v0/b/moment-aad8b.firebasestorage.app/o/stitched%2F$sessionId.gif?alt=media';
  }

  static String getHostingBaseUrl({
    required String host,
    bool? useEmulators,
  }) {
    final emulators = useEmulators ?? EmulatorConfigService.shouldUseEmulators;
    if (emulators && isLocalHost(host)) {
      return 'http://$host:5000';
    }
    return 'https://moment-aad8b.web.app';
  }

  static String getShareLandingPageUrl({
    required String host,
    required String sessionId,
    bool? useEmulators,
  }) {
    final gifUrl = getGifUrl(host: host, sessionId: sessionId, useEmulators: useEmulators);
    final hostingBaseUrl = getHostingBaseUrl(host: host, useEmulators: useEmulators);
    return '$hostingBaseUrl/?gif=${Uri.encodeComponent(gifUrl)}';
  }
}
