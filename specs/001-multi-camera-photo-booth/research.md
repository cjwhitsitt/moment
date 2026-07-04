# Research: Distributed Multi-Camera Photo Booth

## Latency & Trigger Synchronization

### Decision
Implement WebSockets for persistent control connections and a custom/local NTP server on the Go local coordinator.

### Rationale
- **NTP Time Sync**: Under standard networks, direct WebSocket trigger messages can suffer from packet jitter, resulting in skews of 10ms to 100ms. By syncing client smartphone clocks with the coordinator's local NTP clock (achieving <1ms synchronization), the coordinator can schedule the capture at a precise future timestamp (e.g., `current_time + 500ms`). The smartphones then trigger their shutter at the exact epoch timestamp, completely eliminating network latency from the shutter trigger path.
- **WebSockets**: Provides low-overhead bidirectional messaging to track connection health, signal trigger events, and coordinate pairing via QR code.

### Alternatives Considered
- **Direct HTTP Trigger Requests**: Rejected due to high overhead (TCP handshake/connection establishment) and high jitter.
- **UDP Broadcast Triggering**: While lower latency than TCP, UDP is unreliable and doesn't solve shutter jitter across devices without clock synchronization. Clock sync remains necessary.

---

## Client Upload Pipeline

### Decision
Flutter clients upload captured images directly to Firebase Cloud Storage asynchronously.

### Rationale
- Offloading the file transfers from the local coordinator to Firebase Storage avoids saturating the local Wi-Fi router's bandwidth.
- Directly uploading to the cloud utilizes the mobile nodes' high-bandwidth uploads (if on LTE/5G or separate Wi-Fi channels) and streamlines backend integration.
- The local coordinator only receives lightweight WebSocket metadata confirming the start of the upload.

### Alternatives Considered
- **Proxy Uploads through Go Coordinator**: Rejected. Uploading five 5MB images sequentially or concurrently through the Go coordinator would clog the local coordinator's bandwidth, increasing latency for subsequent trigger sessions.

---

## Cloud Stitching Backend

### Decision
Node.js Cloud Functions triggered by Firestore document updates, watching for all expected frames to be uploaded (where expected frames $N$ is between 3 and 10), and invoking FFmpeg to produce a looping ping-pong GIF. For $N$ active nodes, the sequence is dynamically generated as $1 \rightarrow 2 \rightarrow ... \rightarrow N \rightarrow N-1 \rightarrow ... \rightarrow 2$.

### Rationale
- **Dynamic Ping-Pong Sequencing**: Reversing the intermediate frames ($N-1 \rightarrow 2$) creates a smooth, seamless loop back to frame 1 without duplicating the endpoint frames (1 and $N$), preventing visual stutters.
- **Firestore Trigger**: Watching for document updates allows the serverless functions to scale down to zero when the booth is idle.
- **FFmpeg**: The industry standard for fast, high-performance image-to-video/GIF processing.
- **Dynamic Expected Frame Count**: Passing `expectedFrames` in the Firestore session metadata (determined by the coordinator's registered client count) lets the Cloud Function dynamically evaluate completion and construct the sequence.

### Alternatives Considered
- **Stitching on Go Coordinator**: Rejected because it consumes local CPU/GPU resources on the edge device (e.g., Raspberry Pi) which could introduce latency jitter for subsequent capture triggers.
- **Static 5-Camera Stitching**: Rejected because it limits physical setup flexibility for operators who need to use 3+ (up to 10) devices.

---

## Coordinator Discovery (mDNS)

### Decision
Use mDNS (Multicast DNS) broadcasting from the Go coordinator and client-side discovery (via `nsd` or `bonsoir`) in the Flutter Operator App, with manual IP address backup.

### Rationale
- **Zero-Configuration**: Event operators should not need to log into routers or run command-line tools to find the Raspberry Pi's local IP address. mDNS allows the Operator App to discover the coordinator's WebSocket port automatically on the local Wi-Fi subnet.
- **Manual Backup**: In networks where multicast traffic is disabled by AP isolation or enterprise policies, a manual IP input field ensures the system remains functional.

### Alternatives Considered
- **Direct Scan**: Having the operator scan a QR code printed by the Pi's terminal. This was rejected because in a headless setup, the Pi has no screen or terminal display.
- **Cloud Registry**: Registering the local IP to a central cloud Firestore database. This was rejected because the local system should be able to establish edge connections first without relying on immediate cloud database updates.

---

## Transactional Email Delivery

### Decision
Use Resend via a dedicated Node.js Cloud Function.

### Rationale
- **Resend**: Offers a highly reliable, developer-friendly REST API for email delivery with excellent deliverability.
- **Node.js Cloud Function**: Decoupling email sending from the Flutter application ensures that email processing doesn't consume mobile device bandwidth or CPU, and allows for securing API credentials on the server side.

### Alternatives Considered
- **Direct Mailgun/Twilio SDKs on Mobile**: Rejected due to exposure of API credentials inside the client mobile application bundle.
- **Firebase Trigger Email Extension**: Rejected because it is less customizable than writing a lightweight, dedicated Node.js function calling Resend directly.

---

## Operator Manual IP Input Constraints & Persistence

### Decision
Limit manual IP keyboard inputs to digits and period characters (`[0-9.]`) and cache the last connected IP address locally using `shared_preferences`.

### Rationale
- **Input Sanitation**: Limiting characters at the keyboard controller layer using `FilteringTextInputFormatter` prevents guests or operators from typing invalid characters (such as letters or special symbols) that would lead to immediate connection parser crashes.
- **Local Cache Persistence**: In production environments, the coordinator's local IP address might remain static or lease-pinned across sessions, but the Operator Panel device might be restarted. Auto-filling the last successfully paired coordinator IP prevents operators from having to manually type the 15-character string on every launch.

### Alternatives Considered
- **No Persistence**: Rejected. Typing IP addresses manually on virtual touch keyboards during multiple setup sessions increases operator configuration friction.
