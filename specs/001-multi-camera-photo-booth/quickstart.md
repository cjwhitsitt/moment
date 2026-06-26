# Quickstart Validation Guide: Distributed Multi-Camera Photo Booth

This guide outlines the steps required to verify that the photo booth system functions correctly from local device pairing to cloud stitching.

## Prerequisites

- **Go**: Version 1.21+ installed on the coordinator host (macOS/Raspberry Pi)
- **Flutter**: Flutter SDK installed for client testing
- **Firebase CLI**: Installed and authenticated to the target Firebase project
- **Local Network**: All devices (coordinator and smartphones) must be on the same local Wi-Fi subnet with UDP port 123 (NTP) and TCP port 8080 (WebSockets) open.

---

## Scenario 1: Setup & Connection Verification

Verify that client devices can pair with the local coordinator and synchronize system clocks.

### Steps
1. Start the local coordinator server:
   ```bash
   go run cmd/coordinator/main.go --port=8080 --ntp-port=123
   ```
2. Retrieve the pairing QR code from the coordinator interface or console output.
3. Open the Flutter client app on a test device, select "Scan Coordinator QR", and scan the QR code.
4. Verify the client console displays a successful registration handshake.

### Expected Outcomes
- Coordinator terminal log shows:
  ```text
  [INFO] Registered Client Node 1 from IP 192.168.1.50
  ```
- Client app shows the active connection indicator and displays the calculated NTP clock offset (e.g., `Clock Offset: -4ms`).

---

## Scenario 2: Synchronized Capture Trigger

Verify that a capture signal is received and executed simultaneously across client nodes.

### Steps
1. Pair all N client smartphones (where $3 \le N \le 10$). Ensure the coordinator reports a `Ready to Shoot` state.
2. Click the "Capture" trigger button on the coordinator dashboard.
3. Observe the camera shutters firing on all N smartphones.

### Expected Outcomes
- Coordinator logs show a broadcast trigger payload dispatched to all connected clients:
  ```text
  [INFO] Triggering Capture Session: session-9b1deb4d
  ```
- All N smartphones fire their cameras at the identical future epoch timestamp designated in the payload.

---

## Scenario 3: Cloud Stitching & Display Verification

Verify that uploaded frames are stitched into a looping ping-pong GIF and shared.

### Steps
1. Let the smartphones complete uploading their frames directly to Firebase Storage.
2. Verify the Firestore document `sessions/session-9b1deb4d` updates to `processing` and then `completed`.
3. Check the coordinator screen for the generated sharing QR code.
4. Scan the sharing QR code with a smartphone.

### Expected Outcomes
- Firestore session document is updated with:
  ```json
  {
    "status": "completed",
    "gifUrl": "https://firebasestorage.googleapis.com/.../session-9b1deb4d.gif"
  }
  ```
- The phone browser navigates to the URL and plays a smooth, looping ping-pong GIF animation sequenced as: `1 → 2 → ... → N → N-1 → ... → 2` (skipping the duplicate end-frame to prevent lag).
