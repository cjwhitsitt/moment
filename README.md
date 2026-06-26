# Moment: Distributed Multi-Camera Photo Booth

A distributed edge-and-cloud photo booth system that triggers exactly 5 physical smartphone camera nodes simultaneously over a local network, uploads raw captures directly to Firebase Storage, and compiles them via FFmpeg in Node.js Cloud Functions into a smooth looping ping-pong GIF (`1-2-3-4-5-4-3-2`) displayed locally via a guest sharing QR code.

---

## 🎯 System Architecture

- **Go Coordinator**: Exposes a local WebSockets server (default port `8080`) for pairing registration/heartbeats and a local UDP NTP server (default port `1230`) to synchronize client clocks.
- **Flutter Clients**: 5 smartphones running the mobile app. They calculate clock offset relative to the coordinator NTP, establish persistent WebSocket pairing, listen for future-scheduled shutter trigger epochs, keep screens awake during session registration, and upload raw photos directly to Firebase Storage.
- **Cloud Backend**: Firebase Storage (stores frames and finished GIFs), Firestore (orchestrates session states in real-time), and Node.js Cloud Functions (invokes FFmpeg to stitch GIFs).

---

## 📋 Operator Setup Guide

Follow this sequence to set up the system at an event.

### 1. Prerequisites & Networking
- **Single Subnet**: The MacBook hosting the coordinator/emulators and all 5 physical smartphones must be connected to the exact same Wi-Fi router.
- **Network Ports**: Ensure the following ports are open on the host MacBook:
  - `8080` (TCP - WebSockets coordinator)
  - `1230` (UDP - NTP coordinator)
  - `8082` (TCP - Firestore emulator)
  - `9199` (TCP - Storage emulator)
  - `5001` (TCP - Functions emulator)
  - `4000` (TCP - Firebase UI console)

---

### 2. Startup Sequence

1. **Find MacBook local IP address**:
   Open terminal on the MacBook and run:
   ```bash
   ifconfig | grep "inet "
   ```
   Note the local IP address (typically `192.168.1.X` or `10.0.0.X`).
2. **Start the Go Coordinator**:
   ```bash
   go run cmd/coordinator/main.go --port=8080 --ntp-port=1230
   ```
   This will print a pairing QR code to the terminal.
3. **Start the Firebase Emulators**:
   Ensure `firebase.json` binds emulators to `0.0.0.0` (all interfaces) so external devices can reach them:
   ```bash
   firebase emulators:start
   ```
4. **Wipe Client App Cache**:
   On each physical client smartphone, wipe or clear the application cache/data in Settings. 
   *(Important: This clears any cached Dynamic gRPC ports stored in Firestore's offline database).*
5. **Pair the Smartphones**:
   - Open the Flutter client app on each phone.
   - Scan the coordinator pairing QR code.
   - Assign each device a unique camera index (`1` to `5`).
   - Confirm connection state transitions to "Ready" (screen wake locks will engage automatically, preventing the devices from sleeping or dimming).
6. **Trigger Shutter**:
   Once all 5 camera nodes show registered on the coordinator dashboard, click **Capture** or trigger the session endpoint.
7. **View Looping GIF**:
   - The coordinator terminal will print a guest sharing QR code once stitching is complete.
   - Scan with a guest device to view the looping ping-pong GIF.

---

### 3. Troubleshooting Local Connections

If a smartphone fails to connect or displays `ERR_ADDRESS_UNREACHABLE` / `No route to host` / `SocketException`:

* **Disable Mobile/Cellular Data**: 
  Turn off Mobile Data on all client smartphones. If Wi-Fi has no internet access, Android/iOS will route private network requests (`192.168.1.X`) through the cellular interface, where they are unreachable.
* **AP/Client Isolation**: 
  Many home, office, and public routers block wireless clients from talking to each other. If pinging the MacBook's IP from the phone fails, set up a **Personal Mobile Hotspot** on a smartphone, connect the MacBook and all client devices to that hotspot, and use the hotspot's IP address.
* **macOS Firewall**: 
  If the firewall on the MacBook is enabled, it blocks incoming client connections. Temporarily disable the firewall in **System Settings > Network > Firewall** or add allow rules for `node` and the Go `coordinator`.

---

## 🛠️ Developer & Build Guide

### Go Coordinator
- **Build local binary**:
  ```bash
  go build -o build/coordinator cmd/coordinator/main.go
  ```
- **Cross-compile for edge deployment**:
  ```bash
  ./scripts/build.sh
  ```
  Generates target binaries for `darwin/amd64` (Intel Mac), `darwin/arm64` (Apple Mac), and `linux/arm64` (Raspberry Pi) in the `build/` directory.

### Firebase Functions
- **Install and Build**:
  ```bash
  cd functions
  npm install
  npm run build
  ```

### Flutter Client
- **Get Packages**:
  ```bash
  cd clients/mobile
  flutter pub get
  ```
- **Run in Debug**:
  ```bash
  flutter run -d <device-id>
  ```
