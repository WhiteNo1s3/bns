#!/bin/bash
# BNS — Apple builds, turnkey. Run ON THE MAC from the project root:
#
#   ./scripts/build-apple.sh            # macOS app + iOS build (device-ready archive)
#   ./scripts/build-apple.sh macos      # just the Mac app (zipped into dist/)
#   ./scripts/build-apple.sh ios        # just iOS (then Xcode signs & installs)
#   ./scripts/build-apple.sh ipad-sim   # quick look at iPad layout in the simulator
#
# First time on a new Mac? Read docs/apple-build-guide.md — it walks the
# whole first hour (Xcode, signing, your iPhone). Everything else — plists,
# entitlements, .bns associations, icons — is already configured in the repo.

set -e
cd "$(dirname "$0")/.."

TARGET="${1:-all}"
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//' | sed 's/+.*//')
mkdir -p dist

echo "=== BNS Apple builds (v$VERSION) ==="

# --- sanity checks that save an hour of confusion ---
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not on PATH. Install: https://docs.flutter.dev/get-started/install/macos"
  exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode command line tools missing. Run: xcode-select --install"
  echo "And install Xcode itself from the App Store (one time, big download)."
  exit 1
fi
if ! command -v pod >/dev/null 2>&1; then
  echo "CocoaPods missing. Run: brew install cocoapods   (or: sudo gem install cocoapods)"
  exit 1
fi

flutter pub get

if [[ "$TARGET" == "all" || "$TARGET" == "macos" ]]; then
  echo ""
  echo "--- macOS (clean native, Apple Silicon + Intel) ---"
  flutter build macos --release --obfuscate --split-debug-info=build/symbols-macos
  APP="build/macos/Build/Products/Release/bns.app"
  ZIP="dist/BNS-macos-v$VERSION.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  echo "Mac app:  $APP"
  echo "Shipable: $ZIP  (unzip → drag bns.app to Applications)"
  echo "Note: without notarization, first launch = right-click → Open (once)."
fi

if [[ "$TARGET" == "all" || "$TARGET" == "ios" ]]; then
  echo ""
  echo "--- iOS (iPhone + iPad, one build) ---"
  # No codesign here: signing wants YOUR Apple ID team, chosen in Xcode once.
  flutter build ios --release --no-codesign --obfuscate --split-debug-info=build/symbols-ios
  echo ""
  echo "Built. To put it ON YOUR IPHONE (first time; docs/apple-build-guide.md has pictures-level detail):"
  echo "  1. open ios/Runner.xcworkspace"
  echo "  2. Xcode → Runner target → Signing & Capabilities → Team: your Apple ID"
  echo "  3. Plug in the iPhone, pick it as the destination, press Run ▶"
  echo "For the App Store later: Product → Archive → Distribute (needs the paid developer account)."
fi

if [[ "$TARGET" == "ipad-sim" ]]; then
  echo ""
  echo "--- iPad simulator (layout check: sidebar in landscape) ---"
  SIM_ID=$(xcrun simctl list devices available | grep -m1 -i 'iPad' | grep -oE '[0-9A-F-]{36}') || true
  if [[ -z "$SIM_ID" ]]; then
    echo "No iPad simulator found — open Xcode → Settings → Platforms to add one."
    exit 1
  fi
  xcrun simctl boot "$SIM_ID" 2>/dev/null || true
  open -a Simulator
  flutter run -d "$SIM_ID"
fi

echo ""
echo "Done."
