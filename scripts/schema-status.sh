#!/usr/bin/env bash
#
# Waits for the debug build on the phone to upload the CloudKit schema, after a
# model change and `./install.sh --launch`.
#
#   scripts/schema-status.sh            # wait until the upload is newer than now
#   scripts/schema-status.sh --once     # just print the last upload
#
# The debug build uploads the Development schema whenever
# GreenhouseModel.fingerprint changes, and records the result in its prefs.
# This reads those prefs off the phone. Once it reports a new upload, deploy
# Development to Production in the CloudKit Console before anyone installs
# the TestFlight build, or the new fields won't sync.

set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_JSON=$(mktemp)
WORK=$(mktemp -d)
trap 'rm -rf "$DEVICE_JSON" "$WORK"' EXIT
xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null 2>&1

# Same pick as install.sh: the first paired iPhone.
UDID=$(python3 -c "
import json
d = json.load(open('$DEVICE_JSON'))
for dev in d.get('result', {}).get('devices', []):
    conn = dev.get('connectionProperties', {})
    if conn.get('tunnelState') != 'unavailable' or conn.get('pairingState') == 'paired':
        print(dev.get('hardwareProperties', {}).get('udid') or dev['identifier'])
        break
" 2>/dev/null || true)

if [[ -z "$UDID" ]]; then
    echo "No paired iPhone found. Plug it in and unlock it."
    exit 1
fi

read_status() {
    xcrun devicectl device copy from --device "$UDID" \
        --domain-type appDataContainer --domain-identifier com.landenblume.greenhouse \
        --source Library/Preferences/com.landenblume.greenhouse.plist \
        --destination "$WORK/prefs.plist" >/dev/null 2>&1 || return 1
    STATUS=$(plutil -extract cloudKitSchemaStatus raw "$WORK/prefs.plist" 2>/dev/null || echo "none yet")
    FINGERPRINT=$(plutil -extract cloudKitSchemaFingerprint raw "$WORK/prefs.plist" 2>/dev/null || echo "none")
}

if [[ "${1:-}" == "--once" ]]; then
    read_status || { echo "Couldn't read the app's prefs (is the debug build installed?)"; exit 1; }
    echo "$STATUS | $FINGERPRINT"
    exit 0
fi

read_status || true
BEFORE=${FINGERPRINT:-none}
echo "==> Waiting for a new schema upload (last: ${STATUS:-none} | $BEFORE)"
echo "    Keep the phone unlocked with Greenhouse open."
for _ in $(seq 1 36); do
    sleep 10
    read_status || continue
    if [[ "$FINGERPRINT" != "$BEFORE" && "$FINGERPRINT" != "none" ]]; then
        echo "==> Uploaded: $STATUS | $FINGERPRINT"
        echo "    Next: CloudKit Console > Deploy Schema Changes to Production."
        exit 0
    fi
done
echo "No new upload after 6 minutes (last: ${STATUS:-none} | $FINGERPRINT)."
echo "Is the phone unlocked and the app open? If the model didn't change, there's nothing to upload."
exit 1
