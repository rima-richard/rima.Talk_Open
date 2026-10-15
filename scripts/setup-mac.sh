#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
xcodebuild -version
/usr/bin/ruby -v
if [[ -e .git ]]; then
  git submodule update --init --recursive
elif [[ -f ThirdParty/SlackTextViewController/Source/SLKTextViewController.m && -d ThirdParty/DRCellSlideGestureRecognizer ]]; then
  printf 'Quellpaket ohne Git-Metadaten: eingebettete Submodule werden verwendet.\n'
else
  echo 'Submodulquellen fehlen. Repository mit --recurse-submodules klonen.' >&2
  exit 1
fi

# Local gems only. No sudo or changes to the system Ruby installation.
export GEM_HOME="${RIMA_GEM_HOME:-$repo_root/build/tools/gems}"
export GEM_PATH="$GEM_HOME"
export PATH="$GEM_HOME/bin:$PATH"
mkdir -p "$GEM_HOME"
if ! /usr/bin/gem list --local --exact bundler --version 2.4.22 --installed >/dev/null; then
  /usr/bin/gem install bundler --version 2.4.22 --no-document
fi
/usr/bin/ruby "$GEM_HOME/bin/bundle" _2.4.22_ config set --local path build/tools/bundle
/usr/bin/ruby "$GEM_HOME/bin/bundle" _2.4.22_ install
RUBYOPT="-rbundler/setup -rlogger${RUBYOPT:+ $RUBYOPT}" \
  /usr/bin/ruby "$GEM_HOME/bin/bundle" _2.4.22_ exec pod install --deployment
python3 scripts/prepare-corresponding-source.py
printf '\nAbhängigkeiten vorbereitet. Öffne NextcloudTalk.xcworkspace in Xcode.\n'
