import 'package:ntp/ntp.dart';

class NtpService {
  /// Queries the local NTP server on the coordinator to calculate clock drift.
  static Future<int> getClockOffset(String host, int port) async {
    try {
      final offset = await NTP.getNtpOffset(
        lookUpAddress: host,
        port: port,
        timeout: const Duration(seconds: 3),
      );
      return offset;
    } catch (e) {
      // Fallback or bubble up error
      rethrow;
    }
  }
}
