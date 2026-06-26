# Feature Specification: Distributed Multi-Camera Photo Booth

**Feature Branch**: `001-multi-camera-photo-booth`

**Created**: 2026-06-23

**Status**: Draft

**Input**: User description: "Build a distributed multi-camera photo booth system that triggers 5 smartphones simultaneously over a local network, uploads the images to cloud storage, and stitches them into a looping ping-pong animation (.gif) available instantly for an in-person guest display via a QR code scan. The setup must utilize a manual QR code scan between the devices to share the local server's IP address."

## Clarifications

### Session 2026-06-25

- Q: Operator Setup Documentation → A: An operator README must exist detailing step-by-step setup, prerequisites, local networking requirements, and troubleshooting (such as mobile data interference and firewall settings) to ensure confident system deployment.
- Q: Client Device Sleep Prevention → A: The Flutter client application must prevent smartphone devices from entering sleep mode or dimming the screen (keeping them awake/active) while they are registered and paired with the coordinator.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Camera Node Setup & Pairing (Priority: P1)

An operator sets up the physical photo booth by pairing 5 client smartphones with the central coordinator.

**Why this priority**: Without establishing a reliable connection between the coordinator and all client devices, no synchronized capture can occur.

**Independent Test**: The operator launches the coordinator and scan-pairs one client smartphone. The coordinator's dashboard displays that 1 camera is connected and ready.

**Acceptance Scenarios**:

1. **Given** the coordinator is running and displaying a connection QR code containing its local IP address, **When** a camera node application is launched on a smartphone and scans the QR code, **Then** the camera node successfully connects to the coordinator and registers its index (1 to 5).
2. **Given** 4 camera nodes are connected, **When** the 5th camera node scans the pairing QR code, **Then** the coordinator shows all 5 nodes connected and transitions to the "Ready to Shoot" state.

---

### User Story 2 - Synchronized Capture Trigger (Priority: P1)

An operator triggers the photo booth to capture a synchronized photo session across all 5 cameras.

**Why this priority**: This is the core interaction that generates the source frames for the final animation.

**Independent Test**: The operator triggers the system, and all 5 camera nodes capture an image within the latency target.

**Acceptance Scenarios**:

1. **Given** all 5 camera nodes are connected and ready, **When** the operator triggers the capture, **Then** all 5 camera nodes receive the trigger simultaneously, capture an image, and send confirmation back to the coordinator.

---

### User Story 3 - Ping-Pong GIF Stitching & Upload (Priority: P2)

The system automatically creates a looping ping-pong animation and uploads it to cloud storage.

**Why this priority**: The animation is the primary deliverable for the photo booth experience.

**Independent Test**: After a capture session, a looping GIF is generated with frames in the order 1-2-3-4-5-4-3-2 (skipping the duplicate end-frame to prevent lag) and successfully uploaded to cloud storage.

**Acceptance Scenarios**:

1. **Given** 5 successfully captured frames from a session, **When** the stitching process runs, **Then** a looping .gif animation is generated in a ping-pong pattern (1-2-3-4-5-4-3-2) and uploaded to cloud storage, returning a unique, secure access URL.

---

### User Story 4 - In-Person Guest Display (Priority: P2)

An in-person guest scans a QR code to view and share their ping-pong animation instantly.

**Why this priority**: High quality user experience relies on low friction, instant access to the final asset.

**Independent Test**: A guest scans a generated QR code with their mobile phone and sees the animation looping on their browser.

**Acceptance Scenarios**:

1. **Given** a successfully generated and uploaded animation, **When** the coordinator displays the guest QR code for that session and a guest scans it, **Then** the guest's mobile device navigates directly to the hosted GIF animation page.

---

### Edge Cases

- **Capture Failure or Timeout**: If one or more camera nodes fail to capture/upload their image within a 10-second timeout window, the capture session is aborted, the operator is notified, and no GIF is generated.
- **Late Trigger Arrival**: If a camera node receives the trigger message with a delay that exceeds the latency tolerance, causing frame misalignment.
- **Stitching/Upload Interruption**: If the cloud upload or stitching service fails due to network loss.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support pairing exactly 5 smartphone client nodes with a central coordinator.
- **FR-002**: The system MUST allow sharing the coordinator's local IP address with client nodes using a QR code displayed on the coordinator and scanned by the client devices.
- **FR-003**: The system MUST broadcast a synchronized capture trigger to all 5 connected client nodes.
- **FR-004**: Client nodes MUST capture an image immediately upon receiving the trigger, using NTP time synchronization with the coordinator to coordinate the shutter.
- **FR-005**: The system MUST stitch the 5 captured images into a looping ping-pong animation (frames 1-2-3-4-5-4-3-2).
- **FR-006**: The stitched ping-pong animation MUST be uploaded to cloud storage and associated with a unique shareable URL.
- **FR-007**: The system MUST generate a guest QR code for each stitched animation displayed on the central coordinator screen immediately for guests to scan.
- **FR-008**: If any camera node fails to capture or upload its frame during a session within a 10-second timeout, the system MUST fail the session immediately, show an error on the coordinator, and not generate/upload a GIF.
- **FR-009**: The system MUST include a comprehensive operator README detailing physical setup, local network configuration, and troubleshooting steps.
- **FR-010**: The Flutter client application MUST keep the device screen active and prevent sleep mode while registered and paired with the coordinator.

### Key Entities

- **Coordinator**: Central service managing the capture session, device registration, and triggering.
- **Camera Node**: Client device (smartphone) that pairs with the coordinator, receives triggers, and captures/uploads images.
- **Capture Session**: Represents a single synchronized trigger event, containing 5 captured frames, a status, and a reference to the final stitched animation.
- **Stitched Animation**: The final ping-pong GIF asset stored in cloud storage with a unique guest-accessible URL.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Guests can view their generated animation on their own devices within 10 seconds of capture.
- **SC-002**: The trigger latency skew across all 5 camera nodes must be less than 5ms.
- **SC-003**: Operators can pair all 5 smartphone nodes with the coordinator in under 2 minutes during setup.
- **SC-004**: The system must achieve a 99% success rate for end-to-end workflows (capture-to-display) under nominal local network conditions.

## Assumptions

- The local network has sufficient bandwidth and low packet loss to support UDP/TCP/WebSockets communication between the coordinator and client nodes.
- Smartphone devices have cameras capable of immediate capture triggers (fast shutter response).
- Guests have mobile data or local Wi-Fi connectivity to access the cloud-stored GIFs after scanning the guest QR code.
