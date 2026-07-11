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
- [x] T004 Setup Firebase local emulators configuration (binding to host 0.0.0.0) in firebase.json
- [x] T026 Setup Flutter iOS minimum deployment target version to 15.0 in clients/mobile/ios/Runner.xcodeproj/project.pbxproj
- [x] T027 Configure platform-specific FirebaseOptions (appId and iosBundleId) in clients/mobile/lib/main.dart
- [x] T028 Configure iOS permission description usage keys in clients/mobile/ios/Runner/Info.plist
- [x] T030 Setup Flutter Android cleartext HTTP permissions and internet permission in clients/mobile/android/app/src/main/AndroidManifest.xml
- [x] T032 Setup consistent storage bucket domain ("moment-aad8b.firebasestorage.app") in clients/mobile/lib/main.dart for both iOS and Android to prevent domain mismatches with the backend
- [x] T033 Add @ffmpeg-installer/ffmpeg dependency and update functions/src/stitch.ts to use the package's binary path to prevent system-wide FFmpeg binary requirements

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
- [x] T024 [US1] Add wakelock_plus dependency and configure screen sleep prevention in clients/mobile/lib/bloc/sync_bloc.dart
- [x] T029 [US1] Implement dynamic camera lifecycle management in clients/mobile/lib/main.dart to prevent Android camera resource conflicts between QR Scanner and Camera Preview


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
- [x] T017 [P] [US3] Implement Firestore session state updater (with offline persistence disabled) in clients/mobile/lib/services/session_service.dart
- [x] T018 [US3] Create Firestore trigger Node.js Cloud Function watching `sessions/{sessionId}` updates in functions/src/index.ts
- [x] T019 [US3] Implement FFmpeg processing slice to sequence frames as `1-2-3-4-5-4-3-2` and upload final GIF in functions/src/stitch.ts
- [x] T031 [US3] Update Firebase Admin SDK imports in functions/src/index.ts to use modular subpath imports for FieldValue to resolve runtime serverTimestamp TypeErrors
- [x] T034 [US3] Add conditional local emulator URL generation in functions/src/stitch.ts to bypass cryptographic signedUrl failures under mock emulator credentials

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
- [x] T025 Generate operator setup and troubleshooting README.md at repository root
- [x] T056 Add install-android.sh automated concurrent install script for Android devices in clients/mobile/install-android.sh
- [x] T057 Add install-ios.sh automated concurrent install script for iOS devices in clients/mobile/install-ios.sh

---

## Phase 7: Support Variable Cameras (3-10) & Dynamic Stitching

**Goal**: Support 3 to 10 cameras and dynamic ping-pong stitching.

- [x] T035 [US1] Update Go coordinator ClientNode registration to support index range 1 to 10 in pkg/ws/websocket.go
- [x] T036 [US1] Update Flutter client index dropdown selection list up to 10 in clients/mobile/lib/main.dart
- [x] T037 [US2] Update Go domain TriggerPayload to include expected_frames in pkg/domain/session.go
- [x] T038 [US2] Update Go coordinator trigger handler to enforce 3 to 10 connected nodes and broadcast expected_frames in cmd/coordinator/main.go
- [x] T039 [US2] Update Flutter client to parse expected_frames from WebSocket capture_trigger in clients/mobile/lib/bloc/sync_bloc.dart
- [x] T040 [US3] Update Flutter client SessionService.updateFrameUpload to write expectedFrames to Firestore in clients/mobile/lib/services/session_service.dart
- [x] T041 [US3] Update Cloud Functions onSessionWrite trigger to run when frameKeys matches expectedFrames in functions/src/index.ts
- [x] T042 [US3] Update Cloud Functions stitchFrames to dynamically build ping-pong sequence, scale/pad inputs to 800x600, apply fifo buffering, and set -reinit_filter 0 in functions/src/stitch.ts

---

## Phase 8: User Story 5 - Operator Control Panel (Priority: P1)

**Goal**: Establish remote Operator dashboard connection via mDNS discovery, monitor node status, and trigger captures.

**Independent Test**: The Operator App discovers and connects to the coordinator, displays status metrics for all active camera nodes, and triggers a synchronized capture session.

### Implementation for User Story 5

