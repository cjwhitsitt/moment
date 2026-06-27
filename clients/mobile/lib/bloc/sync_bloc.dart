import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/websocket_client.dart';
import '../services/ntp_service.dart';

// States
abstract class SyncState {}

class SyncInitial extends SyncState {}

class SyncPairing extends SyncState {}

class SyncConnecting extends SyncState {
  final String url;
  final int cameraIndex;
  SyncConnecting(this.url, this.cameraIndex);
}

class SyncConnected extends SyncState {
  final String url;
  final int cameraIndex;
  final String status;
  final int clockOffsetMs;
  SyncConnected({
    required this.url,
    required this.cameraIndex,
    required this.status,
    this.clockOffsetMs = 0,
  });

  SyncConnected copyWith({
    String? url,
    int? cameraIndex,
    String? status,
    int? clockOffsetMs,
  }) {
    return SyncConnected(
      url: url ?? this.url,
      cameraIndex: cameraIndex ?? this.cameraIndex,
      status: status ?? this.status,
      clockOffsetMs: clockOffsetMs ?? this.clockOffsetMs,
    );
  }
}

class SyncCaptureTriggered extends SyncState {
  final String sessionId;
  final int cameraIndex;
  final int expectedFrames;
  SyncCaptureTriggered({required this.sessionId, required this.cameraIndex, required this.expectedFrames});
}

class SyncError extends SyncState {
  final String message;
  SyncError(this.message);
}

// Events
abstract class SyncEvent {}

class StartPairingEvent extends SyncEvent {}

class ConnectEvent extends SyncEvent {
  final String wsUrl;
  final int cameraIndex;
  ConnectEvent({required this.wsUrl, required this.cameraIndex});
}

class DisconnectEvent extends SyncEvent {}

class MessageReceivedEvent extends SyncEvent {
  final Map<String, dynamic> message;
  MessageReceivedEvent(this.message);
}

class UpdateClockOffsetEvent extends SyncEvent {
  final int offsetMs;
  UpdateClockOffsetEvent(this.offsetMs);
}

class FireShutterEvent extends SyncEvent {
  final String sessionId;
  final int expectedFrames;
  FireShutterEvent(this.sessionId, this.expectedFrames);
}

class SessionCompletedEvent extends SyncEvent {
  final String sessionId;
  final String status;
  final String? gifUrl;
  final String? error;
  SessionCompletedEvent({
    required this.sessionId,
    required this.status,
    this.gifUrl,
    this.error,
  });
}

class SendStatusUpdateEvent extends SyncEvent {
  final String sessionId;
  final String status;
  final String? errorMessage;
  SendStatusUpdateEvent({
    required this.sessionId,
    required this.status,
    this.errorMessage,
  });
}

