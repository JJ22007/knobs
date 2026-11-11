#!/bin/bash
# Set up a new Mac in one line:
#   curl -fsSL https://raw.githubusercontent.com/JJ22007/knobs/main/scripts/bootstrap.sh | bash -s -- <profile>
#
# <profile> is a preset name (snappy, developer, focus, presenter, jj22007), an https link to
# someone's *.knobs.json (a gist or a file in a repo), or a local file. Without it, Knobs is
# installed and nothing is changed.
#
# What it does: clones Knobs to ~/.local/share/knobs (or updates it), builds and installs it,
# shows what the profile would change, then applies it. Nothing needs sudo.
set -euo pipefail
PROFILE="${1:-}"
DIR="$HOME/.local/share/knobs"
REPO="https://github.com/JJ22007/knobs"

if ! xcrun --find swiftc >/dev/null 2>&1 && [ ! -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
    echo "Knobs is built from source and needs Apple's Command Line Tools."
    echo "Run: xcode-select --install   then run this command again."
    xcode-select --install 2>/dev/null || true
    exit 1
fi

if [ -d "$DIR/.git" ]; then
    git -C "$DIR" pull -q --ff-only
else
    mkdir -p "$(dirname "$DIR")"
    git clone -q --depth 1 "$REPO" "$DIR"
fi
KNOBS_BACKGROUND=1 bash "$DIR/build.sh" install

K="$HOME/.local/bin/knobs"
if [ -n "$PROFILE" ]; then
    echo
    "$K" apply "$PROFILE" --dry-run
    echo
    "$K" apply "$PROFILE"
fi
echo
echo "Done. Open the window with: $K open"
