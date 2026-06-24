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

Broadcasted by the Go coordinator to all 5 connected clients simultaneously to schedule a capture session.

### Broadcast Payload (Coordinator -> Client)
```json
{
  "event": "capture_trigger",
  "data": {
    "session_id": "session-9b1deb4d-3b7d-4bad",
    "trigger_epoch_ms": 1782349010500
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
    "error_message": null
  }
}
```
