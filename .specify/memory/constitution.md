<!--
SYNC IMPACT REPORT
- Version change: none → 1.0.0 (baseline)
- Modified principles: None (initial ratification)
- Added sections: Core Principles I-V, Architecture & Technology Stack Constraints, Verification & Quality Standards, Governance
- Removed sections: None
- Templates requiring updates:
  - .specify/templates/plan-template.md (✅ updated)
  - .specify/templates/spec-template.md (✅ updated)
  - .specify/templates/tasks-template.md (✅ updated)
- Follow-up TODOs: None
-->

# Project Moment Constitution

## Core Principles

### I. Ultra-Low Latency Capture Sync (<5ms Target)
Synchronization of capture events across the multi-camera array is the absolute top priority. The local coordinator must achieve <5ms sync target. Non-deterministic operations (like garbage collection pauses on the hot path or blocking I/O) are strictly prohibited in the capture loop.

### II. Go-Based Coordinator compiled for macOS & Raspberry Pi (arm64)
The local coordinator must be built in Go (Golang) targeting macOS (for local development and control) and Raspberry Pi (arm64) for edge deployment. All hardware and camera trigger components must be abstracted behind clean Go interfaces to support simulation and unit testing.

### III. Flutter/Dart Clients with Bloc/Cubit State Management
Client nodes must be built using Flutter and Dart. Application state management must strictly utilize the Bloc or Cubit pattern to maintain a unidirectional data flow and guarantee clear, testable separations between UI and business logic.

### IV. Firebase Cloud Stitching Infrastructure
The cloud stitching backend must utilize Firebase Firestore for metadata and state orchestration, Firebase Storage for raw and stitched media asset storage, and Node.js Cloud Functions for stitching coordination. Arbitrary cloud resources or external databases must not be introduced without governance approval.

### V. Serverless FFmpeg Video Processing
Multi-camera video stitching must be executed inside Node.js Cloud Functions using FFmpeg command execution. All FFmpeg operations must handle memory constraints, local /tmp cleanup, and execution timeouts gracefully. Processing tasks must be idempotent and log detailed execution steps.

## Architecture & Technology Stack Constraints

- **Local Coordinator (Go)**: Must target `darwin/amd64`, `darwin/arm64`, and `linux/arm64`. Third-party dependencies must be kept to a minimum to ensure rapid startup and lightweight execution.
- **Client Nodes (Flutter/Dart)**: Must enforce strict linting rules. No ad-hoc setState or global mutable states outside the Bloc/Cubit tree.
- **Cloud Backend (Firebase/Node.js)**: Node.js Cloud Functions must utilize structured JSON logging, validate all incoming request payloads, and clean up temporary local files.

## Verification & Quality Standards

- **Latency Verification**: The local coordinator must include benchmark tests measuring synchronization offset. Any change increasing hot-path latency above 1ms must be justified.
- **State Unit Tests**: Flutter client changes to state transitions must be verified with `blocTest`.
- **Stitching Integration**: Stitching Cloud Functions must be tested with simulated multi-camera storage uploads and mock Firestore state changes.

## Governance

- **Compliance**: All proposed code changes must comply with the Core Principles. Violations will reject builds or pull requests.
- **Amendments**: Changes to the Constitution require a version bump (Major for breaking principles, Minor for additions, Patch for clarifications) and ratification update.
- **Guidance**: Refer to the project's [AGENTS.md](file:///Users/jay/Developer/Hobby/moment/AGENTS.md) and current plans for runtime context.

**Version**: 1.0.0 | **Ratified**: 2026-06-23 | **Last Amended**: 2026-06-23