// Bloc Implementation
class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final WebSocketClient _wsClient;
  StreamSubscription? _wsSubscription;
  final Map<String, StreamSubscription> _sessionSubscriptions = {};
  int _clockOffsetMs = 0;

  SyncBloc(this._wsClient) : super(SyncInitial()) {
    on<StartPairingEvent>((event, emit) => emit(SyncPairing()));

    on<ConnectEvent>((event, emit) async {
      emit(SyncConnecting(event.wsUrl, event.cameraIndex));
      try {
        await _wsClient.connect(event.wsUrl);
        _wsSubscription?.cancel();
        _wsSubscription = _wsClient.messages.listen((msg) {
          add(MessageReceivedEvent(msg));
        });

        // Trigger registration handshake
        _wsClient.send('client_register', {
          'camera_index': event.cameraIndex,
          'device_name': PlatformDeviceInfo.getDeviceName(),
        });

        // Trigger background NTP clock synchronization
        _runNtpSync(event.wsUrl);
      } catch (e) {
        WakelockPlus.disable();
        emit(SyncError('Connection failed: ${e.toString()}'));
      }
    });

    on<MessageReceivedEvent>((event, emit) async {
      final msg = event.message;
      final eventName = msg['event'] as String?;
      final data = msg['data'] as Map<String, dynamic>? ?? {};

      if (eventName == 'client_registered') {
        final status = data['status'] as String? ?? 'failed';
        final index = data['camera_index'] as int? ?? 0;
        if (state is SyncConnecting) {
          final connState = state as SyncConnecting;
          if (status == 'ready' && index == connState.cameraIndex) {
            WakelockPlus.enable(); // Keep device screen awake while registered
            emit(SyncConnected(
              url: connState.url,
              cameraIndex: connState.cameraIndex,
              status: 'ready',
              clockOffsetMs: _clockOffsetMs,
            ));
          } else {
            WakelockPlus.disable();
            emit(SyncError('Coordinator registration rejected.'));
          }
        }
      } else if (eventName == 'capture_trigger') {
        final sessionId = data['session_id'] as String? ?? '';
        final triggerEpochMs = data['trigger_epoch_ms'] as int? ?? 0;
        final expectedFrames = data['expected_frames'] as int? ?? 5;
 
        // Perform synchronized latency wait
        final now = DateTime.now().millisecondsSinceEpoch;
        final clientTimeWithDrift = now + _clockOffsetMs;
        final delayMs = triggerEpochMs - clientTimeWithDrift;
 
        if (delayMs > 0) {
          await Future.delayed(Duration(milliseconds: delayMs));
        }
        add(FireShutterEvent(sessionId, expectedFrames));
      } else if (eventName == 'disconnected') {
        WakelockPlus.disable(); // Release wake lock
        emit(SyncInitial());
      } else if (eventName == 'error') {
        WakelockPlus.disable();
        emit(SyncError(msg['error'] as String? ?? 'WebSocket error'));
      }
    });

    on<UpdateClockOffsetEvent>((event, emit) {
      _clockOffsetMs = event.offsetMs;
      if (state is SyncConnected) {
        final s = state as SyncConnected;
        emit(s.copyWith(clockOffsetMs: _clockOffsetMs));
      }
    });

    on<FireShutterEvent>((event, emit) {
      if (state is SyncConnected) {
        final s = state as SyncConnected;
        emit(SyncCaptureTriggered(
          sessionId: event.sessionId,
          cameraIndex: s.cameraIndex,
          expectedFrames: event.expectedFrames,
        ));

        // Start listening to the Firestore session state for completion
        _listenToSessionCompletion(event.sessionId, s.cameraIndex);

        emit(s);
      }
    });

    on<SendStatusUpdateEvent>((event, emit) {
      if (state is SyncConnected) {
        _wsClient.send('status_update', {
          'session_id': event.sessionId,
          'camera_index': (state as SyncConnected).cameraIndex,
          'status': event.status,
          'battery_level': 85,
          'error_message': event.errorMessage,
        });
      }
    });

    on<SessionCompletedEvent>((event, emit) {
      _sessionSubscriptions[event.sessionId]?.cancel();
      _sessionSubscriptions.remove(event.sessionId);

      // Report completion/failure back to Go coordinator over WebSockets
      if (state is SyncConnected) {
        _wsClient.send('status_update', {
          'session_id': event.sessionId,
          'camera_index': (state as SyncConnected).cameraIndex,
          'status': event.status,
          'battery_level': 85,
          'gif_url': event.gifUrl,
          'error_message': event.error,
        });
      }
    });

    on<DisconnectEvent>((event, emit) async {
      _wsSubscription?.cancel();
      _cancelAllSessionSubscriptions();
      await _wsClient.disconnect();
      WakelockPlus.disable(); // Release wake lock
      emit(SyncInitial());
    });
  }

  void _runNtpSync(String wsUrl) async {
    try {
      final uri = Uri.parse(wsUrl.replaceFirst('ws://', 'http://'));
      final host = uri.host;
      final offset = await NtpService.getClockOffset(host, 1230);
      add(UpdateClockOffsetEvent(offset));
    } catch (e) {
      // Clock offset fallback remains 0
    }
  }

  void _listenToSessionCompletion(String sessionId, int cameraIndex) {
    if (_sessionSubscriptions.containsKey(sessionId)) return;

    final subscription = FirebaseFirestore.instance
        .collection('sessions')
        .doc(sessionId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;
      final data = snapshot.data();
      if (data == null) return;

      final status = data['status'] as String?;
      if (status == 'completed') {
        final gifUrl = data['gifUrl'] as String?;
        add(SessionCompletedEvent(
          sessionId: sessionId,
          status: 'completed',
          gifUrl: gifUrl,
        ));
      } else if (status == 'failed') {
        final err = data['errorMessage'] as String?;
        add(SessionCompletedEvent(
          sessionId: sessionId,
          status: 'failed',
          error: err,
        ));
      }
    });

    _sessionSubscriptions[sessionId] = subscription;
  }

  void _cancelAllSessionSubscriptions() {
    for (var sub in _sessionSubscriptions.values) {
      sub.cancel();
    }
    _sessionSubscriptions.clear();
  }

  @override
  Future<void> close() {
    _wsSubscription?.cancel();
    _cancelAllSessionSubscriptions();
    WakelockPlus.disable(); // Always ensure wake lock is released on close
    return super.close();
  }
}

// Simple Helper to mock device details
class PlatformDeviceInfo {
  static String getDeviceName() {
    return 'Camera Node';
  }
}
