import 'dart:async';
import 'package:nsd/nsd.dart';

class DiscoveryService {
  Discovery? _discovery;
  final _controller = StreamController<Service>.broadcast();

  Stream<Service> get discoveredServices => _controller.stream;

  Future<void> start() async {
    if (_discovery != null) return;
    try {
      _discovery = await startDiscovery('_moment-coord._tcp');
      _discovery!.addListener(() {
        for (final service in _discovery!.services) {
          if (service.host != null && service.port != null) {
            _controller.add(service);
          }
        }
      });
    } catch (e) {
      print('Failed to start mDNS discovery: $e');
    }
  }

  Future<void> stop() async {
    if (_discovery == null) return;
    try {
      await stopDiscovery(_discovery!);
      _discovery = null;
    } catch (e) {
      print('Failed to stop mDNS discovery: $e');
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
