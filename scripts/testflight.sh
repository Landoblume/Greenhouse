#!/usr/bin/env bash
#
# Archive a Release build and upload it to App Store Connect for TestFlight.
#
#   scripts/testflight.sh
#
# Uses the Apple account signed in to Xcode (Settings > Accounts). The build
# shows up in App Store Connect > Greenhouse > TestFlight after Apple finishes
# processing it, usually 5-15 minutes, and installs from the TestFlight app.
#
# The build number is a timestamp, because App Store Connect rejects any build
# number it has already seen and this way nobody has to remember to bump it.

set -euo pipefail

cd "$(dirname "$0")/.."

BUILD=$(date +%Y%m%d%H%M)
ARCHIVE="archives/Greenhouse-$BUILD.xcarchive"

echo "==> Regenerating project"
xcodegen generate --quiet

echo "==> Archiving build $BUILD"
xcodebuild archive \
    -project Greenhouse.xcodeproj \
    -scheme Greenhouse \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    -quiet \
    CURRENT_PROJECT_VERSION="$BUILD"

echo "==> Uploading to App Store Connect"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "archives/export-$BUILD" \
    -allowProvisioningUpdates

echo "==> Uploaded build $BUILD. It appears in TestFlight once Apple finishes processing."
