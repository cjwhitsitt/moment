# Feature Specification: Distributed Multi-Camera Photo Booth

**Feature Branch**: `001-multi-camera-photo-booth`

**Created**: 2026-06-23

**Status**: Draft

**Input**: User description: "Build a distributed multi-camera photo booth system that triggers 5 smartphones simultaneously over a local network, uploads the images to cloud storage, and stitches them into a looping ping-pong animation (.gif) available instantly for an in-person guest display via a QR code scan. The setup must utilize a manual QR code scan between the devices to share the local server's IP address."

## Clarifications

### Session 2026-06-25

- Q: Operator Setup Documentation → A: An operator README must exist detailing step-by-step setup, prerequisites, local networking requirements, and troubleshooting (such as mobile data interference and firewall settings) to ensure confident system deployment.
- Q: Client Device Sleep Prevention → A: The Flutter client application must prevent smartphone devices from entering sleep mode or dimming the screen (keeping them awake/active) while they are registered and paired with the coordinator.

### Session 2026-06-26

- Q: Camera Limit flexibility → A: The system will support a variable number of client camera nodes, from a minimum of 3 up to a maximum of 10. The stitching sequence will dynamically construct a ping-pong loop based on the number of active paired cameras (e.g. for N cameras: 1 → 2 → ... → N → N-1 → ... → 2).

### Session 2026-06-27

- Q: Operator Setup Documentation (README.md) camera count references → A: The operator README will be updated to reflect the variable camera count setup (between 3 and 10 smartphones, indices 1 to 10) instead of the previous hardcoded exactly 5.
- Q: Deployment and publishing steps documentation → A: A new section detailing Cloud Functions deployment and Flutter client test publishing (TestFlight/Firebase App Distribution) will be added to the root README.md.
- Q: Resend API Key Setup Documentation → A: The root README.md will include instructions on setting the `RESEND_KEY` environment variable in `functions/.env` for local testing and as a Firebase Secret for production deployment.

### Session 2026-07-04

