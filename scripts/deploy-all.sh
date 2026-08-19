#!/bin/zsh
# THE DEPLOY LOOP — one command from green tests to every test device.
# (Owner's standing loop: "push it and I will test the new build".)
#
#   ./scripts/deploy-all.sh
#
# Builds macOS + Android release, names dist files by the alpha law
# (docs/versioning.md), installs on the connected phone, replaces
# /Applications/bns.app, and re-dresses the four harness apps
# (.l4-test/.l3-test) with their own bundle identities + entitlements.
# The phone being absent is reported, never fatal — the rest deploys.
set -e
cd "$(dirname "$0")/.."

# Human version 0.XXa derived from pubspec (machine form 0.XX.0+N).
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//' | sed 's/+.*//' \
  | sed -E 's/^([0-9]+)\.([0-9]+)\..*/\1.\2a/')

# adb lives outside a non-interactive shell's PATH (lived 2026-08-18:
# the chain died on `command not found: adb` after both builds passed).
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
command -v adb >/dev/null 2>&1 && ADB=$(command -v adb)
PHONE="${BNS_PHONE:-R5CW62DRCLD}"

echo "== macOS build (v$VERSION) =="
./scripts/build-apple.sh macos

echo "== Android APK =="
flutter build apk --release
mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk "dist/BNS-android-v$VERSION.apk"

echo "== phone $PHONE =="
if "$ADB" -s "$PHONE" install -r build/app/outputs/flutter-apk/app-release.apk; then
  echo "phone: installed (data kept)"
else
  echo "phone: NOT installed (not connected?) — dist/BNS-android-v$VERSION.apk is ready"
fi

echo "== /Applications =="
rm -rf /Applications/bns.app
ditto build/macos/Build/Products/Release/bns.app /Applications/bns.app

echo "== harness x4 =="
for d in .l4-test .l3-test; do
  case $d in
    .l4-test) ent="$d/l4.entitlements";;
    .l3-test) ent="$d/l3.entitlements";;
  esac
  for app in BNS-Person BNS-Care; do
    t="$d/$app.app"
    [ -d "$t" ] || { echo "  $t missing — skipped"; continue; }
    bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$t/Contents/Info.plist")
    bname=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$t/Contents/Info.plist")
    bdisp=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$t/Contents/Info.plist" 2>/dev/null || echo "$bname")
    rm -rf "$t"
    ditto build/macos/Build/Products/Release/bns.app "$t"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bid" "$t/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $bname" "$t/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $bdisp" "$t/Contents/Info.plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $bdisp" "$t/Contents/Info.plist"
    codesign --force --deep -s - --entitlements "$ent" "$t"
    echo "  re-dressed $t as $bid"
  done
done

# THE L2 PAIR AGES TOO (lived 2026-08-19: the seated windows showed
# BNS-Care.app still answering «מתי היום שלך מתחיל?» — a person question
# on a Care seat, because that app predated the data-dir pin and read
# bundle documents instead of .l2-test/caregiver). The gBNS harness pair
# now rides every wave with everyone else. Missing dir = reported, never
# fatal (this Mac may not carry the fork).
L2DIR="$HOME/dev/gBNS/.l2-test"
if [ -d "$L2DIR" ]; then
  echo "== harness L2 pair =="
  for app in BNS-L2 BNS-Care; do
    t="$L2DIR/$app.app"
    case $app in
      BNS-L2)   ent="$L2DIR/l2.entitlements";;
      BNS-Care) ent="$L2DIR/l2care.entitlements";;
    esac
    [ -d "$t" ] || { echo "  $t missing — skipped"; continue; }
    bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$t/Contents/Info.plist")
    bname=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$t/Contents/Info.plist")
    bdisp=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$t/Contents/Info.plist" 2>/dev/null || echo "$bname")
    rm -rf "$t"
    ditto build/macos/Build/Products/Release/bns.app "$t"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bid" "$t/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $bname" "$t/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $bdisp" "$t/Contents/Info.plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $bdisp" "$t/Contents/Info.plist"
    codesign --force --deep -s - --entitlements "$ent" "$t"
    echo "  re-dressed $t as $bid"
  done
else
  echo "== harness L2 pair: $L2DIR not on this Mac — skipped =="
fi

echo "WAVE-DEPLOYED v$VERSION"
