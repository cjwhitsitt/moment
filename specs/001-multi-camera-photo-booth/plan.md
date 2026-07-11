# Implementation Plan: Distributed Multi-Camera Photo Booth

**Branch**: `001-multi-camera-photo-booth` | **Date**: 2026-06-23 | **Spec**: [spec.md](file:///Users/jay/Developer/Hobby/moment/specs/001-multi-camera-photo-booth/spec.md)

**Input**: Feature specification from `specs/001-multi-camera-photo-booth/spec.md`

## Summary

This feature implements a distributed multi-camera photo booth system designed for ultra-low latency capture synchronization. The local system consists of a Go coordinator running an NTP server and a WebSockets server to pair and trigger a variable number of smartphone client nodes (between 3 and 10) (Flutter/Dart). The cloud system leverages Firebase Storage and Firestore to orchestrate image uploads, and a Node.js Cloud Function running FFmpeg to dynamically stitch the images into a seamless ping-pong looping GIF based on the active node count. A QR code displayed on the coordinator allows guests to view the final GIF instantly.

## Technical Context

**Language/Version**: Go 1.21+ (Coordinator), Dart 3.x / Flutter 3.x (Clients), Node.js 18+ / TypeScript (Cloud Functions)

**Primary Dependencies**:
- `github.com/gorilla/websocket` (Go WebSocket server)
- `github.com/hashicorp/mdns` (Go mDNS service registration)
- `ntp` (Dart package for NTP sync)
- `nsd` (Dart package for mDNS client-side discovery)
- `flutter_bloc` (Dart state management)
- `firebase_core`, `firebase_storage` (Dart Firebase SDK)
- `firebase-functions`, `firebase-admin` (Node.js SDK)
- `resend` (Node.js email delivery SDK)
- `fluent-ffmpeg` (Node.js FFmpeg wrapper)
- `wakelock_plus` (Dart package for preventing screen sleep)
- `shared_preferences` (Dart package for local caching persistence)

**Storage**: Firebase Cloud Storage (raw captures and stitched GIF), Firebase Firestore (session metadata and real-time status orchestration)

**Testing**: Go unit/benchmark tests, Flutter `bloc_test` suites, Firebase Emulator suite for functions

**Target Platform**: macOS (`darwin/amd64`, `darwin/arm64`) & Raspberry Pi (`linux/arm64`) for coordinator; iOS/Android for clients

**Project Type**: Distributed edge & cloud application

**Performance Goals**: Synchronization trigger skew <5ms across all connected clients; end-to-end capture-to-display time <10 seconds.

**Constraints**: Devices must be connected to the same local Wi-Fi subnet; camera startup and shutter lag must be minimized on client hardware. The Flutter client application must prevent the device from sleeping by enabling a wake lock while registered/paired. A comprehensive operator setup README must be provided in the root directory. The iOS client application minimum deployment target must be set to 15.0 to support Firebase Swift Package Manager dependencies. Platform-specific FirebaseOptions must be configured programmatically to prevent iOS SDK configuration exceptions, including using a valid 39-character apiKey starting with "A". iOS Info.plist must contain NSCameraUsageDescription, NSMicrophoneUsageDescription, NSLocalNetworkUsageDescription, and NSBonjourServices keys to prevent OS runtime termination and network sandbox blocks; the Flutter client application must implement dynamic camera lifecycle management to prevent camera resource lock conflicts between the QR code scanner (MobileScanner) and camera preview (CameraController) on Android; the Android AndroidManifest.xml must permit cleartext traffic and request the internet permission to support local network connection to the Firebase storage and firestore emulators; Node.js Cloud Functions must target the Node.js 20 runtime environment (replacing the decommissioned Node.js 18), and utilize modular subpath imports (such as 'firebase-admin/firestore' for FieldValue) to prevent legacy global namespace resolution errors under firebase-admin v12+; the Flutter client application and Firebase Cloud Functions must use a consistent storage bucket domain (specifically 'moment-aad8b.firebasestorage.app') to prevent file resolution mismatches during stitching; the Node.js Cloud Functions must depend on '@ffmpeg-installer/ffmpeg' to provide a precompiled self-contained FFmpeg binary for cross-platform portability without requiring a system-level binary installation; the Node.js Cloud Functions must construct direct unauthenticated local download URLs when running in the emulator (detected via FIREBASE_STORAGE_EMULATOR_HOST) to avoid cryptographic signing errors due to mock credentials; the Node.js Cloud Functions must specify an explicit -start_number 0 in the FFmpeg demuxer configuration to guarantee that the frame sequence starts at 0 and doesn't skip the first frame on platforms defaulting to 1; the Node.js Cloud Functions must disable filter reinitialization via -reinit_filter 0, and pre-scale all individual input frames to a uniform 800x600 resolution (using scale and pad) prior to combining them to prevent FFmpeg demuxer decoding artifacts (green lines/blocks) when camera nodes upload captures at varying native resolutions. The system supports pairing between 3 and 10 devices, and trigger commands must enforce this minimum/maximum check. The Go coordinator must prioritize querying active network interfaces (InterfaceAddrs) over loopback hostname lookup to advertise its actual non-loopback LAN IP address over mDNS, publishing its WebSocket service on port 8080 using service type `_moment-coord._tcp` and service name `moment-coordinator`. The Flutter client application must launch directly into Camera Node setup by default, and provide a navigation action button to switch to Operator Mode. The Operator Control Panel must automatically initiate local mDNS auto-discovery on load, extract the resolved numeric IPv4 address to bypass local .local hostname resolution constraints, present manual IP inputs directly on the scanning screen, and require confirmation from the operator before connecting to any resolved coordinator service. Captured JPEGs must be physically rotated on the client device using package:image before uploading to Storage to bake in the device orientation and prevent unrotated landscape output in the final stitched GIF. The Operator App must switch from the utilitarian dashboard to a full-screen, customer-friendly GIF preview and share view when stitching is complete, showing the stitched preview GIF at full-width as the primary focal element, arranging all sharing options (including guest download QR code and email fields) underneath it, and providing a "Back to Dashboard" reset control. All outgoing email shares must be triggered via an HTTPS Callable Cloud Function calling the Resend API, using an API key stored in Firebase Functions environment config (`resend.key`).







## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Principle I: Ultra-Low Latency Capture Sync (<5ms Target)**: PASSED. By running a local NTP server on the Go coordinator, clients compute clock offsets to target exact future epoch timestamps, bypassing WebSocket network transmission jitter.
- **Principle II: Go-Based Coordinator compiled for macOS & Raspberry Pi**: PASSED. The coordinator is built in Go, targeting macOS/Raspberry Pi (arm64).
- **Principle III: Flutter/Dart Clients with Bloc/Cubit**: PASSED. Client nodes use Flutter and Bloc/Cubit state management.
- **Principle IV: Firebase Cloud Stitching Infrastructure**: PASSED. The cloud backend is built on Firebase Storage, Firestore, and Node.js Cloud Functions.
- **Principle V: Serverless FFmpeg Video Processing**: PASSED. Cloud functions execute FFmpeg command lines to process and stitch raw frames into the ping-pong GIF.

## Project Structure

### Documentation

```text
README.md                # Operator setup, dev/build details, and network troubleshooting
specs/001-multi-camera-photo-booth/
├── plan.md              # This file
├── research.md          # Synchronization and upload strategy
├── data-model.md        # Firestore document schemas and local structs
├── quickstart.md        # Step-by-step verification guide
├── contracts/
│   └── websocket.md     # WebSocket contract definition
└── tasks.md             # Implementation tasks checklist (Phase 2)
```

### Source Code

```text
cmd/
└── coordinator/         # Go coordinator main entrypoint
pkg/
├── ntp/                 # Local NTP server implementation
├── ws/                  # WebSocket server and connection manager
├── mdns/                # mDNS advertising service
└── domain/              # Shared Go domain types
clients/
└── mobile/              # Flutter client app
    ├── install-android.sh # Script to build and deploy to all connected Android devices in parallel
    ├── install-ios.sh     # Script to build and deploy to all connected iOS devices in parallel
    ├── lib/
    │   ├── bloc/        # Bloc/Cubit state files (Camera and Operator)
    │   ├── services/    # NTP sync, WebSocket, mDNS Discovery, and Firebase upload services
    │   ├── ui/          # UI pages (Selection, Camera Node, Operator Panel)
    │   └── main.dart    # Main Flutter entrypoint
    └── test/            # Flutter widget, bloc, and unit tests
functions/               # Firebase Cloud Functions (TypeScript)
    ├── src/
    │   ├── index.ts     # Main Cloud Function hooks and Callable email endpoint
    │   ├── stitch.ts    # FFmpeg processing and sequence builder
    │   └── email.ts     # Resend client integration
    ├── package.json
    └── tsconfig.json
```

**Structure Decision**: A multi-component repository. `cmd/` and `pkg/` host the Go coordinator backend, `clients/mobile/` hosts the Flutter/Dart mobile app, and `functions/` hosts the Firebase Cloud Functions node project.

## Verification Plan

### Automated Tests
- **Go NTP Server Unit Tests**:
  ```bash
  go test -v ./pkg/ntp/...
  ```
- **Flutter State Tests**:
  ```bash
  cd clients/mobile && flutter test
  ```
- **Parallel Multi-Device Deployment**:
  ```bash
  cd clients/mobile
  chmod +x install-android.sh && ./install-android.sh
  chmod +x install-ios.sh && ./install-ios.sh
  ```
- **Firebase Functions Tests**:
  ```bash
  cd functions && npm run test
  ```

### Manual Verification
1. Start the Go coordinator server locally.
2. Launch the mobile application on a device, select **Operator Mode**, and confirm it auto-discovers the Go coordinator via mDNS and establishes connection.
3. Launch $N$ instances (where $3 \le N \le 10$) of the mobile app in **Camera Mode**. Scan the pairing QR code displayed on the Operator device to establish connections.
4. Verify that the Operator App dashboard displays all paired camera nodes with their battery levels, calculated NTP offsets (<1ms target offset), and states.
5. Tap **Capture** on the Operator App dashboard to trigger the synchronized capture session.
6. Verify that raw images are captured and uploaded directly to the Firebase Cloud Storage emulator bucket.
7. Verify that the Node.js function processes the $N$ frames using FFmpeg, sequences them in a looping ping-pong GIF (`1 -> 2 -> ... -> N -> N-1 -> ... -> 2`), and updates the Firestore document status to `completed`.
8. Verify that the Operator App displays the guest sharing QR code and the stitched GIF animation preview once stitching finishes.
9. Enter a test email address on the Operator App, tap submit, and verify that the Resend Cloud Function sends the email containing the stitched GIF. Check the Resend dashboard or mail logs to verify.
10. Attempt to type alphabetic characters into the manual IP input field on the Operator Panel. Verify they are rejected.
11. Complete a manual connection to the coordinator successfully, force close the app, relaunch it, and verify the manual IP field auto-fills with that last connected IP address.
12. Initialize Camera Mode on a node, verify the live preview matches actual target shapes without distortion, and confirm a central target alignment focus icon overlays the center of the camera box.
13. Run direct curl or console checks on Firebase Firestore and Storage rules to verify that unauthorized queries on sessions list, session deletes, and raw captures are denied, but reads of stitched GIFs succeed.
14. Select an arbitrary index in the Camera Node configuration dropdown, force close and relaunch the app, and verify the dropdown defaults to the last selected index.
15. Launch the app from a clean state, confirm it opens on the Camera Node setup screen, tap the switch to operator button, verify it pushes the Operator panel, and tap back to return.
16. Complete a capture session, verify the Operator Panel switches to a full-screen sharing overlay, tap "Back to Dashboard", and confirm it returns to the status grid.
17. Complete a capture session, verify the preview GIF spans the full width of the sharing container, and verify the QR code and email form are placed underneath it.
18. Launch the app in Operator Mode. Verify discovery starts automatically, check that manual IP fields are visible on the scanning view, start the coordinator, confirm the connect approval prompt appears, tap cancel to stay on scanning, and then approve connection on next detection.
19. Hold a camera node in portrait mode, trigger capture, and verify that the uploaded JPEG file has portrait dimensions (height > width) and the final stitched GIF is correctly oriented.
