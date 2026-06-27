# WebSocket Contract: Coordinator <-> Client Nodes

The WebSocket connection operates locally over TCP (default port `8080`). All payloads are serialized as JSON.

---

## 1. Client Registration (Handshake)

Sent by the Flutter client node upon scanning the QR code and establishing a WebSocket connection.

### Request Payload (Client -> Coordinator)
```json
{
  "event": "client_register",
  "data": {
    "camera_index": 1,
    "device_name": "iPhone 15 Pro"
  }
}
```

### Response Payload (Coordinator -> Client)
```json
{
  "event": "client_registered",
  "data": {
    "camera_index": 1,
    "status": "ready"
  }
}
```

---

## 2. Synchronization Heartbeat / Latency Ping

Sent periodically by the Go coordinator to monitor link health and offset drift.

### Request Payload (Coordinator -> Client)
```json
{
  "event": "ping",
  "data": {
    "coordinator_timestamp_ms": 1782349000000
  }
}
```

### Response Payload (Client -> Coordinator)
```json
{
  "event": "pong",
  "data": {
    "coordinator_timestamp_ms": 1782349000000,
    "client_timestamp_ms": 1782349000050
  }
}
```

---

## 3. Capture Trigger

Broadcasted by the Go coordinator to all connected clients simultaneously to schedule a capture session and inform the clients of the total camera count.

### Broadcast Payload (Coordinator -> Client)
```json
{
  "event": "capture_trigger",
  "data": {
    "session_id": "session-9b1deb4d-3b7d-4bad",
    "trigger_epoch_ms": 1782349010500,
    "expected_frames": 5
  }
}
```

---

## 4. Capture & Upload Progress Update

Sent by Flutter clients to notify the coordinator of their progress through the capture and direct-to-cloud upload lifecycle.

### Status Update Payload (Client -> Coordinator)
```json
{
  "event": "status_update",
  "data": {
    "session_id": "session-9b1deb4d-3b7d-4bad",
    "camera_index": 1,
    "status": "capturing" | "uploading" | "uploaded" | "failed",
    "battery_level": 88,
    "error_message": null
  }
}
```

---

## 5. Operator Registration (Handshake)

Sent by the Flutter Operator App upon establishing a WebSocket connection.

### Request Payload (Operator -> Coordinator)
```json
{
  "event": "operator_register",
  "data": {
    "device_name": "iPad Pro"
  }
}
```

### Response Payload (Coordinator -> Operator)
```json
{
  "event": "operator_registered",
  "data": {
    "status": "ready"
  }
}
```

---

## 6. Remote Capture Trigger

Sent by the Operator App to request the coordinator to start a capture session.

### Request Payload (Operator -> Coordinator)
```json
{
  "event": "operator_capture_trigger",
  "data": {}
}
```

---

## 7. Operator Dashboard Sync

Pushed in real-time by the Go coordinator to all registered Operator connections whenever any node registry state changes (pairing, disconnects, battery updates, NTP offsets, or capture state transitions).

### Push Payload (Coordinator -> Operator)
```json
{
  "event": "dashboard_sync",
  "data": {
    "cameras": [
      {
        "camera_index": 1,
        "device_name": "iPhone 15 Pro",
        "state": "idle" | "capturing" | "uploading" | "uploaded" | "failed",
        "battery_level": 85,
        "clock_offset_ms": -0.45,
        "is_ready": true
      }
    ],
    "active_session": {
      "session_id": "session-9b1deb4d-3b7d-4bad",
      "status": "idle" | "triggered" | "done" | "failed"
    }
  }
}
```
