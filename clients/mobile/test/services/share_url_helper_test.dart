import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/share_url_helper.dart';

void main() {
  group('ShareUrlHelper', () {
    test('isLocalHost identifies local IPs and localhost', () {
      expect(ShareUrlHelper.isLocalHost('localhost'), isTrue);
      expect(ShareUrlHelper.isLocalHost('127.0.0.1'), isTrue);
      expect(ShareUrlHelper.isLocalHost('192.168.1.50'), isTrue);
      expect(ShareUrlHelper.isLocalHost('10.0.0.2'), isTrue);
      expect(ShareUrlHelper.isLocalHost('172.16.0.1'), isTrue);
      expect(ShareUrlHelper.isLocalHost('example.com'), isFalse);
      expect(ShareUrlHelper.isLocalHost('moment-aad8b.web.app'), isFalse);
    });

    test('getGifUrl returns local emulator URL when useEmulators is true', () {
      final url = ShareUrlHelper.getGifUrl(
        host: '192.168.1.100',
        sessionId: 'session-123',
        useEmulators: true,
      );
      expect(
        url,
        'http://192.168.1.100:9199/v0/b/moment-aad8b.firebasestorage.app/o/stitched%2Fsession-123.gif?alt=media',
      );
    });

    test('getGifUrl returns production Cloud Storage URL when useEmulators is false', () {
      final url = ShareUrlHelper.getGifUrl(
        host: '192.168.1.100',
        sessionId: 'session-123',
        useEmulators: false,
      );
      expect(
        url,
        'https://firebasestorage.googleapis.com/v0/b/moment-aad8b.firebasestorage.app/o/stitched%2Fsession-123.gif?alt=media',
      );
    });

    test('getHostingBaseUrl returns local port 5000 when useEmulators is true', () {
      final url = ShareUrlHelper.getHostingBaseUrl(
        host: '192.168.1.100',
        useEmulators: true,
      );
      expect(url, 'http://192.168.1.100:5000');
    });

    test('getHostingBaseUrl returns production web.app when useEmulators is false', () {
      final url = ShareUrlHelper.getHostingBaseUrl(
        host: '192.168.1.100',
        useEmulators: false,
      );
      expect(url, 'https://moment-aad8b.web.app');
    });

    test('getShareLandingPageUrl encodes full URL with query parameter', () {
      final url = ShareUrlHelper.getShareLandingPageUrl(
        host: '192.168.1.100',
        sessionId: 'session-abc',
        useEmulators: false,
      );
      expect(url, startsWith('https://moment-aad8b.web.app/?gif='));
      expect(url, contains('firebasestorage.googleapis.com'));
    });
  });
}
