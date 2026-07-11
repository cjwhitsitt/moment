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

---

## Camera Node Preview Scaling & Alignment Crosshairs

### Decision
Display the camera preview inside a `ClipRect` -> `FittedBox(fit: BoxFit.cover)` wrapper referencing native camera resolution aspect ratios, and overlay a target focus alignment icon (`Icons.center_focus_weak`) using a centered `Stack`.

### Rationale
- **No-Distortion Fit**: Wrapping the `CameraPreview` inside a `FittedBox` with `BoxFit.cover` ensures that the preview dynamically fills the allotted container bounds uniformly without squishing or stretching its aspect ratio.
- **Orientation Compensation**: Since camera sensors report preview sizes in landscape format by default, swapping width and height dynamically based on the device's portrait orientation ensures the box matches the layout dimensions correctly.
- **Alignment Target**: Overlaying a semi-transparent `Icons.center_focus_weak` target in the absolute visual center coordinates gives the operator a quick references point to align all camera array nodes horizontally and vertically.

### Alternatives Considered
- **Custom Painter Grid**: Rejected. While extremely flexible, drawing a full grid overlay is more complex than displaying a high-contrast target icon, which provides sufficient visual cues for node center alignment.

---

## Firestore and Storage Security Rules Design

### Decision
Configure `firestore.rules` to permit individual document `get` and `create`/`update` write operations but block collection `list` queries and deletions. Configure `storage.rules` to deny read access on raw `captures/` but allow public read access on `stitched/` shareable GIFs.

### Rationale
- **Obscurity & Restricted Operations for Kiosk**: Because kiosk mobile clients pair dynamically on the local network without user authentication, rules cannot rely on `request.auth` checks. Disabling `list` prevent malicious parties from harvesting session lists, and disabling `delete` prevents session tampering, while still allowing the client app to write updates and fetch its current session document.
- **Data Protection**: Banning public read access on `captures/` prevents unauthorized downloads of individual raw frames. Allowing public read access on `stitched/` ensures that any guest scanning the sharing QR code can resolve the signed storage URL to view and download their GIF immediately.

### Alternatives Considered
- **Anonymous Auth**: Rejected. Requiring client registration flow over the internet complicates setup and creates unnecessary dependency on external Firebase Auth servers for an offline-first local network setup.

---

## Camera Node Position Index Persistence

### Decision
Cache the selected camera index locally using `shared_preferences` under the key `'camera_position_index'`, load it during `initState` in the camera home widget, and update the cache whenever the user changes the dropdown option.

### Rationale
- **Reduced Setup Overhead**: When setting up the physical booth, camera smartphone nodes are usually mounted to a fixed position. If the app crashes or restarts, having the dropdown automatically load its last assigned index avoids human error (e.g. accidentally setting two nodes to the same index).

### Alternatives Considered
- **Central Coordination Discovery**: Rejected. Letting the coordinator dynamically assign indices based on registration order is less predictable than physical placement mapping, which is highly sensitive to index order (since frame sequencing depends strictly on sequential indices 1 to N).

---

## Default Launch Route and Mode Navigation

### Decision
Set the default `home` route of the `MaterialApp` in `main.dart` directly to `HomeScreen` (Camera Node view), and add an action button in the Camera Node configuration screen that navigates to the `OperatorDashboardPage` using standard Flutter `Navigator.push`.

### Rationale
- **Streamlined Edge Setup**: Since the vast majority of devices running the app in a physical photo booth array are camera nodes (e.g. 10 phones vs 1 operator dashboard), forcing selection on every launch creates redundant UI interaction overhead. Starting directly on the Camera Node configuration saves operator setup clicks.
- **Navigation Hierarchy**: Pushing the Operator Dashboard as a secondary screen on top of the home screen allows simple back-navigation to return to the default camera mode state.

### Alternatives Considered
- **Persistence of Mode Selection**: Rejected. Caching the operator mode selection state is more complex and less predictable than providing a static navigation transition button from the camera setup view.

---

## Operator Full-Screen Customer Sharing Cockpit

### Decision
Display the sharing section full-screen when the current session status resolves to `'done'`. Implement an `operator_clear_session` WebSocket event handler on the Go coordinator to reset its memory state and trigger sync broadcasts, and map this to a "Back to Dashboard" text button in the top right.

### Rationale
- **Clean Customer UX**: During physical booth events, guests should not be distracted by device battery percentages, camera indices, or developer-facing debug logs. Automatically rendering the GIF preview, download QR code, and email form full-screen hides the operational layout from guests.
- **Session Lifecycle Isolation**: Sending an explicit `operator_clear_session` command to reset the coordinator's state ensures that the entire system (including client devices) is re-initialized and ready for the next trigger capture, preventing UI sync lockups.

### Alternatives Considered
- **Local Cache Reset**: Rejected. Simply clearing the active session locally inside the Operator App widget state doesn't reset the coordinator's state, meaning the coordinator will continue advertising the finished session, leading to synchronization mismatches.