- [x] T043 [US5] Add nsd dependency to clients/mobile/pubspec.yaml
- [x] T044 [US5] Implement mDNS discovery service in clients/mobile/lib/services/discovery_service.dart to auto-resolve the Go coordinator service on the local Wi-Fi subnet
- [x] T045 [US5] Implement Go mDNS advertiser in pkg/mdns/advertiser.go using github.com/hashicorp/mdns and initialize it on startup in cmd/coordinator/main.go
- [x] T046 [US5] Create connection mode selection screen (Camera Mode vs Operator Mode) in clients/mobile/lib/ui/selection_page.dart
- [x] T047 [US5] Update Go coordinator WebSocket registration handler to support operator connection types in pkg/ws/websocket.go
- [x] T048 [US5] Update Go coordinator to broadcast real-time node state sync payloads to operator connections on registry changes in pkg/ws/websocket.go
- [x] T049 [US5] Update Flutter client to track and send battery level and state updates to coordinator in clients/mobile/lib/bloc/sync_bloc.dart
- [x] T050 [US5] Implement Operator Dashboard UI (pairing QR, camera status grid, battery level, NTP offset, state, and trigger button) in clients/mobile/lib/ui/operator_dashboard_page.dart
- [x] T051 [US5] Implement remote capture trigger command routing (operator_capture_trigger -> capture_trigger) in cmd/coordinator/main.go

**Checkpoint**: Operator Control Panel is functional and can trigger capture sessions.

---

## Phase 9: Support Guest Email Delivery (Priority: P1)

**Goal**: Deliver stitched GIFs to guest email addresses via Resend from the Operator App.

**Independent Test**: Enter an email address on the Operator App, tap submit, and verify that the Resend Cloud Function sends the email containing the stitched GIF.

### Implementation for Phase 9

- [x] T052 [US5] Add resend dependency to functions/package.json
- [x] T053 [P] [US5] Implement Resend client integration and HTML/markdown email template sender in functions/src/email.ts
- [x] T054 [US5] Implement Callable Cloud Function sendGifEmail to validate request inputs and invoke Resend in functions/src/index.ts
- [x] T055 [US5] Implement guest email entry input field, delivery status state, and stitched GIF preview display on Operator App sharing view in clients/mobile/lib/ui/operator_dashboard_page.dart

**Checkpoint**: Guest email sharing delivers stitched animations via Resend.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately.
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories.
- **User Stories (Phase 3+)**: All depend on Foundational phase completion.
  - Can proceed sequentially in priority order: US1 (P1) → US2 (P1) → US3 (P2) → US4 (P2)
- **Variable Cameras (Phase 7)**: Depends on all previous user stories being complete.
- **Operator Control Panel (Phase 8)**: Depends on Variable Cameras (Phase 7) being complete.
- **Guest Email Delivery (Phase 9)**: Depends on Operator Control Panel (Phase 8) being complete.
- **Operator Connection Cache (Phase 10)**: Depends on Operator Control Panel (Phase 8) being complete.
- **Polish (Final Phase)**: Depends on all user stories and Phase 10 being complete.

---

## Phase 10: Operator Connection Caching & Input Filter (Priority: P1)

**Goal**: Implement numeric-only/period input filtering and persistence caching for the Coordinator IP text field on the Operator Panel.

- [x] T058 [US5] Add shared_preferences: ^2.2.3 to clients/mobile/pubspec.yaml
- [x] T059 [US5] Implement text input formatter constraint (FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))) on the Coordinator IP text field in clients/mobile/lib/ui/operator_dashboard_page.dart
- [x] T060 [US5] Implement caching logic in OperatorBloc (or helper service) to save successfully connected IP address to SharedPreferences on successful operator_registered message
- [x] T061 [US5] Implement SharedPreferences loading and autofill logic in OperatorDashboardPage during initState to pre-populate the manual IP entry controller
- [x] T062 Run Scenario 4 validation in specs/001-multi-camera-photo-booth/quickstart.md to verify input filtering and persistence caching.

---

## Phase 11: Camera Preview Alignment & Aspect Ratio (Priority: P1)

**Goal**: Ensure the Camera Node live view displays in real proportions without stretching, and includes center crosshairs for alignment.

- [x] T063 [US1] Implement aspect-ratio-aware FittedBox camera preview container in clients/mobile/lib/main.dart
- [x] T064 [US1] Overlay center focus target alignment icon (Icons.center_focus_weak) over the camera preview using a Stack in clients/mobile/lib/main.dart
- [x] T065 Run Scenario 5 validation in specs/001-multi-camera-photo-booth/quickstart.md to verify scaling and target alignment.

