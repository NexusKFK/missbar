#!/bin/bash
#
# Downloads a missbar release (or takes one you already have), re-signs it with this machine's
# local identity, and installs it into /Applications.
#
# Usage:
#   scripts/install-local.sh                 # latest release
#   scripts/install-local.sh v2.16.0-missbar.2
#   scripts/install-local.sh /path/to/missbar.zip
#   scripts/install-local.sh /path/to/missbar.app
#
# The re-signing is the point. CI ships an ad-hoc signature, whose designated requirement is a
# bare cdhash that changes with every build, so macOS treats each update as a new program and
# drops its Accessibility and Screen Recording grants. Signing with the certificate that
# scripts/create-signing-identity.sh created produces an identity-based requirement that is
# identical across builds, so the grants carry over.

set -euo pipefail

IDENTITY="${MISSBAR_SIGNING_IDENTITY:-missbar Local Signing}"
REPO="${MISSBAR_REPO:-NexusKFK/missbar}"
DEST="/Applications/missbar.app"
ARG="${1:-}"

if ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    echo "No signing identity '$IDENTITY' on this machine." >&2
    echo "Run scripts/create-signing-identity.sh first." >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---- obtain the app ----------------------------------------------------------------------
if [[ "$ARG" == *.app ]]; then
    [ -d "$ARG" ] || { echo "No such app: $ARG" >&2; exit 1; }
    ditto "$ARG" "$WORK/missbar.app"
elif [[ "$ARG" == *.zip ]]; then
    [ -f "$ARG" ] || { echo "No such file: $ARG" >&2; exit 1; }
    ditto -x -k "$ARG" "$WORK"
else
    command -v gh >/dev/null || { echo "gh is required to download a release." >&2; exit 1; }
    if [ -n "$ARG" ]; then
        echo "Downloading $REPO $ARG…"
        gh release download "$ARG" --repo "$REPO" --pattern 'missbar.zip' --dir "$WORK"
    else
        echo "Downloading the latest $REPO release…"
        gh release download --repo "$REPO" --pattern 'missbar.zip' --dir "$WORK"
    fi
    ditto -x -k "$WORK/missbar.zip" "$WORK"
fi

APP="$WORK/missbar.app"
[ -d "$APP" ] || { echo "No missbar.app found in the downloaded archive." >&2; exit 1; }

VERSION="$(/usr/bin/defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
echo "Found missbar $VERSION"

# ---- re-sign -----------------------------------------------------------------------------
# Entitlements are taken from the build rather than from App/missbar.entitlements: re-signing
# without them silently produces an app that cannot launch at all, because the hardened runtime
# then blocks its own bundled Sparkle.framework. Reading them back from the bundle keeps this
# script correct even if the entitlements change, with no second copy to drift.
ENT="$WORK/entitlements.plist"
codesign -d --entitlements "$ENT" --xml "$APP" 2>/dev/null
plutil -lint "$ENT" >/dev/null || { echo "Could not read the build's entitlements." >&2; exit 1; }

echo "Signing with '$IDENTITY'…"
# Inside-out: nested code must be signed before the bundle that contains it.
find "$APP/Contents/Frameworks" "$APP/Contents/XPCServices" \
     -maxdepth 1 -mindepth 1 \( -name '*.framework' -o -name '*.xpc' -o -name '*.dylib' \) \
     -print0 2>/dev/null |
while IFS= read -r -d '' nested; do
    codesign --force --sign "$IDENTITY" --options runtime "$nested" 2>/dev/null
done
codesign --force --sign "$IDENTITY" --entitlements "$ENT" --options runtime "$APP"

codesign --verify --deep --strict "$APP"

# `codesign --verify` passes on a bundle that cannot actually run -- it checks that each nested
# component is validly signed, not that their Team IDs agree -- so load the binary before
# replacing a working install with it.
( "$APP/Contents/MacOS/missbar" >"$WORK/dyld.log" 2>&1 & echo $! >"$WORK/app.pid" ) || true
sleep 6
kill -9 "$(cat "$WORK/app.pid")" 2>/dev/null || true
if grep -qE "Library not loaded|different Team IDs|code signature.*not valid" "$WORK/dyld.log"; then
    echo "The re-signed app cannot load its own frameworks; not installing." >&2
    grep -E "Library not loaded|Reason:" "$WORK/dyld.log" | head -3 >&2
    exit 1
fi

# ---- install -----------------------------------------------------------------------------
osascript -e 'tell application "missbar" to quit' 2>/dev/null || true
sleep 2
pkill -x missbar 2>/dev/null || true
sleep 1

rm -rf "$DEST"
ditto "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo
echo "Installed missbar $VERSION to $DEST"
codesign -d -r- "$DEST" 2>&1 | grep designated | sed 's/^/  /'
echo
echo "That requirement is the same for every build signed with this identity, so macOS keeps"
echo "the Accessibility and Screen Recording grants across updates."
echo
open -a "$DEST"
