# Project Moment Context
- Architecture: Distributed multi-camera array sync over local network with cloud stitching.
- Backend: Go (Golang) compiled for macOS/Raspberry Pi (arm64).
- Frontend: Flutter (Dart) using BLoC/Cubit for state management (FVM managed).
- Cloud: Firebase (Firestore, Cloud Storage, Node.js Cloud Functions with FFmpeg).
- Absolute Priority: Low latency network coordination (<5ms trigger variance).