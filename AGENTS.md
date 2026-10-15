# rima.Chat public source

Read README.md, BUILD.md and PUBLIC-SOURCE.json before changing this edition.

- Preserve upstream history, GPL notices, COPYING.iOS and pinned submodules/dependency locks.
- Preserve branding, chat layout, call actions and media behavior unless a task changes them.
- Never commit credentials, private signing/APNs keys, provisioning profiles, device containers or personal conversation data.
- Use an unsigned simulator for local source verification. Integration tests need a separately controlled test server.
- Source publication does not authorize production-service changes or release of an app binary.
- Regenerate the ignored source ZIP with scripts/prepare-corresponding-source.py before building.
- The workspace and scheme are NextcloudTalk; the app display name is rima.Chat.
