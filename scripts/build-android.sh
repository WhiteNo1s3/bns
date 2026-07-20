#!/usr/bin/env bash
# Build a debug APK for owner device testing (Pass 7 feature bundle).
# Usage: ./scripts/build-android.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="${HOME}/flutter/bin:${PATH}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

if ! command -v flutter >/dev/null; then
  echo "Flutter not found. Install or put flutter on PATH."
  exit 1
fi
if [ ! -d "$ANDROID_HOME" ]; then
  echo "Android SDK not found at $ANDROID_HOME"
  echo "Install cmdline-tools / Android Studio, or set ANDROID_HOME."
  exit 1
fi

flutter pub get
# Debug APK: installable without store signing — for personal testing.
flutter build apk --debug
APK="$ROOT/build/app/outputs/flutter-apk/app-debug.apk"
echo ""
echo "APK ready for phone install:"
echo "  $APK"
ls -lh "$APK"
echo ""
echo "Copy to phone and open, or: adb install -r \"$APK\""
