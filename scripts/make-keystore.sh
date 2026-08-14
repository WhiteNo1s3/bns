#!/usr/bin/env bash
# Creates YOUR Android release signing certificate on macOS / Linux —
# run ONCE, keep forever. (Mirror of scripts/make-keystore.ps1 for the PC.)
#
# What it does:
#   1. Finds keytool (JAVA_HOME / Android Studio's bundled JBR / PATH).
#   2. Generates android/bns-release.jks (your certificate, valid ~27 years).
#   3. Writes android/key.properties so gradle picks it up automatically.
# After this, every `flutter build apk --release` on this machine is signed
# with YOUR certificate — and every future build signed with the SAME
# certificate installs straight over the app on the phone, keeping the
# person's routines, memories and voice notes. That is the whole point.
#
# IMPORTANT:
#   - The .jks and key.properties are GITIGNORED. Never commit or share them.
#   - BACK UP android/bns-release.jks + the password somewhere safe (password
#     manager + a copy on another disk). If they are lost, a future update can
#     NOT be installed over the old app — Android sees a stranger, and the
#     only way through is uninstalling, which deletes the person's data.
#   - A certificate made HERE is a different identity from the one on the PC.
#     Whichever machine signs, every later update must use the same file.
#   - Your password is typed by YOU, here, and goes nowhere else.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
jks="$root/android/bns-release.jks"
props="$root/android/key.properties"

if [[ -e "$jks" ]]; then
  echo "A release keystore already exists: $jks"
  echo "You almost never want a second one (updates must keep the SAME certificate)."
  echo "Delete it by hand first if you truly mean to start over."
  exit 1
fi

# --- find keytool ---
keytool=""
if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/keytool" ]]; then
  keytool="$JAVA_HOME/bin/keytool"
else
  for c in \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
    "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
    "$(command -v keytool || true)"
  do
    if [[ -n "$c" && -x "$c" ]]; then keytool="$c"; break; fi
  done
fi
if [[ -z "$keytool" ]]; then
  echo "keytool not found. Install a JDK or Android Studio, or set JAVA_HOME." >&2
  exit 1
fi
echo "Using keytool: $keytool"
echo

# --- ask for the password (this is YOURS — store it in a password manager) ---
read -r -s -p "Choose a keystore password (min 6 chars): " p1; echo
read -r -s -p "Type it again: " p2; echo
if [[ "$p1" != "$p2" ]]; then echo "Passwords don't match." >&2; exit 1; fi
if [[ ${#p1} -lt 6 ]]; then echo "Too short (min 6)." >&2; exit 1; fi

# Passwords go in on stdin, never on the command line — an argument would be
# visible to every other process on the machine while keytool runs.
printf '%s\n%s\n' "$p1" "$p1" | "$keytool" -genkeypair -v \
  -keystore "$jks" \
  -alias bns \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=BNS, O=whiteno1se enterprise (SHALTIEL), C=IL"

# key.properties: read by android/app/build.gradle.kts (storeFile is
# resolved relative to the android/ folder). Readable only by you.
umask 077
cat > "$props" <<EOF
storePassword=$p1
keyPassword=$p1
keyAlias=bns
storeFile=bns-release.jks
EOF
chmod 600 "$props" "$jks"

echo
echo "Done. Release builds on this Mac are now signed with YOUR certificate."
echo "  Keystore:   $jks"
echo "  Properties: $props"
echo
echo "NOW BACK UP the .jks file + the password (password manager + second disk)."
echo "Lose them and no future build can ever update this app without a wipe."
