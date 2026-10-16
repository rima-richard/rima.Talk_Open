# rima.Chat · iOS source

Corresponding application source for **rima.Chat 25.0.2 (15)**, the employee communication app of rima Pflege GmbH. The Xcode workspace and scheme retain the upstream name **NextcloudTalk**.

This edition includes rima branding, chat layout refinements, direct audio/video actions, the monochrome call screen, round contact images/initials, the wider hang-up button, HD video defaults and rima call tones. It is based on [Nextcloud Talk iOS v25.0.2](https://github.com/nextcloud/talk-ios/tree/0231f1c6b6ce51aa13dd9bde5008ae0839e1f8d1).

## Build

```sh
git clone --recurse-submodules https://github.com/rima-richard/rima.Talk_Open.git
cd rima.Talk_Open
./scripts/setup-mac.sh
open NextcloudTalk.xcworkspace
```

See [BUILD.md](BUILD.md) for requirements and an unsigned simulator build. CocoaPods, SwiftPM and submodule versions are pinned. Setup also generates the source ZIP required by the app's source-sharing action.

The published client configuration contains public service URLs and Apple bundle/team identifiers. Device signing requires your own authorized signing access. Running a separate deployment requires its own server and push service. No signing credentials, APNs private keys, review passwords or employee messages are included.

## Source edition

Use tag **rima-chat-25.0.2-15** for this application edition. [PUBLIC-SOURCE.json](PUBLIC-SOURCE.json) records the upstream revision and source-package hash from the verified signed Build 15 export. Application and test source match that development source. All 30 final Build 15 signaling/controller/layout tests passed; the preceding Build 14 security and regression run passed 69 tests. Build 15 retains those security fixes and adds bounded on-device diagnostics without changing media control or signaling validation. Foreground and locked-recipient audio/video calls, push with direct reply, and file sharing were accepted on both test iPhones. Network handover and long-term reliability are separate checks; the earlier Build 14 call failure cause remains unproven. The project differs only in equivalent CocoaPods formatting/empty-list normalization. Release documentation and build helpers are adapted for this standalone repository.

The public upstream history is retained. The separate internal development handoff commit, device reports, operational notes and local build outputs are outside this repository's published history. The original private development checkout is preserved separately.

## License and attribution

- [GNU GPL version 3 or later](LICENSE), with the original [Apple App Store exception](COPYING.iOS).
- [Authors](AUTHORS.md), [original project documentation](docs/UPSTREAM-README.md), and existing copyright/SPDX notices are retained.
- Pinned third-party source retains its own license and attribution files. Binary dependencies are identified by the checked-in dependency locks and their package/pod specifications.

## Contact

[rima.Chat support and content reports](https://rima-pflege.de/rima-chat) · [rima.Chat privacy information](https://rima-pflege.de/rima-chat/datenschutz).

The included [upstream security policy](SECURITY.md) describes Nextcloud's own reporting process. For issues specific to rima's modifications or service, use the rima support contact. Never include passwords, access tokens or personal conversation data in public issues.

<!-- SPDX-FileCopyrightText: 2026 rima Pflege GmbH -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
