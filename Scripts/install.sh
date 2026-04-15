#!/bin/bash
# install.sh — Build and install kiro-bridge to /usr/local/bin
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"

echo "kiro-bridge: Building release binary..."
cd "$PACKAGE_DIR"
swift build -c release --product kiro-bridge

BINARY=".build/release/kiro-bridge"
INSTALL_PATH="/usr/local/bin/kiro-bridge"

echo "kiro-bridge: Installing to $INSTALL_PATH (may require sudo)..."
if [[ -w "/usr/local/bin" ]]; then
    cp "$BINARY" "$INSTALL_PATH"
else
    sudo cp "$BINARY" "$INSTALL_PATH"
fi

echo "kiro-bridge: Installed ✓"
echo ""
echo "Next steps:"
echo "  1. Run: kiro-bridge"
echo "  2. Register in Xcode: Settings → Intelligence → + → Locally Hosted"
echo "     Port: 7077   Description: Kiro"
echo ""
echo "For auto-start on login:"
echo "  cp Scripts/com.kiro-bridge.plist ~/Library/LaunchAgents/"
echo "  launchctl load ~/Library/LaunchAgents/com.kiro-bridge.plist"
