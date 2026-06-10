#!/usr/bin/env bash
# Build Hillराब्ता IPA for TestFlight upload.
# Requires: macOS, Xcode, Flutter, Apple Developer account.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Flutter pub get"
flutter pub get

echo "==> Build iOS release (no codesign — Xcode will sign)"
flutter build ipa --release \
  --export-options-plist=ios/ExportOptions.plist

echo ""
echo "IPA ready at: build/ios/ipa/"
echo "Upload with Transporter app or:"
echo "  xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios -u YOUR_APPLE_ID"