- Q: Local FFmpeg Executable Resolution on macOS → A: To support local testing using the Firebase emulator on Apple Silicon and Intel macOS architectures, the Cloud Functions stitching code will dynamically probe standard Homebrew paths (`/opt/homebrew/bin/ffmpeg` and `/usr/local/bin/ffmpeg`) and fall back to the system-wide executable if `@ffmpeg-installer/ffmpeg` module loading fails or resolves to an incompatible architecture binary.
- Q: Multi-Device Deployment Automation → A: Automated build-and-deploy helper scripts `install-android.sh` and `install-ios.sh` will be added to the mobile project root to compile release builds and install them in parallel on all connected test devices (using ADB for Android and ios-deploy for iOS).
- Q: Executable output directory mapping → A: The local Go coordinator build process will compile and output to the `build/` directory (ignored by `.gitignore`) to prevent untracked binaries from cluttering the root workspace.
- Q: Batched WebSocket Frame Parsing on Client → A: Due to Gorilla WebSocket's write coalescing optimizations on the coordinator (which packages multiple queued text messages into a single TCP packet frame separated by newlines), the Flutter client's WebSocket parser will split incoming message frames on newlines to parse and process each payload individually, avoiding JSON parsing errors on consolidated registrations.
- Q: Operator Connection IP Input Constraints and Persistence → A: The Coordinator IP text field on the Operator Panel will only accept numeric characters and periods (`[0-9.]`). Additionally, the last successfully entered IP address will be cached locally using `shared_preferences` and auto-filled on application launch.
- Q: FFmpeg fifo Filter Deprecation → A: Starting with FFmpeg v7.0+, the `fifo` video filter has been officially removed from the FFmpeg codebase. The stitching Cloud Function will bypass the `fifo` filter and feed the split video stream branch directly to `paletteuse`, ensuring compatibility with both legacy (v5/v6) and modern (v7/v8) FFmpeg runtimes.
- Q: Camera Preview Alignment and Aspect Ratio → A: To ensure accurate setup alignment, the Camera Node preview MUST preserve its native aspect ratio without stretching or distortion (using uniform scale-to-fill/cover fit). It MUST also overlay a subtle central crosshair indicator at the visual center of the preview.
- Q: Input Resolution Mismatch Artifacts → A: To prevent green lines and blocky decoding artifacts when different camera models upload frames at varying resolutions, the Cloud Functions stitching code will pre-scale all individual frames to a uniform 800x600 resolution prior to invoking the final FFmpeg image2 sequence demuxer.
- Q: Firestore and Storage Security Rules → A: To prevent unauthorized access, Firestore and Storage rules must block all public/unauthenticated read and write requests to session metadata and raw captures. Only cloud functions and privileged operations are permitted to read/write. However, the final stitched GIF files under the public sharing directory must permit public read-only access so guests can access their animations.
- Q: Cloud Functions Node.js Runtime Upgrade → A: Since the Node.js 18 runtime was decommissioned on 2025-10-30, the Cloud Functions engine version in package.json is upgraded to Node.js 20, along with corresponding Node type definitions to ensure full compiler type safety and deprecation warnings resolution.
- Q: Camera Position Index Persistence → A: To streamline camera setup, the Camera Node configuration screen must save the selected camera position index (1 to 10) locally in settings using SharedPreferences, and auto-select this cached value on subsequent app launches.
- Q: Application Launch Default Route → A: To optimize speed-of-setup, the Flutter application MUST launch directly into Camera Node mode by default. The Camera Node configuration screen MUST display a distinct action button allowing the user to switch to Operator Mode.
- Q: SelectionPage Deletion → A: Following the direct-to-camera routing upgrade, the obsolete `SelectionPage` selection screen view class and its corresponding file have been completely removed from the client mobile application codebase.
- Q: Full-screen Operator Share Screen Toggle → A: When a stitched GIF is ready (`done` state), the Operator App MUST switch from the capture dashboard to a full-screen, customer-facing sharing screen (displaying the GIF, download QR code, and email input field) and hide all utilitarian controls. The view MUST include a "Back to Dashboard" close action that resets the active session status and returns to the capture trigger view.
- Q: Operator Sharing Page Layout → A: To highlight the guest's stitched animation, the GIF preview MUST span the full width of the sharing view and be rendered as large as possible (preserving its native 4:3 aspect ratio). All guest sharing options (including the download QR code and the email delivery input field) MUST be positioned secondary to the image, below the preview container.
- Q: Operator mDNS Auto-Start & Connection Confirmation → A: Upon entering Operator Mode, the client application MUST automatically start local network mDNS discovery. While discovery is active, the interface MUST permit manual IP entry. If a coordinator service is resolved, the app MUST halt auto-connection and present a confirmation prompt to the operator to approve connection before initiating the WebSocket registration handshake.



## User Scenarios & Testing *(mandatory)*

### User Story 1 - Camera Node Setup & Pairing (Priority: P1)

An operator sets up the physical photo booth by pairing between 3 and 10 client smartphones with the central coordinator.

**Why this priority**: Without establishing a reliable connection between the coordinator and all client devices, no synchronized capture can occur.

**Independent Test**: The operator launches the coordinator and scan-pairs one client smartphone. The coordinator's dashboard displays that 1 camera is connected and ready.

**Acceptance Scenarios**:

1. **Given** the coordinator is running and displaying a connection QR code containing its local IP address, **When** a camera node application is launched on a smartphone and scans the QR code, **Then** the camera node successfully connects to the coordinator and registers its index (1 to N, where 3 <= N <= 10).
2. **Given** N-1 camera nodes are connected (where 3 <= N <= 10), **When** the Nth camera node scans the pairing QR code, **Then** the coordinator shows all N nodes connected and transitions to the "Ready to Shoot" state.

---

### User Story 2 - Synchronized Capture Trigger (Priority: P1)

An operator triggers the photo booth to capture a synchronized photo session across all N cameras (where 3 <= N <= 10).

**Why this priority**: This is the core interaction that generates the source frames for the final animation.

**Independent Test**: The operator triggers the system, and all connected camera nodes capture an image within the latency target.

**Acceptance Scenarios**:

1. **Given** all connected camera nodes are paired and ready, **When** the operator triggers the capture, **Then** all connected camera nodes receive the trigger simultaneously, capture an image, and send confirmation back to the coordinator.

---

### User Story 3 - Ping-Pong GIF Stitching & Upload (Priority: P2)

The system automatically creates a looping ping-pong animation and uploads it to cloud storage.

