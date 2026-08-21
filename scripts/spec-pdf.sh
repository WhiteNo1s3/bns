#!/bin/zsh
# THE SPEC AS A PDF — docs/BNS-SPEC.md → dist/BNS-SPEC-v<human>.pdf
# (owner, 2026-08-21: "we need md file pdf level with specs, levels, sync,
# features and all included in bns"). Self-contained: our own tiny
# Markdown→HTML (scripts/spec-md2html.py) + Chrome headless to print.
# No packages installed on the Mac for this.
set -e
cd "$(dirname "$0")/.."
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//' | sed 's/+.*//' \
  | sed -E 's/^([0-9]+)\.([0-9]+)\..*/\1.\2a/')
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "Google Chrome not found at $CHROME"; exit 1; }
mkdir -p dist build/spec
python3 scripts/spec-md2html.py docs/BNS-SPEC.md build/spec/BNS-SPEC.html
OUT="dist/BNS-SPEC-v$VERSION.pdf"
"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="$PWD/$OUT" "file://$PWD/build/spec/BNS-SPEC.html" 2>/dev/null
echo "SPEC-PDF $OUT ($(du -h "$OUT" | cut -f1))"