---

## Full-Width GIF Preview and Share Arrangement Layout

### Decision
Re-architect the share section in the Operator App. The preview image spans the full width of the view and expands to cover maximum vertical space while maintaining its native 4:3 aspect ratio. The QR code download indicator and email input/submit buttons are stacked cleanly underneath the image.

### Rationale
- **Visual Prominence**: Looping GIFs are the ultimate product of the photo booth experience. Maximizing the preview's area gives guests immediate visual feedback, while secondary actions (download/email) are naturally discovered by scrolling down.

### Alternatives Considered
- **Horizontal Side-by-Side Slicing**: Rejected. Rendering the GIF and QR code in a single row restricts the preview's area, rendering it too small on compact phone screens.

---

## Operator mDNS Discovery Auto-Start & Confirmation Workflow

### Decision
Introduce a new state `OperatorDiscovered(String url)` in `OperatorBloc`. Auto-trigger `StartDiscoveryEvent` on operator page load (bypassing the initial welcome button). Merge the manual IP connection form onto the scanning screen itself (`OperatorDiscovering` state) so it remains accessible during background scans. Render a clear yes/no confirmation prompt when the state transitions to `OperatorDiscovered`.

### Rationale
- **Frictionless Auto-pairing**: Having mDNS start automatically saves a user action. However, connecting silently to the first discovered coordinator on a busy network could connect the operator to the wrong coordinator instance. Requiring confirmation preserves user agency.
- **Accessible Manual Fallback**: Displaying the manual IP fields on the scanning screen prevents the operator from having to tap "Cancel" to expose the manual inputs if auto-discovery hangs.

### Alternatives Considered
- **Silently Connect on Scan Success**: Rejected. Risk of connecting to neighboring booths at multi-setup events.

---

## Client-Side Image Orientation Baking (Bake Orientation)

### Decision
Add `image: ^4.2.0` package dependency to the Flutter mobile client app. Before uploading any captured JPEG image to Firebase Storage inside `UploadService.takeAndUploadPicture`, read the captured file, decode it using `package:image`'s `decodeImage`, physically rotate the pixel grid to bake in the correct EXIF orientation using `bakeOrientation`, re-encode it to JPEG with `encodeJpg`, and write the rotated bytes back to the file before uploading.

### Rationale
- **Exif Decoupling**: Android's `camera` package encodes JPEG bytes in the camera sensor's native landscape grid, referencing the true orientation in EXIF tags. Because FFmpeg's image sequence compilation pipeline does not natively parse or apply individual JPEG EXIF orientation metadata on some setups, baking the orientation physically into the image pixel buffer resolves rotation issues 100% reliably.
- **Zero Shutter Delay Impact**: Decoding, rotating, and encoding JPEGs is deferred to the asynchronous upload queue thread (`UploadService.takeAndUploadPicture` run in the background after the capture hot path), meaning the synchronized capture timing/latency is unaffected.

### Alternatives Considered
- **FFmpeg Autorotate Filter**: Rejected. FFmpeg's `image2` demuxer and jpeg reader ignore EXIF orientation metadata on certain OS/version configs.

---

## Camera Node Landscape Header Conditionally Hidden

### Decision
Detect device orientation in `main.dart`'s `build` method using `MediaQuery.of(context).orientation`. If the orientation matches `Orientation.landscape`, set the Scaffold's `appBar` parameter to `null` to hide the "Moment Camera Node" header. When the orientation matches `Orientation.portrait`, render the AppBar normally.

### Rationale
- **Maximizing Viewport Height**: In landscape mode, phone screens have very limited vertical space. An AppBar consumes valuable pixels, resulting in a squished camera preview. Hiding it ensures the camera live feed occupies the maximum possible vertical area.

### Alternatives Considered
- **Custom Tiny Header**: Rejected. Still consumes pixels and doesn't offer enough utility to justify the layout compression.

---

## Guest Download Landing Page (Firebase Hosting)

### Decision
Create a static single-page application at `public/index.html` and configure Firebase Hosting in `firebase.json` (along with the Hosting emulator on port 5000). The landing page will extract the `gif` URL query parameter, display the preview GIF with premium dark-mode styling, and use JavaScript blob fetching to trigger direct-to-disk file downloads.

### Rationale
- **Direct Download Control**: Mobile and desktop browsers usually open raw URLs pointing to foreign CDNs (like `firebasestorage.googleapis.com`) directly in a new browser tab instead of triggering a file download. Implementing blob fetching on our own Firebase Hosting domain bypasses this origin restriction, enabling a reliable "Download" button.
- **Flexible Subnet Emulation**: In emulator/local development mode, the operator app generates the QR code pointing to `http://<coordinator-ip>:5000/?gif=...`. In production, it points to `https://moment-aad8b.web.app/?gif=...`.