---

## Phase 12: Resolution-Aware Frame Pre-scaling (Priority: P1)

**Goal**: Solve FFmpeg image2 demuxer green line decoding artifacts when input images have varying resolution sizes.

- [x] T066 [Backend] Implement sequential pre-scaling of individual sequence JPEGs to a uniform 800x600 resolution prior to final stitching in functions/src/stitch.ts

---

## Phase 13: Firestore & Storage Security Rules (Priority: P1)

**Goal**: Configure and secure Firestore and Firebase Storage rules to block unauthorized public access but allow public read access for stitched GIF assets.

- [x] T067 Configure and implement secure document-level operations and block list/delete access in firestore.rules
- [x] T068 Configure and implement private raw captures and public stitched GIF download access in storage.rules
- [x] T069 Run Scenario 6 validation in specs/001-multi-camera-photo-booth/quickstart.md to verify rules logic.

---

## Phase 14: Cloud Functions Runtime Upgrade (Priority: P1)

**Goal**: Upgrade Cloud Functions target engine to Node.js 20 to resolve deployment blockages due to decommissioned Node.js 18.

- [x] T070 [Backend] Update engines.node version to 20 and update devDependencies.@types/node to ^20.0.0 in functions/package.json
- [x] T071 Run npm install and verify successful TypeScript compilation under the new runtime environment via npm run build in functions/

---

## Phase 15: Camera Node Dropdown Persistence (Priority: P1)

**Goal**: Ensure the Camera Node position dropdown defaults to the last used position.

- [x] T072 [US1] Load last used camera index from SharedPreferences in HomeScreen initState inside clients/mobile/lib/main.dart
- [x] T073 [US1] Save the selected camera index to SharedPreferences when changed in the DropdownButtonFormField in clients/mobile/lib/main.dart
- [x] T074 Run Scenario 7 validation in specs/001-multi-camera-photo-booth/quickstart.md to verify dropdown persistence.

---

## Phase 16: Default Launch Route & Mode Switch (Priority: P1)

**Goal**: Default MaterialApp home directly to HomeScreen (Camera Node) and add a button to navigate to Operator Mode.

- [x] T075 [US1] Change MaterialApp.home directly to HomeScreen in clients/mobile/lib/main.dart
- [x] T076 [US1] Add a text or icon button in the camera node _buildSetupView to push OperatorDashboardPage in clients/mobile/lib/main.dart
- [x] T077 Run Scenario 8 validation in specs/001-multi-camera-photo-booth/quickstart.md to verify default launching and mode switching.
- [x] T078 Remove the obsolete selection_page.dart view file since launch routes go directly to Camera Node mode.

---

## Phase 17: Full-Screen Sharing Overlay (Priority: P1)

**Goal**: Toggle full-screen guest sharing view on Operator App when stitching completes, and implement coordinator clear session reset event.

- [x] T079 [Backend] Implement operator_clear_session event handler in pkg/ws/websocket.go to clear activeSession and broadcast sync
- [x] T080 [US5] Add ClearActiveSessionEvent to OperatorBloc in clients/mobile/lib/bloc/operator/operator_bloc.dart to send operator_clear_session message
- [x] T081 [US5] Implement full-screen conditional sharing screen toggle in _buildConnectedView inside clients/mobile/lib/ui/operator_dashboard_page.dart
- [x] T082 Run Scenario 9 validation in specs/001-multi-camera-photo-booth/quickstart.md to verify full-screen toggle and return.

---

## Phase 18: Full-Width Preview & Share Sizing (Priority: P1)

**Goal**: Rearrange the share cockpit layout to render the GIF preview at full-width and place sharing options below it.

- [x] T083 [US5] Modify _buildShareSection in clients/mobile/lib/ui/operator_dashboard_page.dart to display the GIF preview image full-width with a 4:3 aspect ratio
- [x] T084 [US5] Rearrange sharing options (download QR code and email fields) to stack cleanly below the preview image inside clients/mobile/lib/ui/operator_dashboard_page.dart
- [x] T085 Run Scenario 10 validation in specs/001-multi-camera-photo-booth/quickstart.md to verify full-width layout integrity.

---

## Phase 19: mDNS iOS Discovery Permissions (Priority: P1)