**Why this priority**: The animation is the primary deliverable for the photo booth experience.

**Independent Test**: After a capture session, a looping GIF is generated with frames in a ping-pong pattern (e.g. 1-2-3-4-5-4-3-2 for N=5, skipping the duplicate end-frame to prevent lag) and successfully uploaded to cloud storage.

**Acceptance Scenarios**:

1. **Given** N successfully captured frames from a session (where 3 <= N <= 10), **When** the stitching process runs, **Then** a looping .gif animation is generated in a ping-pong pattern (1 → 2 → ... → N → N-1 → ... → 2) and uploaded to cloud storage, returning a unique, secure access URL.

---

### User Story 4 - In-Person Guest Display (Priority: P2)

An in-person guest scans a QR code to view and share their ping-pong animation instantly.

**Why this priority**: High quality user experience relies on low friction, instant access to the final asset.

**Independent Test**: A guest scans a generated QR code with their mobile phone and sees the animation looping on their browser.

**Acceptance Scenarios**:

1. **Given** a successfully generated and uploaded animation, **When** the coordinator displays the guest QR code for that session and a guest scans it, **Then** the guest's mobile device navigates directly to the hosted GIF animation page.

---

### User Story 5 - Operator Control Panel (Priority: P1)

An operator uses a mobile device (tablet or phone) running the app in Operator Mode to pair cameras, trigger captures, view node status, and send the animation to guest emails.

**Why this priority**: Running a headless coordinator on a Raspberry Pi requires a remote control interface so the operator does not need a monitor or terminal access to manage the booth.

**Independent Test**: The operator launches the app in Operator Mode, it connects to the coordinator, displays the pairing QR code, allows triggering captures, and sends an email via a form field.

**Acceptance Scenarios**:

1. **Given** the Go coordinator is running on the local subnet, **When** the operator opens the app in Operator Mode, **Then** it auto-discovers the coordinator via mDNS (with manual IP entry as backup) and establishes a connection.
2. **Given** the Operator App is connected, **When** camera nodes pair, **Then** the Operator App displays a dashboard showing each camera's index, battery level, NTP clock offset, and current state (idle, capturing, uploading, uploaded, error).
3. **Given** the camera nodes are ready, **When** the operator taps "Capture" on the Operator App, **Then** the coordinator triggers a synchronized capture session across all camera nodes.
4. **Given** the capture session finishes stitching, **When** the Operator App displays the sharing screen, **Then** it renders the guest sharing QR code, displays the stitched GIF animation preview, and allows entering a guest email to trigger delivery.

---

### Edge Cases

