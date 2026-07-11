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

---

## Scenario 9: Full-Screen Sharing View and Reset Verification

Verify that the Operator App switches to full-screen sharing when stitching completes and permits dashboard return.

### Steps
1. Connect 3 Camera Nodes and 1 Operator Panel.
2. Trigger a capture session and wait for stitching to complete.
3. Verify that once the GIF is stitched, the Operator App immediately hides the status grid and pairing QR code, displaying only the GIF preview, guest QR code, and email input.
4. Tap the **Back to Dashboard** action button.
5. Verify that the Operator App returns to the active camera node status grid and trigger capture cockpit view.

### Expected Outcomes
- The status dashboard is completely replaced by the customer-friendly share cockpit when the session completes.
- Pushing the close button resets the session state and returns to the active cockpit.

---

## Scenario 10: Full-Width Preview Layout Verification

Verify that the completed sharing view displays the preview image full-width and share details below it.

### Steps
1. Complete a capture and wait for stitching to complete.
2. Verify that the GIF preview spans the entire width of the sharing layout and is the main focal element.
3. Scroll down (or inspect below) and confirm that the guest QR code scanner card and email delivery inputs are positioned underneath the preview.

### Expected Outcomes
- The preview GIF is shown at full-width as the primary asset.
- All sharing tools are arranged underneath the preview container.

---

## Scenario 11: mDNS Auto-Start, Manual Entry & Connection Confirmation Verification

Verify that entering Operator Mode triggers scanning automatically, displays manual IP fields, and prompts before connecting.

### Steps
1. Launch the application and select **Switch to Operator Mode**.
2. Verify that the screen immediately displays **Searching for Coordinator...** with a spinner (no manual start button required).
3. Verify that the manual IP entry input field and connect button are visible on this scanning screen.
4. Start the Go coordinator.
5. Verify that once the service is resolved, the app transitions to the **Coordinator Found** screen.
6. Confirm the screen displays the discovered coordinator's address and prompts: **Connect to Discovered Coordinator?**.
7. Tap **Cancel / Reject**. Verify you return to the scanning screen.
8. Once resolved again, tap **Connect / Approve**. Verify you successfully connect and register to the dashboard view.

### Expected Outcomes
- Discovery starts automatically.
- Manual IP connection remains possible during background scans.
- A confirmation dialog is required to complete auto-discovered connections.

---

## Scenario 12: Client-Side Image Orientation Baking Verification

Verify that photos captured in portrait mode are physically rotated and uploaded in portrait, resulting in correctly oriented frames in the stitched GIF.

### Steps
1. Connect a camera node device in portrait mode.
2. Trigger a capture session.
3. Check the Firestore console or the Cloud Storage directory for the raw capture of that camera node (e.g. `raw/{sessionId}/cam1.jpg`).
4. Verify that the physical dimensions of the JPEG file are portrait (e.g. height is greater than width, with no EXIF rotation needed).
5. Once stitching is complete, verify that the preview GIF displays the frame correctly oriented (not rotated sideways).

### Expected Outcomes
- The raw uploaded JPEGs are physically oriented matching the device's physical orientation at capture.
- Stitched GIF animations preserve correct orientation.

---

## Scenario 16: Single-Screen Operator Post-Capture Sharing View Verification

Verify that all widgets fit on a single screen without scrolling for both landscape and portrait captures.

### Steps
1. Connect camera nodes and trigger a capture session.
2. Once stitching is complete, verify that the Operator screen switches to the sharing view.
3. Check that the GIF, QR code, and email fields are all completely visible on the screen.
4. Verify that you cannot scroll the screen (the layout is locked and fits perfectly within the device height).
5. Confirm this layout budget holds for both landscape and portrait sessions.

### Expected Outcomes
- The entire sharing view fits on one screen with no scrolling required.

---

## Scenario 17: Tap to Zoom Verification

Verify that tapping the preview GIF or guest share QR code opens a fullscreen modal, and tapping anywhere dismisses it.

### Steps
1. Connect camera nodes and trigger a capture session.
2. Once stitching is complete, tap on the looping preview GIF.
3. Verify that a fullscreen dialog opens showing the GIF scaled to fit.
4. Tap anywhere on the dialog overlay. Verify that it closes immediately.
5. Tap on the guest sharing QR code.
6. Verify that the fullscreen dialog opens showing a large zoomed-in QR code.
7. Tap anywhere to close the overlay.

