# Tasks: Distributed Multi-Camera Photo Booth

**Input**: Design documents from `specs/001-multi-camera-photo-booth/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are optional and implemented during feature validation.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Initialize Go module at repository root in go.mod
- [x] T002 Initialize Flutter client app project structure in clients/mobile/
- [x] T003 Initialize Node.js Firebase Functions project with TypeScript in functions/
- [x] T004 Setup Firebase local emulators configuration in firebase.json

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 [P] Implement common domain data types in pkg/domain/session.go
- [x] T006 Implement base WebSocket connection hub in pkg/ws/websocket.go

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Camera Node Setup & Pairing (Priority: P1) 🎯 MVP

**Goal**: Register and pair 5 client nodes via local IP QR code scan.

**Independent Test**: The operator pairs one client smartphone. The coordinator's dashboard displays that 1 camera is connected and ready.

### Implementation for User Story 1

- [x] T007 [US1] Implement pairing QR code generator and console display in cmd/coordinator/main.go
- [x] T008 [P] [US1] Implement WebSocket handshake listener and registration handler in pkg/ws/websocket.go
- [x] T009 [P] [US1] Implement QR code camera scanner and WebSocket client listener in clients/mobile/lib/services/websocket_client.dart
- [x] T010 [US1] Create pairing UI and connection status display in clients/mobile/lib/main.dart
- [x] T011 [US1] Build Cubit/Bloc to manage connection states (pairing, connecting, connected, disconnected) in clients/mobile/lib/bloc/sync_bloc.dart

**Checkpoint**: User Story 1 is fully functional and testable independently.

---

## Phase 4: User Story 2 - Synchronized Capture Trigger (Priority: P1)

**Goal**: Synchronized capture skew <5ms using NTP clock synchronization.

**Independent Test**: The operator triggers the capture, and all paired client nodes capture an image simultaneously.

### Implementation for User Story 2

- [x] T012 [P] [US2] Implement local SNTP/NTP responder server in pkg/ntp/ntp.go
- [x] T013 [P] [US2] Implement NTP time offset synchronization client in clients/mobile/lib/services/ntp_service.dart
- [x] T014 [US2] Implement scheduling capture logic at future epoch timestamp in clients/mobile/lib/bloc/sync_bloc.dart
- [x] T015 [US2] Integrate camera trigger broadcast command on coordinator side in pkg/ws/websocket.go

**Checkpoint**: User Stories 1 and 2 should both work independently.

---

## Phase 5: User Story 3 - Ping-Pong GIF Stitching & Upload (Priority: P2)

**Goal**: Direct frame upload to Storage, Firestore real-time updates, and FFmpeg stitching of frames `1-2-3-4-5-4-3-2`.

**Independent Test**: Captured images are uploaded to storage, stitched into a looping ping-pong GIF, and stored.

### Implementation for User Story 3

- [x] T016 [P] [US3] Implement image capture and direct Firebase Storage upload in clients/mobile/lib/services/upload_service.dart
- [x] T017 [P] [US3] Implement Firestore session state updater in clients/mobile/lib/services/session_service.dart
- [x] T018 [US3] Create Firestore trigger Node.js Cloud Function watching `sessions/{sessionId}` updates in functions/src/index.ts
- [x] T019 [US3] Implement FFmpeg processing slice to sequence frames as `1-2-3-4-5-4-3-2` and upload final GIF in functions/src/stitch.ts

**Checkpoint**: User Stories 1, 2, and 3 are functional.

---

## Phase 6: User Story 4 - In-Person Guest Display (Priority: P2)

**Goal**: Display sharing QR code on coordinator.

**Independent Test**: Guest scans guest QR code displayed by coordinator and views stitched GIF in browser.

### Implementation for User Story 4

- [x] T020 [US4] Implement Firestore subscriber on Go coordinator to listen for session status completions in cmd/coordinator/main.go
- [x] T021 [US4] Display generated guest sharing QR code in coordinator dashboard once gifUrl is available in cmd/coordinator/main.go

---

## Phase N: Polish & Cross-Cutting Concerns

**Purpose**: Compilation configuration, cleaning up, and validation scenario runs.

- [x] T022 [P] Configure cross-compilation scripts for macOS/linux/arm64 in scripts/build.sh
- [x] T023 Run end-to-end local validation scenarios defined in specs/001-multi-camera-photo-booth/quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately.
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories.
- **User Stories (Phase 3+)**: All depend on Foundational phase completion.
  - Can proceed sequentially in priority order: US1 (P1) → US2 (P1) → US3 (P2) → US4 (P2)
- **Polish (Final Phase)**: Depends on all user stories being complete.
