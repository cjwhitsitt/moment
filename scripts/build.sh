#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

echo "=== Building Project Moment Go Coordinator ==="
mkdir -p build

# 1. macOS amd64 (Intel)
echo "Building for macOS Intel (darwin/amd64)..."
GOOS=darwin GOARCH=amd64 go build -o build/coordinator-darwin-amd64 cmd/coordinator/main.go

# 2. macOS arm64 (Apple Silicon)
echo "Building for macOS Apple Silicon (darwin/arm64)..."
GOOS=darwin GOARCH=arm64 go build -o build/coordinator-darwin-arm64 cmd/coordinator/main.go

# 3. Raspberry Pi (linux/arm64)
echo "Building for Raspberry Pi (linux/arm64)..."
GOOS=linux GOARCH=arm64 go build -o build/coordinator-linux-arm64 cmd/coordinator/main.go

echo "==============================================="
echo "Build complete! Binaries created in 'build/' folder:"
ls -la build/
echo "==============================================="
