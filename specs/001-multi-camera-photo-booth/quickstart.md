# Quickstart Validation Guide: Distributed Multi-Camera Photo Booth

This guide outlines the steps required to verify that the photo booth system functions correctly from local device pairing to cloud stitching and email delivery.

## Prerequisites

- **Go**: Version 1.21+ installed on the coordinator host (macOS/Raspberry Pi)
- **Flutter**: Flutter SDK installed for client and operator testing
- **Firebase CLI**: Installed and authenticated to the target Firebase project
- **Resend**: API Key configured in Firebase Functions environment variables
- **Local Network**: All devices (coordinator, operator, and smartphones) must be on the same local Wi-Fi subnet with UDP port 1230 (NTP) and TCP port 8080 (WebSockets) open.

---

## Scenario 1: Setup, Discovery & Connection Verification

Verify that the Operator App can discover the headless coordinator via mDNS and cameras can pair with the system.

### Steps
1. Start the headless coordinator server:
   ```bash
   go run cmd/coordinator/main.go --port=8080 --ntp-port=1230
   ```
2. Open the Flutter app on the Operator device and select **Operator Mode**.
3. Verify that the Operator App auto-discovers the coordinator (via mDNS) and displays the pairing QR code.
4. Open the Flutter app on a camera node smartphone, select **Camera Mode**, and scan the QR code off the Operator App screen.
5. Repeat for N cameras (where $3 \le N \le 10$).

### Expected Outcomes
- Coordinator terminal log shows:
   ```text
   [INFO] Operator registered: iPad Pro
   [INFO] Camera node 1 registered: iPhone 15 Pro (IP: 192.168.1.50)
   ```
- The Operator App dashboard displays all N connected camera nodes, showing their unique indices, battery levels, NTP clock offsets (<1ms target), and status (Idle).

---

## Scenario 2: Synchronized Capture Trigger

Verify that a capture signal is triggered remotely from the Operator App and executed simultaneously across client nodes.

### Steps
1. Confirm the Operator App dashboard displays a `Ready to Shoot` state (meaning between 3 and 10 camera nodes are connected).
2. Tap the **Capture** trigger button on the Operator App dashboard.
3. Observe the camera shutters firing on all N smartphones.

### Expected Outcomes
- All N smartphones fire their cameras at the identical future epoch timestamp designated by the coordinator.
- The Operator App dashboard updates the camera status indicators in real-time from `Idle` -> `Capturing` -> `Uploading` -> `Uploaded`.

---

## Scenario 3: Cloud Stitching & Email Delivery

Verify that uploaded frames are stitched into a looping ping-pong GIF and shared/delivered via email.

### Steps
1. Allow the smartphones to finish uploading their frames directly to Firebase Storage.
2. Verify the Operator App sharing screen displays the guest QR code and the stitched GIF animation preview once stitching is complete.
3. Scan the sharing QR code with a guest smartphone.
4. On the Operator App, enter a test email address and submit.

### Expected Outcomes
- Firestore session document is updated to `completed` with the `gifUrl`.
- The Operator App displays the guest QR code, renders the looping stitched GIF preview, and opens the email delivery form.
- The Resend cloud function dispatches the email. Check the inbox (or Resend dashboard logs) for the email containing the stitched GIF.
- A new share document is created under `sessions/{sessionId}/shares` with status `sent`.

---

## Scenario 4: Operator Connection Input Filtering & Persistence

Verify that the Operator Panel restricts manual IP text input and caches the last connected IP.

### Steps
1. On the Operator Page initial view, attempt to type letters (e.g. `abc`) into the manual IP input field. Verify they are rejected.
2. Enter a valid coordinator IP address, tap **Connect Manually**, and complete pairing successfully.
3. Force close the Flutter application.
4. Relaunch the application, open the Operator Panel, and inspect the manual IP text input field.

### Expected Outcomes
- The manual IP input field only accepts digit characters and dots (`0-9` and `.`).
- Upon relaunching, the manual IP input field is pre-populated with the exact IP address used in step 2.

---

## Scenario 5: Camera Node Preview Aspect Ratio & Alignment Target Verification

Verify that the Camera Node preview displays without stretching and includes a target crosshair overlay.

### Steps
1. Connect a camera node device to the coordinator and enter **Camera Mode**.
2. Once the camera hardware initializes, inspect the live video preview area.
3. Hold the phone in both portrait and landscape orientation.
4. Inspect the center of the video preview.

### Expected Outcomes
- The live feed is displayed cleanly without horizontal or vertical stretching.
- A target alignment crosshair (target focus icon) is displayed in the absolute center of the camera preview frame.

---

## Scenario 6: Security Rules Integrity Verification

Verify that Firestore and Firebase Storage security rules block public access to raw data but allow public access to stitched animations.

### Steps
1. Attempt to fetch all session documents from Firestore without credentials (e.g. list operation). Verify it is rejected.
2. Attempt to download a raw capture file from the Storage `captures/` path without credentials. Verify it is rejected.
3. Attempt to download a stitched GIF file from the Storage `stitched/` path without credentials. Verify it succeeds.

### Expected Outcomes
- Firestore list operations and direct deletes are rejected (returns permission denied).
- Storage reads from the `captures/` path are rejected (returns permission denied).
- Storage reads from the `stitched/` path succeed, allowing image download.

---

## Scenario 7: Camera Node Position Index Persistence Verification

Verify that the Camera Node setup screen retains the last chosen index.

### Steps
1. Launch the application and select **Camera Array Node**.
2. Open the camera position dropdown and select `Camera Node 4`.
3. Force close the application.
4. Relaunch the application and open the Camera Node configuration screen.

### Expected Outcomes
- The dropdown defaults to `Camera Node 4` on relaunch.

---

## Scenario 8: Default Camera Node Launch and Operator Navigation Verification

Verify that the application launches into Camera Node setup by default and permits transition to Operator Mode.

### Steps
1. Launch the application from a clean state.
2. Verify that the screen presented is the **Configure Camera Node** screen.
3. Locate and tap the **Switch to Operator Mode** action button.
4. Verify that the **Operator Control Panel** (IP connection screen) is displayed.
5. Tap the back navigation arrow.
6. Verify that you return to the **Configure Camera Node** screen.

### Expected Outcomes
- The app bypasses the Selection Page and opens the Camera Node view on launch.
- Pushing the Operator action button correctly transitions to the Operator connection page.
- Tapping back returns the user to the Camera Node view.
