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
