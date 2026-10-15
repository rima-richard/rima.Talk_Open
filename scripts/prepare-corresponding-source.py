#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Bundle current source and pinned submodules, without Git history or local data."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'NextcloudTalk/Legal/rima.Chat-source.zip'

def git(*args, cwd=ROOT):
    return subprocess.check_output(['git', *args], cwd=cwd)

def paths():
    for row in git('ls-files', '--stage', '-z').split(b'\0'):
        if not row:
            continue
        meta, name = row.split(b'\t', 1)
        mode, sha, stage = meta.decode().split()
        assert stage == '0', 'Resolve source conflicts before packaging'
        name = name.decode()
        if mode == '160000':
            sub = ROOT / name
            assert git('rev-parse', 'HEAD', cwd=sub).decode().strip() == sha
            assert not git('status', '--porcelain', cwd=sub).strip()
            for child in git('ls-files', '-z', cwd=sub).split(b'\0'):
                if child:
                    yield name + '/' + child.decode()
        else:
            yield name
    for name in git('ls-files', '--others', '--exclude-standard', '-z').split(b'\0'):
        if name:
            yield name.decode()

def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    entries = []
    prefix = 'rima.Chat-source/'
    with zipfile.ZipFile(OUTPUT, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in sorted(set(paths())):
            # Store marketing/handoff records and local evidence are not needed to build.
            included_docs = {'docs/rima/app-store/ExportOptions.plist',
                             'docs/rima/CALL-SOUNDS-PROVENANCE.json',
                             'docs/rima/CALLKIT-ICON-PROVENANCE.json'}
            if (name.startswith(('docs/rima/', '.github/', 'ThirdParty/SlackTextViewController/Examples/Pods/')) and name not in included_docs) or name == 'START-MACBOOK.md':
                continue
            path = ROOT / name
            assert path.resolve() != OUTPUT.resolve(), 'Generated archive must be ignored by Git'
            assert not path.is_symlink(), 'Review symlinks before distributing source'
            assert not any(part in {'.git', '.aws', '.codex', '.agents', 'build', 'Pods', 'xcuserdata'} for part in Path(name).parts)
            assert path.suffix.lower() not in {'.p8', '.p12', '.mobileprovision', '.provisionprofile', '.key', '.pem', '.ipa', '.xcresult'}
            data = path.read_bytes()
            archive.write(path, prefix + name)
            entries.append({'path': name, 'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data)})
        manifest = {'base_commit': git('rev-parse', 'HEAD').decode().strip(),
                    'state': 'Current working source, including pinned submodule source. Not a Git history export.',
                    'files': entries}
        archive.writestr(prefix + 'CORRESPONDING-SOURCE.json', json.dumps(manifest, ensure_ascii=False, indent=2))
        archive.writestr(prefix + 'BUILD-SOURCE.txt',
                        'rima.Chat iOS corresponding application source\n\n'
                        'License: LICENSE (GPL-3.0-or-later), COPYING.iOS and original third-party notices.\n'
                        'Pinned submodule contents are included directly; no Git metadata or credentials.\n'
                        'Install Xcode, then run scripts/setup-mac.sh to obtain locked CocoaPods dependencies.\n'
                        'Open NextcloudTalk.xcworkspace and resolve the checked-in SwiftPM pins.\n'
                        'Use Debug / iOS Simulator / CODE_SIGNING_ALLOWED=NO for a local unsigned build.\n'
                        'Apple signing and a separately configured push service are needed for device distribution.\n'
                        'Binary dependencies remain at the versions recorded by the package/Pod locks; '
                        'their original licenses and source references remain applicable.\n'
                        'Historical handoff snapshots, store marketing assets and local build data are omitted.\n')
    print(f'Prepared corresponding source: {len(entries)} files, {OUTPUT.stat().st_size} bytes')

if __name__ == '__main__':
    main()
