#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."

# Only archives and exports locally. Never uploads or submits for review.
RIMA_ARCHIVE_PATH="${RIMA_ARCHIVE_PATH:-$PWD/build/AppStore/rima.Chat-25.0.2-14.xcarchive}"
RIMA_EXPORT_PATH="${RIMA_EXPORT_PATH:-$PWD/build/AppStore/export-14}"
RIMA_DERIVED_DATA="${RIMA_DERIVED_DATA:-$PWD/build/StoreDerivedData}"
RIMA_PACKAGES="${RIMA_PACKAGES:-$PWD/build/SourcePackages}"
mkdir -p "$PWD/build/AppStore"
if [[ -e "$RIMA_ARCHIVE_PATH" || -e "$RIMA_EXPORT_PATH" ]]; then
  echo "Archive/export path already exists; choose new paths to preserve earlier artifacts." >&2
  exit 1
fi
python3 scripts/prepare-corresponding-source.py
xcodebuild -workspace NextcloudTalk.xcworkspace -scheme NextcloudTalk \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$RIMA_DERIVED_DATA" -clonedSourcePackagesDirPath "$RIMA_PACKAGES" \
  -packageAuthorizationProvider netrc -disableAutomaticPackageResolution \
  -allowProvisioningUpdates -archivePath "$RIMA_ARCHIVE_PATH" archive
xcodebuild -exportArchive -archivePath "$RIMA_ARCHIVE_PATH" \
  -exportOptionsPlist docs/rima/app-store/ExportOptions.plist \
  -exportPath "$RIMA_EXPORT_PATH" -allowProvisioningUpdates
