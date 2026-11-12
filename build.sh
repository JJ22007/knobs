#!/bin/bash
# Build Knobs.app.
#   bash build.sh            compile to build/Knobs.app and run the self-test
#   bash build.sh install    also copy it to ~/Applications, link the `knobs` command and launch
#
# Signing, in order of preference:
#   1. SIGN_ID="Developer ID Application: You" bash build.sh install
#   2. the local identity created by scripts/setup-signing.sh (used automatically)
#   3. ad-hoc. Works, but macOS forgets the Accessibility grant on every rebuild.
set -euo pipefail
cd "$(dirname "$0")"

# A freshly installed Xcode refuses to run until its licence is accepted (sudo). The Command
# Line Tools need no licence step, so fall back to them instead of failing.
if ! swiftc --version >/dev/null 2>&1 && [ -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

APP="build/Knobs.app"
BIN="$APP/Contents/MacOS/Knobs"
rm -rf "$APP" build/obj
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj
cp -R Resources/icons "$APP/Contents/Resources/icons"
cp -R presets "$APP/Contents/Resources/presets"

# The vendored C library that posts the synthetic swipe (see Vendor/ISS/LICENSE).
for f in Vendor/ISS/*.c; do
    clang -O2 -w -c "$f" -o "build/obj/$(basename "$f" .c).o"
done
swiftc -O -swift-version 5 -import-objc-header Sources/Bridging.h Sources/*.swift build/obj/*.o \
    -framework IOKit -framework ServiceManagement -o "$BIN"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.knobs</string>
    <key>CFBundleName</key><string>Knobs</string>
    <key>CFBundleDisplayName</key><string>Knobs</string>
    <key>CFBundleExecutable</key><string>Knobs</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

IDENTITY="${SIGN_ID:-}"
if [[ -z "$IDENTITY" ]]; then
    for candidate in "Knobs Local Signing" "Paneful Local Signing"; do
        if security find-identity -p codesigning 2>/dev/null | grep -q "\"$candidate\""; then IDENTITY="$candidate"; break; fi
    done
fi
if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" ${SIGN_KEYCHAIN:+--keychain "$SIGN_KEYCHAIN"} "$APP"
    echo "signed with: $IDENTITY"
else
    codesign --force --sign - "$APP" 2>/dev/null
    echo "signed ad-hoc (run scripts/setup-signing.sh once to keep the Accessibility grant across rebuilds)"
fi

"$BIN" --selftest | grep -v '^ok' || true
"$BIN" --selftest >/dev/null || { echo "self-test failed"; exit 1; }
for f in presets/*.json examples/*.json; do "$BIN" apply "$f" --dry-run >/dev/null || { echo "bad preset: $f"; exit 1; }; done

if [[ "${1:-}" == "install" ]]; then
    DEST="$HOME/Applications/Knobs.app"
    pkill -x Knobs 2>/dev/null || true
    mkdir -p "$HOME/Applications" "$HOME/.local/bin"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    ln -sf "$DEST/Contents/MacOS/Knobs" "$HOME/.local/bin/knobs"
    open "$DEST" ${KNOBS_BACKGROUND:+--args --background}
    echo "installed and launched: $DEST"
    # Claude Code finds knobs in any folder through a user-level skill. Nothing is written to ~/.claude without
    # a yes: KNOBS_SKILL=1 says yes, KNOBS_SKILL=0 says no, otherwise ask on the terminal. A skill that is
    # already installed is kept up to date, since the user said yes to it before.
    SKILL_FILE="$HOME/.claude/skills/knobs/SKILL.md"
    if [ -d "$HOME/.claude" ] && [ "${KNOBS_SKILL:-}" != "0" ] && [ -z "${KNOBS_NO_SKILL:-}" ]; then
        ANSWER="${KNOBS_SKILL:-}"
        if [ -f "$SKILL_FILE" ]; then
            ANSWER=1
        elif [ -z "$ANSWER" ] && { exec 3<>/dev/tty; } 2>/dev/null; then
            printf "Add a Claude Code skill at ~/.claude/skills/knobs so Claude Code can use knobs in any folder? [y/N] " >&3
            read -r REPLY <&3 || REPLY=""
            exec 3<&-
            case "$REPLY" in [yY]*) ANSWER=1 ;; esac
        fi
        if [ "$ANSWER" = "1" ]; then
            "$DEST/Contents/MacOS/Knobs" skill install
        else
            echo "Claude Code skill not installed. Add it any time with: ~/.local/bin/knobs skill install"
        fi
    fi
    echo "command line: ~/.local/bin/knobs (add ~/.local/bin to your PATH to type just \`knobs\`)"
fi
