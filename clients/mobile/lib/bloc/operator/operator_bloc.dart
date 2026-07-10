import 'dart:async';
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/websocket_client.dart';
import '../../services/discovery_service.dart';
import '../../services/emulator_config_service.dart';

// States
abstract class OperatorState {}

class OperatorInitial extends OperatorState {}

class OperatorDiscovering extends OperatorState {}

class OperatorConnecting extends OperatorState {
  final String url;
  OperatorConnecting(this.url);
}

class OperatorDiscovered extends OperatorState {
  final String url;
  final String host;
  final int port;
  OperatorDiscovered({required this.url, required this.host, required this.port});
}

class OperatorConnected extends OperatorState {
  final String url;
  final List<CameraNodeStatus> cameras;
  final ActiveSessionStatus? activeSession;

  OperatorConnected({
    required this.url,
    required this.cameras,
    this.activeSession,
  });

  OperatorConnected copyWith({
    String? url,
    List<CameraNodeStatus>? cameras,
    ActiveSessionStatus? activeSession,
    bool clearActiveSession = false,
  }) {
    return OperatorConnected(
      url: url ?? this.url,
      cameras: cameras ?? this.cameras,
      activeSession: clearActiveSession ? null : (activeSession ?? this.activeSession),
    );
  }
}

class OperatorError extends OperatorState {
  final String message;
  OperatorError(this.message);
}

// Sub-models
class CameraNodeStatus {
  final int cameraIndex;
  final String deviceName;
  final String state; // idle, capturing, uploading, uploaded, error
  final int batteryLevel;
  final double clockOffsetMs;
  final bool isReady;

  CameraNodeStatus({
    required this.cameraIndex,
    required this.deviceName,
    required this.state,
    required this.batteryLevel,
    required this.clockOffsetMs,
    required this.isReady,
  });

  factory CameraNodeStatus.fromJson(Map<String, dynamic> json) {
    return CameraNodeStatus(
      cameraIndex: json['camera_index'] as int? ?? 0,
      deviceName: json['device_name'] as String? ?? '',
      state: json['state'] as String? ?? 'idle',
      batteryLevel: json['battery_level'] as int? ?? 0,
      clockOffsetMs: (json['clock_offset_ms'] as num? ?? 0.0).toDouble(),
      isReady: json['is_ready'] as bool? ?? false,
    );
  }
}

class ActiveSessionStatus {
  final String sessionId;
  final String status;

  ActiveSessionStatus({
    required this.sessionId,
    required this.status,
  });

  factory ActiveSessionStatus.fromJson(Map<String, dynamic> json) {
    return ActiveSessionStatus(
      sessionId: json['session_id'] as String? ?? '',
      status: json['status'] as String? ?? 'idle',
    );
  }
}

// Events
abstract class OperatorEvent {}

class StartDiscoveryEvent extends OperatorEvent {}

class DiscoverServiceEvent extends OperatorEvent {
  final String host;
  final int port;
  DiscoverServiceEvent({required this.host, required this.port});
}

class ConnectManualEvent extends OperatorEvent {
  final String wsUrl;
  ConnectManualEvent(this.wsUrl);
}

class IgnoreDiscoveredEvent extends OperatorEvent {}

class DisconnectOperatorEvent extends OperatorEvent {}

class MessageReceivedOperatorEvent extends OperatorEvent {
  final Map<String, dynamic> message;
  MessageReceivedOperatorEvent(this.message);
}

class TriggerCaptureEvent extends OperatorEvent {}

class ClearActiveSessionEvent extends OperatorEvent {}

// Bloc Implementation
class OperatorBloc extends Bloc<OperatorEvent, OperatorState> {
  final WebSocketClient _wsClient;
  final DiscoveryService _discoveryService = DiscoveryService();
  StreamSubscription? _discoverySubscription;
  StreamSubscription? _wsSubscription;