### Expected Outcomes
- Tapping assets zooms them in a dismissible fullscreen dialog.

---

## Scenario 18: Operator Pairing QR Code Modal Verification

Verify that the pairing QR code is hidden by default, shown via the Add Node button, and auto-opened if empty.

### Steps
1. Launch the Operator App and connect to a fresh coordinator session (no nodes connected yet).
2. Verify that the pairing QR code dialog opens automatically on screen entry.
3. Close the dialog. Verify that the QR code is not visible on the main cockpit.
4. Tap the "+" (Add Node) action button in the cockpit header.
5. Verify that the pairing QR code dialog pops open again.

### Expected Outcomes
- Pairing QR code auto-opens when empty and opens manually on tap.

---

## Scenario 19: Responsive Camera Node Grid Verification

Verify that camera status cards dynamically adjust their column count.

### Steps
1. Connect 4 camera nodes to the coordinator.
2. Rotate the Operator device to portrait. Verify that the grid renders as 2 columns of status cards.
3. Rotate the Operator device to landscape. Verify that the grid automatically expands to 3 or 4 columns depending on screen width.

### Expected Outcomes
- Camera cards adapt dynamically to available viewport width.

---

## Scenario 20: Operator Email Share Modal Verification

Verify that email sharing is triggered via the side-by-side "Email" button and shows success/error status in the modal overlay.

### Steps
1. Complete a capture session to load the post-capture sharing view.
2. Verify that the view has a "Share to" panel with the QR code on the left and an "Email" button on the right.
3. Tap the "Email" button. Verify that a modal dialog overlay opens containing an email text input field.
4. Enter a test email and tap "Send". Verify that a loading spinner is shown, followed by a success message in the dialog.
5. Close the dialog. Tap "Email" again. Verify that the input field and status are reset.

### Expected Outcomes
- Email sharing is moved to a clean, dismissible dialog overlay.

---

## Scenario 13: Camera Node Landscape Header Hiding Verification

Verify that rotating the Camera Node device to landscape hides the AppBar.

### Steps
1. Open the Camera Node screen in portrait mode. Verify that the **Moment Camera Node** AppBar is visible.
2. Rotate the device (or simulate rotation) to landscape mode.
3. Verify that the **Moment Camera Node** AppBar disappears.
4. Rotate back to portrait mode. Verify that the AppBar is visible again.

### Expected Outcomes
- AppBar is dynamically shown in portrait and hidden in landscape.

---

## Scenario 14: Guest Download Landing Page Verification

Verify that scanning the guest download QR code opens the landing page and downloads the correct GIF.

### Steps
1. Complete a capture session and wait for stitching to complete.
2. Scan the guest download QR code shown in the Operator panel using a mobile phone.
3. Verify that the URL is structured correctly (e.g. starts with `http://<coordinator-ip>:5000` or `https://moment-aad8b.web.app`).
4. Confirm the web page opens and displays the GIF preview at full scale.
5. Tap the **Download GIF** button. Verify that the file downloads directly to the device.

### Expected Outcomes
- The QR code redirects to the hosting landing page.
- The landing page displays the preview and successfully triggers direct file download.

---

## Scenario 15: Forced 16:9 Aspect Ratio Verification

Verify that captured images and resulting stitched GIFs are forced to 16:9.

### Steps
1. Open the Camera Node screen. Verify that the full camera preview viewport is visible with a translucent gray overlay shade framing the active 16:9 (or 9:16) region.
2. Trigger a capture. Download the raw uploaded JPEG from Storage.
3. Verify that the file's resolution matches the raw, uncropped format (e.g. native 4:3 camera resolution like `1440x1080` or similar).
4. Once stitched, verify that the preview GIF in the Operator dashboard has a 16:9 aspect ratio and does not contain any letterbox black padding.

### Expected Outcomes
- Camera viewfinder renders full viewport with a translucent crop guide.
- Stitched GIF outputs are cropped to 16:9/9:16 on the backend without any letterboxing.