- **Capture Failure or Timeout**: If one or more camera nodes fail to capture/upload their image within a 10-second timeout window, the capture session is aborted, the operator is notified, and no GIF is generated.
- **Late Trigger Arrival**: If a camera node receives the trigger message with a delay that exceeds the latency tolerance, causing frame misalignment.
- **mDNS Discovery Failure**: If mDNS fails to resolve the coordinator's local IP address, the Operator App must fallback to manual IP configuration so the operator can connect.
- **Email Delivery Failure**: If the email delivery fails (e.g. due to invalid email address or network timeout), the cloud backend must log the failure and notify the Operator App so the operator can retry.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support pairing a variable number of smartphone client nodes (between 3 and 10) with a central coordinator.
- **FR-002**: The system MUST allow sharing the coordinator's local IP address with client nodes using a QR code.
- **FR-003**: The system MUST broadcast a synchronized capture trigger to all connected client nodes.
- **FR-004**: Client nodes MUST capture an image immediately upon receiving the trigger, using NTP time synchronization with the coordinator to coordinate the shutter.
- **FR-005**: The system MUST stitch the captured images into a looping ping-pong animation (frames: 1 → 2 → ... → N → N-1 → ... → 2 for N active nodes).
- **FR-006**: The stitched ping-pong animation MUST be uploaded to cloud storage and associated with a unique shareable URL.
- **FR-007**: The system MUST generate a guest QR code for each stitched animation.
- **FR-008**: If any camera node fails to capture or upload its frame during a session within a 10-second timeout, the system MUST fail the session immediately, show an error on the Operator panel, and not generate/upload a GIF.
- **FR-009**: The system MUST include a comprehensive operator README detailing physical setup, local network configuration, and troubleshooting steps.
- **FR-010**: The Flutter client application MUST keep the device screen active and prevent sleep mode while registered and paired with the coordinator.
- **FR-011**: The system MUST support an Operator Mode in the Flutter application acting as a wireless control dashboard.
- **FR-012**: The Operator App MUST discover the Go coordinator on the local subnet using mDNS and support manual IP address input as backup. The manual IP entry field MUST restrict input to numbers and periods (`[0-9.]`), and MUST persist and auto-fill the last successfully connected IP address on launch.
- **FR-013**: The Operator App MUST display the pairing QR code and monitor each connected camera node's connection state, current capture/upload status, battery level, and NTP clock offset in real time.
- **FR-014**: The Operator App MUST trigger the capture session remotely via the Go coordinator.
- **FR-015**: The Operator App MUST display the guest QR code and the stitched GIF animation preview once stitching completes.
- **FR-016**: The Operator App MUST provide a text input field for guest emails.
- **FR-017**: The Cloud Backend MUST send the stitched GIF via email to the input address using a reliable email delivery service.
- **FR-018**: The Camera Node application MUST display the live camera view in its correct aspect ratio without stretching or distortion, and MUST overlay a central crosshair to assist with device alignment.
- **FR-019**: The Cloud Firestore and Firebase Storage security rules MUST block all public/unauthenticated read/write access to session metadata and raw captured frames. However, the final stitched GIF assets stored under the public sharing path MUST permit public/unauthenticated read access so that guests can scan the QR code to view and download their looping animations.
- **FR-020**: The Camera Node configuration screen MUST persist the last chosen camera position index (1-10) locally using SharedPreferences, and default to this index on launch.
- **FR-021**: The Flutter client application MUST default to launching in Camera Node mode. The Camera Node setup view MUST overlay a navigation element allowing transition to Operator Mode.
- **FR-022**: The Operator App MUST automatically transition to a full-screen, customer-friendly sharing view when the looping GIF stitching is complete. It MUST hide the camera node grid, pairing QR code, and trigger button, and MUST provide a clear "Back to Dashboard" reset control to return to the active capture cockpit.
- **FR-023**: The Operator App's full-screen sharing view MUST display the stitched GIF preview at full-width, as the primary focal element. All sharing hooks (download QR code, email fields, and submit buttons) MUST be arranged underneath the main preview container.
- **FR-024**: The Operator App MUST automatically start mDNS discovery on screen entry. The scanning view MUST display the manual IP address entry input field as a fallback. If resolved, the app MUST transition to a confirmation screen prompting the user to approve connection to the discovered coordinator.

### Key Entities

- **Coordinator**: Central Go service running headlessly to manage capture sessions, device registration, and UDP NTP synchronization.
- **Camera Node**: Client device (smartphone) running the app in Camera Mode that pairs with the coordinator, receives triggers, and captures/uploads images.
- **Operator App (Control Panel)**: Client device (tablet or phone) running the app in Operator Mode that connects to the coordinator to monitor status, display QR codes, and trigger captures.
- **Capture Session**: Represents a single synchronized trigger event, containing the captured frames from all active nodes (3 to 10), a status, and a reference to the final stitched animation.
- **Stitched Animation**: The final ping-pong GIF asset stored in cloud storage with a unique guest-accessible URL.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Guests can view their generated animation on their own devices within 10 seconds of capture.
- **SC-002**: The trigger latency skew across all connected camera nodes (3 to 10) must be less than 5ms.
- **SC-003**: Operators can pair all connected smartphone nodes (up to 10) with the coordinator in under 2 minutes during setup.
- **SC-004**: The system must achieve a 99% success rate for end-to-end workflows (capture-to-display) under nominal local network conditions.
- **SC-005**: The Operator App must discover and establish a connection to the Go coordinator via mDNS within 3 seconds of launching on a configured local network.
- **SC-006**: Emails containing the stitched GIF must be dispatched and complete sending transactions within 2 seconds of form submission.

## Assumptions

- The local network has sufficient bandwidth and low packet loss to support UDP/TCP/WebSockets communication between the coordinator and client nodes.
- Smartphone devices have cameras capable of immediate capture triggers (fast shutter response).
- Guests have mobile data or local Wi-Fi connectivity to access the cloud-stored GIFs after scanning the guest QR code.
