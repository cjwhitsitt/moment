# Implementation Plan: Distributed Multi-Camera Photo Booth

**Branch**: `001-multi-camera-photo-booth` | **Date**: 2026-06-23 | **Spec**: [spec.md](file:///Users/jay/Developer/Hobby/moment/specs/001-multi-camera-photo-booth/spec.md)

**Input**: Feature specification from `specs/001-multi-camera-photo-booth/spec.md`

## Summary

This feature implements a distributed multi-camera photo booth system designed for ultra-low latency capture synchronization. The local system consists of a Go coordinator running an NTP server and a WebSockets server to pair and trigger 5 smartphone client nodes (Flutter/Dart). The cloud system leverages Firebase Storage and Firestore to orchestrate image uploads, and a Node.js Cloud Function running FFmpeg to stitch the images into a seamless ping-pong looping GIF. A QR code displayed on the coordinator allows guests to view the final GIF instantly.

## Technical Context

**Language/Version**: Go 1.21+ (Coordinator), Dart 3.x / Flutter 3.x (Clients), Node.js 18+ / TypeScript (Cloud Functions)

**Primary Dependencies**:
- `github.com/gorilla/websocket` (Go WebSocket server)
- `ntp` (Dart package for NTP sync)
- `flutter_bloc` (Dart state management)
- `firebase_core`, `firebase_storage` (Dart Firebase SDK)
- `firebase-functions`, `firebase-admin` (Node.js SDK)
- `fluent-ffmpeg` (Node.js FFmpeg wrapper)

**Storage**: Firebase Cloud Storage (raw captures and stitched GIF), Firebase Firestore (session metadata and real-time status orchestration)

**Testing**: Go unit/benchmark tests, Flutter `bloc_test` suites, Firebase Emulator suite for functions

**Target Platform**: macOS (`darwin/amd64`, `darwin/arm64`) & Raspberry Pi (`linux/arm64`) for coordinator; iOS/Android for clients

**Project Type**: Distributed edge & cloud application

**Performance Goals**: Synchronization trigger skew <5ms across all 5 clients; end-to-end capture-to-display time <10 seconds.

**Constraints**: Devices must be connected to the same local Wi-Fi subnet; camera startup and shutter lag must be minimized on client hardware.

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
└── domain/              # Shared Go domain types
clients/
└── mobile/              # Flutter client app
    ├── lib/
    │   ├── bloc/        # Bloc/Cubit state files
    │   ├── services/    # NTP sync, WebSocket client, and Firebase upload services
    │   └── main.dart    # Main Flutter entrypoint
    └── test/            # Flutter widget and unit tests
functions/               # Firebase Cloud Functions (TypeScript)
    ├── src/
    │   ├── index.ts     # Main Cloud Function hooks
    │   └── stitch.ts    # FFmpeg processing and sequence builder
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
- **Firebase Functions Tests**:
  ```bash
  cd functions && npm run test
  ```

### Manual Verification
1. Start the Go coordinator server locally.
2. Launch 5 instances of the mobile application (or mock clients). Scan the pairing QR code to establish WebSocket connections.
3. Confirm NTP synchronization succeeds and offset is calculated (<1ms target offset).
4. Trigger a capture session from the coordinator dashboard.
5. Verify raw images are uploaded directly to the Firebase Cloud Storage emulator bucket.
6. Verify the Node.js function processes the 5 frames using FFmpeg, sequences them as `1-2-3-4-5-4-3-2` and saves the looping `.gif`.
7. Verify the coordinator displays the final guest QR code, which resolves to the stitched GIF.
