# Building rima.Chat 25.0.2 (15)

This source edition retains the public upstream history and two original pinned submodules. Clone with `--recurse-submodules`.

## Requirements and setup

The original edition was built on macOS 27.0.1 (arm64), Xcode 27.0 (27A266a), iOS 27 SDK, system Ruby 2.6.10 and CocoaPods 1.16.2. The app deployment target is iOS 16.0. Install and select Xcode before setup.

Run `./scripts/setup-mac.sh`. It installs locked local Ruby/CocoaPods dependencies, prepares the submodules and generates `NextcloudTalk/Legal/rima.Chat-source.zip`. It does not install the app or upload to Apple. The script expects `/usr/bin/ruby`; adapt that invocation if your Mac does not provide it. Do not use `pod update` as a routine setup step.

Both SwiftPM lockfiles are checked in. Xcode may need to resolve/download those packages on the first build. Integration tests need their own local Nextcloud instance; the default rima service is an employee system.

## Unsigned simulator

```sh
xcodebuild -workspace NextcloudTalk.xcworkspace -scheme NextcloudTalk \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -packageAuthorizationProvider netrc \
  CODE_SIGNING_ALLOWED=NO build
```

After resolving the pins once, add `-disableAutomaticPackageResolution` if desired. Open `NextcloudTalk.xcworkspace` rather than only the project file in Xcode.

Unit/layout tests can use local synthetic fixtures. Upstream server integration tests require the documented test instance. A simulator build does not establish physical push, media or network-handover acceptance.

## Devices and Release

The checked-in identifiers, app group and signing team describe the rima edition. Signing certificates, profiles, server credentials and APNs provider keys are absent. Authorized rima development uses local signing access; a separate deployment needs its own identifiers, entitlements and backend/push configuration.

Release selects rima's production registration URL and retains a configuration guard. Debug selects the development URL. Public client URLs/identifiers are not authentication secrets. These instructions do not authorize operation of rima's services.

The ignored source ZIP is recreated from the pinned source. The included archive script defaults to Build 14 paths, exports locally and does not upload or submit an app. The signed Build 15 App Store export passed signature, production-push configuration and source-correspondence checks. The requested two-device calls/push/file-sharing acceptance passed; Version 25.0.2 (15) was submitted to App Review on 2026-10-16 and is waiting for review; manual release remains selected. This does not imply approval or publication. To label a new archive/export for this edition, set `RIMA_ARCHIVE_PATH` and `RIMA_EXPORT_PATH` to fresh Build 15 paths before running the helper. If Finder metadata in an iCloud-synced build folder blocks signing, set RIMA_DERIVED_DATA and RIMA_ARCHIVE_PATH to fresh local paths outside the synced folder.

Apple also acknowledged receipt of the Unlisted distribution request on 2026-10-16. Both App Review and Unlisted decisions remain pending; manual release is retained.

<!-- SPDX-FileCopyrightText: 2026 rima Pflege GmbH -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
