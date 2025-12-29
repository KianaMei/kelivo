#!/bin/bash
# bundle_agent_runtime.sh
# Downloads and bundles Node.js runtime for macOS/Linux agent functionality
#
# Usage: ./bundle_agent_runtime.sh [--node-version 22.16.0] [--platform darwin-arm64|darwin-x64|linux-x64]

set -e

# Default values
NODE_VERSION="22.16.0"
PLATFORM=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --node-version)
            NODE_VERSION="$2"
            shift 2
            ;;
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--node-version VERSION] [--platform PLATFORM]"
            echo ""
            echo "Options:"
            echo "  --node-version  Node.js version (default: 22.16.0)"
            echo "  --platform      Target platform: darwin-arm64, darwin-x64, linux-x64"
            echo "                  (default: auto-detect)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Determine platform if not specified
if [[ -z "$PLATFORM" ]]; then
    UNAME_S=$(uname -s)
    UNAME_M=$(uname -m)

    case "$UNAME_S" in
        Darwin)
            case "$UNAME_M" in
                arm64)
                    PLATFORM="darwin-arm64"
                    ;;
                x86_64)
                    PLATFORM="darwin-x64"
                    ;;
                *)
                    echo "Unsupported macOS architecture: $UNAME_M"
                    exit 1
                    ;;
            esac
            ;;
        Linux)
            case "$UNAME_M" in
                x86_64)
                    PLATFORM="linux-x64"
                    ;;
                aarch64)
                    PLATFORM="linux-arm64"
                    ;;
                *)
                    echo "Unsupported Linux architecture: $UNAME_M"
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "Unsupported OS: $UNAME_S"
            exit 1
            ;;
    esac
fi

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_ROOT/resources/agent-runtime"
AGENT_BRIDGE_SOURCE="$PROJECT_ROOT/assets/agent-bridge"

# Node.js archive name
NODE_ARCHIVE="node-v${NODE_VERSION}-${PLATFORM}.tar.gz"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_ARCHIVE}"
NODE_DIR="$OUTPUT_DIR/$PLATFORM"

echo "Kelivo Agent Runtime Bundler for macOS/Linux"
echo "============================================="
echo "Node.js Version: $NODE_VERSION"
echo "Platform: $PLATFORM"
echo "Output Directory: $OUTPUT_DIR"
echo ""

# Create directories
mkdir -p "$NODE_DIR"

# Download and extract Node.js
NODE_BIN="$NODE_DIR/node"
if [[ ! -f "$NODE_BIN" ]]; then
    TEMP_DIR=$(mktemp -d)
    ARCHIVE_PATH="$TEMP_DIR/$NODE_ARCHIVE"

    echo "Downloading Node.js $NODE_VERSION for $PLATFORM..."
    echo "URL: $NODE_URL"

    if command -v curl &> /dev/null; then
        curl -fSL "$NODE_URL" -o "$ARCHIVE_PATH"
    elif command -v wget &> /dev/null; then
        wget -q "$NODE_URL" -O "$ARCHIVE_PATH"
    else
        echo "Error: Neither curl nor wget found"
        exit 1
    fi

    echo "Extracting Node.js..."
    tar -xzf "$ARCHIVE_PATH" -C "$TEMP_DIR"

    EXTRACTED_DIR="$TEMP_DIR/node-v${NODE_VERSION}-${PLATFORM}"

    # Copy node binary
    if [[ -f "$EXTRACTED_DIR/bin/node" ]]; then
        cp "$EXTRACTED_DIR/bin/node" "$NODE_BIN"
        chmod +x "$NODE_BIN"
        echo "Node binary copied to: $NODE_BIN"
    else
        echo "Error: node binary not found in extracted archive"
        exit 1
    fi

    # Cleanup
    rm -rf "$TEMP_DIR"
else
    echo "Node.js already present, skipping download."
fi

# Copy agent-bridge files
AGENT_BRIDGE_OUTPUT="$OUTPUT_DIR/agent-bridge"
echo ""
echo "Copying agent-bridge files..."

rm -rf "$AGENT_BRIDGE_OUTPUT"
cp -r "$AGENT_BRIDGE_SOURCE" "$AGENT_BRIDGE_OUTPUT"

# Remove unnecessary files
rm -f "$AGENT_BRIDGE_OUTPUT/package-lock.json"
rm -f "$AGENT_BRIDGE_OUTPUT/.npmrc"
rm -f "$AGENT_BRIDGE_OUTPUT/.gitignore"

echo "Agent-bridge files copied."

# Calculate sizes
NODE_SIZE=$(du -sh "$NODE_BIN" 2>/dev/null | cut -f1)
BRIDGE_SIZE=$(du -sh "$AGENT_BRIDGE_OUTPUT" 2>/dev/null | cut -f1)

echo ""
echo "============================================="
echo "Bundle complete!"
echo "  Node.js:      $NODE_SIZE"
echo "  Agent-bridge: $BRIDGE_SIZE"
echo ""
echo "Output: $OUTPUT_DIR"
echo ""
echo "Next steps for macOS:"
echo "1. Run 'flutter build macos --release'"
echo "2. Copy $OUTPUT_DIR to the app bundle"
echo "   (build/macos/Build/Products/Release/Kelivo.app/Contents/Resources/agent-runtime)"
echo ""
echo "Next steps for Linux:"
echo "1. Run 'flutter build linux --release'"
echo "2. Copy $OUTPUT_DIR to the build output"
echo "   (build/linux/x64/release/bundle/data/agent-runtime)"
