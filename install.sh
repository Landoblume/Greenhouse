#!/usr/bin/env bash
#
# Build Greenhouse and install it on the iPhone, in one shot.
#
#   ./install.sh            # regenerate, build, install
#   ./install.sh --launch   # ...and launch it on the phone
#
# The phone must be plugged in (or paired over Wi-Fi) and unlocked, with
# Developer Mode on. Once installed, the app runs standalone — unplug and go.
#
# No weekly re-install needed. The 7-day signature expiry is a free Personal
# Team limit; on the paid Developer Program the profile is good for a year, so
# an installed build keeps opening. Check the current expiry with:
#
#   security cms -D -i ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision \
#       | plutil -p - | grep ExpirationDate

set -euo pipefail

cd "$(dirname "$0")"

SCHEME="Greenhouse"
PROJECT="Greenhouse.xcodeproj"
BUNDLE_ID="com.landenblume.greenhouse"

LAUNCH=false
[[ "${1:-}" == "--launch" ]] && LAUNCH=true

# --- find the phone -----------------------------------------------------------
# Pick the first connected physical device. `state` must be "connected" — a
# device showing "connected (no DDI)" has Developer Mode off and cannot be
# installed to.
#
# Use the hardware UDID, not devicectl's `identifier`: that's a CoreDevice
# UUID, which xcodebuild's -destination doesn't recognise. devicectl accepts
# either, so the UDID works for both.
DEVICE_JSON=$(mktemp)
trap 'rm -f "$DEVICE_JSON"' EXIT
xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null 2>&1

DEVICE_ID=$(python3 -c "
import json, sys
d = json.load(open('$DEVICE_JSON'))
for dev in d.get('result', {}).get('devices', []):
    props = dev.get('deviceProperties', {})
    conn = dev.get('connectionProperties', {})
    if conn.get('tunnelState') != 'unavailable' or conn.get('pairingState') == 'paired':
        udid = dev.get('hardwareProperties', {}).get('udid') or dev['identifier']
        print(udid, props.get('name', '?'), sep='\t')
        break
" 2>/dev/null || true)

if [[ -z "$DEVICE_ID" ]]; then
    echo "No paired iPhone found."
    echo "  - plug it in and unlock it"
    echo "  - Settings > Privacy & Security > Developer Mode must be ON"
    exit 1
fi

UDID=$(cut -f1 <<<"$DEVICE_ID")
NAME=$(cut -f2 <<<"$DEVICE_ID")
echo "==> Target: $NAME"

# --- regenerate ---------------------------------------------------------------
# The .xcodeproj is generated and gitignored, so a new source file is invisible
# to the build until this runs. Cheap; always do it.
echo "==> Regenerating project"
xcodegen generate --quiet

# --- build --------------------------------------------------------------------
# -allowProvisioningUpdates lets Apple mint/refresh the profile; without it the
# CLI refuses to sign even when the GUI would happily do so.
echo "==> Building"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS,id=$UDID" \
    -allowProvisioningUpdates \
    -quiet \
    build

APP_DIR=$(xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS,id=$UDID" \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
APP="$APP_DIR/$SCHEME.app"

[[ -d "$APP" ]] || { echo "Build produced no app at $APP"; exit 1; }

# --- install ------------------------------------------------------------------
echo "==> Installing"
xcrun devicectl device install app --device "$UDID" "$APP" >/dev/null

if $LAUNCH; then
    echo "==> Launching"
    xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" >/dev/null
fi

echo "==> Done. Greenhouse is on $NAME."