  OperatorBloc(this._wsClient) : super(OperatorInitial()) {
    on<StartDiscoveryEvent>((event, emit) async {
      emit(OperatorDiscovering());
      _discoverySubscription?.cancel();
      _discoverySubscription = _discoveryService.discoveredServices.listen((service) {
        if (service.port != null) {
          String resolvedHost = service.host ?? '';
          final addresses = service.addresses;
          if (addresses != null && addresses.isNotEmpty) {
            for (final addr in addresses) {
              if (addr.type == InternetAddressType.IPv4) {
                resolvedHost = addr.address;
                break;
              }
            }
            if (resolvedHost == service.host && addresses.isNotEmpty) {
              resolvedHost = addresses.first.address;
            }
          }
          if (resolvedHost.isNotEmpty) {
            add(DiscoverServiceEvent(host: resolvedHost, port: service.port!));
          }
        }
      });
      await _discoveryService.start();
    });

    on<DiscoverServiceEvent>((event, emit) async {
      if (state is! OperatorDiscovering) return;
      
      String ip = event.host;
      if (RegExp(r'[a-zA-Z]').hasMatch(ip)) {
        try {
          final lookupResults = await InternetAddress.lookup(ip);
          if (lookupResults.isNotEmpty) {
            for (final addr in lookupResults) {
              if (addr.type == InternetAddressType.IPv4) {
                ip = addr.address;
                break;
              }
            }
            if (ip == event.host) {
              ip = lookupResults.first.address;
            }
          }
        } catch (_) {
          // Keep original hostname on lookup failure
        }
      }

      final wsUrl = 'ws://$ip:${event.port}/ws';
      emit(OperatorDiscovered(url: wsUrl, host: ip, port: event.port));
    });

    on<IgnoreDiscoveredEvent>((event, emit) {
      if (state is OperatorDiscovered) {
        emit(OperatorDiscovering());
      }
    });

    on<ConnectManualEvent>((event, emit) async {
      emit(OperatorConnecting(event.wsUrl));
      await _discoveryService.stop();
      _discoverySubscription?.cancel();
      EmulatorConfigService.configure(event.wsUrl);

      try {
        await _wsClient.connect(event.wsUrl);
        _wsSubscription?.cancel();
        _wsSubscription = _wsClient.messages.listen((msg) {
          add(MessageReceivedOperatorEvent(msg));
        });

        // Register as Operator
        _wsClient.send('operator_register', {
          'device_name': 'Operator Panel',
        });
      } catch (e) {
        emit(OperatorError('Connection to coordinator failed: ${e.toString()}'));
      }
    });

    on<MessageReceivedOperatorEvent>((event, emit) {
      final msg = event.message;
      final eventName = msg['event'] as String?;
      final data = msg['data'] as Map<String, dynamic>? ?? {};

      if (eventName == 'operator_registered') {
        if (state is OperatorConnecting) {
          final connState = state as OperatorConnecting;
          
          try {
            final uri = Uri.parse(connState.url);
            final host = uri.host;
            if (host.isNotEmpty) {
              SharedPreferences.getInstance().then((prefs) {
                prefs.setString('last_connected_ip', host);
              }).catchError((_) {});
            }
          } catch (_) {
            // Ignore parse errors if URL is not a valid URI format
          }

          emit(OperatorConnected(
            url: connState.url,
            cameras: [],
          ));
        }
      } else if (eventName == 'dashboard_sync') {
        if (state is OperatorConnected) {
          final s = state as OperatorConnected;
          final rawCams = data['cameras'] as List? ?? [];
          final cameras = rawCams.map((c) => CameraNodeStatus.fromJson(c as Map<String, dynamic>)).toList();
          
          ActiveSessionStatus? activeSession;
          if (data['active_session'] != null) {
            activeSession = ActiveSessionStatus.fromJson(data['active_session'] as Map<String, dynamic>);
          }

          emit(s.copyWith(
            cameras: cameras,
            activeSession: activeSession,
            clearActiveSession: activeSession == null,
          ));
        }
      } else if (eventName == 'disconnected') {
        emit(OperatorInitial());
      } else if (eventName == 'error') {
        emit(OperatorError(msg['error'] as String? ?? 'WebSocket error'));
      }
    });

    on<TriggerCaptureEvent>((event, emit) {
      if (state is OperatorConnected) {
        _wsClient.send('operator_capture_trigger', {});
      }
    });

    on<ClearActiveSessionEvent>((event, emit) {
      if (state is OperatorConnected) {
        _wsClient.send('operator_clear_session', {});
      }
    });

    on<DisconnectOperatorEvent>((event, emit) async {
      _discoverySubscription?.cancel();
      await _discoveryService.stop();
      _wsSubscription?.cancel();
      await _wsClient.disconnect();
      emit(OperatorInitial());
    });
  }

  @override
  Future<void> close() {
    _discoverySubscription?.cancel();
    _discoveryService.dispose();
    _wsSubscription?.cancel();
    return super.close();
  }
}