**Goal**: Permit iOS devices to discover Bonjour coordinator advertisements.

- [x] T086 Declare _moment-coord._tcp under NSBonjourServices key in clients/mobile/ios/Runner/Info.plist to satisfy iOS 14+ Bonjour discovery rules and RFC length limits.

---

## Phase 20: Operator mDNS Auto-Start & Confirmation (Priority: P1)

**Goal**: Auto-trigger mDNS discovery, expose manual IP forms on the scanning view, and add a connection confirmation prompt.

- [x] T087 [US5] Add OperatorDiscovered state to clients/mobile/lib/bloc/operator/operator_bloc.dart and extract the resolved numeric IPv4 address during discovery to bypass DNS lookup constraints
- [x] T088 [US5] Auto-dispatch StartDiscoveryEvent in initState of _OperatorDashboardPageState in clients/mobile/lib/ui/operator_dashboard_page.dart
- [x] T089 [US5] Merge the manual IP connection form into _buildDiscoveringView inside clients/mobile/lib/ui/operator_dashboard_page.dart
- [x] T090 [US5] Build _buildDiscoveredConfirmationView to display confirmation yes/no prompt in clients/mobile/lib/ui/operator_dashboard_page.dart
- [x] T091 Run Scenario 11 validation in specs/001-multi-camera-photo-booth/quickstart.md to verify discovery auto-start, manual fallbacks, and connection confirmations.
- [x] T092 Swap Go coordinator mDNS interface IP lookup order in pkg/mdns/advertiser.go to prevent loopback 127.0.0.1 advertisement.

---

## Phase 21: Client-Side Image Orientation Baking (Priority: P1)

**Goal**: Integrate package:image and bake physical capture orientation into JPEGs before storage uploads.

- [x] T093 Add image: ^4.2.0 package dependency to clients/mobile/pubspec.yaml and run pub get
- [x] T094 [US5] Implement JPEG decoding, bakeOrientation, and encoding logic in UploadService.takeAndUploadPicture inside clients/mobile/lib/services/upload_service.dart
- [x] T095 Run Scenario 12 validation in specs/001-multi-camera-photo-booth/quickstart.md to verify client-side orientation baking.

---

## Phase 22: Camera Node Landscape Header Hiding (Priority: P1)

**Goal**: Conditionally hide the AppBar header in landscape mode on the Camera Node view.

- [x] T096 [US5] Update the Scaffold's appBar construction in clients/mobile/lib/main.dart to conditionally return null when the orientation is landscape
- [x] T097 Run Scenario 13 validation in specs/001-multi-camera-photo-booth/quickstart.md to verify landscape header hiding behavior.

---

## Phase 23: Guest Download Landing Page (Priority: P1)

**Goal**: Setup Firebase Hosting configuration, create the premium index.html landing page, and update the operator panel QR code URL mapping.

- [x] T098 Configure hosting and hosting emulators in firebase.json
- [x] T099 [NEW] Create public/index.html with Outfit/Inter typography, dark-mode styling, responsive canvas, and blob-fetching download script
- [x] T100 [US5] Update QrImageView in clients/mobile/lib/ui/operator_dashboard_page.dart to encode the landing page URL with the query-parameter-mapped GIF storage URL
- [x] T101 Run Scenario 14 validation in specs/001-multi-camera-photo-booth/quickstart.md to verify guest landing page downloads.

---

## Phase 24: Forced 16:9 Aspect Ratio (Priority: P1)

**Goal**: Lock captured frames, client previews, and stitched GIF outputs to a 16:9 (or 9:16) aspect ratio.

- [x] T102 [US5] Update the Cloud Function in functions/src/stitch.ts to run ffprobe on download to detect portrait/landscape, center-crop to 16:9/9:16, and scale output to 800x450/450x800 via FFmpeg
- [x] T103 [US5] Implement CameraOverlayPainter and apply custom painter overlay in clients/mobile/lib/main.dart to draw a 50% opacity translucent black shade outside the active 16:9/9:16 viewfinder zone
- [x] T104 [US5] Update the preview GIF AspectRatio in clients/mobile/lib/ui/operator_dashboard_page.dart to dynamically match 16 / 9 or 9 / 16 depending on the session orientation
- [x] T105 Run Scenario 15 validation in specs/001-multi-camera-photo-booth/quickstart.md to verify 16:9 aspect ratio enforcement.

