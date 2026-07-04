import 'dart:convert';
import 'dart:io';
import 'dart:async';

class WebSocketClient {
  WebSocket? _socket;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  bool get isConnected => _socket != null && _socket!.readyState == WebSocket.open;

  Future<void> connect(String url) async {
    try {
      _socket = await WebSocket.connect(url).timeout(const Duration(seconds: 5));
      _socket!.listen(
        (data) {
          try {
            final text = data as String;
            final lines = text.split('\n');
            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) continue;
              final parsed = jsonDecode(trimmed) as Map<String, dynamic>;
              _messageController.add(parsed);
            }
          } catch (e) {
            // Ignored parsing issue on malformed message
          }
        },
        onDone: () {
          _socket = null;
          _messageController.add({'event': 'disconnected'});
        },
        onError: (err) {
          _socket = null;
          _messageController.add({'event': 'error', 'error': err.toString()});
        },
      );
    } catch (e) {
      _socket = null;
      rethrow;
    }
  }

  void send(String event, Map<String, dynamic> data) {
    if (isConnected) {
      _socket!.add(jsonEncode({
        'event': event,
        'data': data,
      }));
    }
  }

  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
  }
}
