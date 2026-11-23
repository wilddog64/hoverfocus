#!/usr/bin/env bash
set -euo pipefail

# Build the bundle first
make bundle

# Create scratch root
root=$(mktemp -d)
snapshot_file=$(mktemp)
current_file=$(mktemp)
trap 'rm -rf "$root" "$snapshot_file" "$current_file"' EXIT

touch "$root/HF_TEST_ROOT"
mkdir -p "$root/home" "$root/bin"
export HOME="$root/home"
APPDIR="$root/home/Applications"
AGENTDIR="$root/home/Library/LaunchAgents"
mkdir -p "$APPDIR" "$AGENTDIR"

# Stub launchctl in $root/bin
cat << 'EOF' > "$root/bin/launchctl"
#!/usr/bin/env bash
if [ ! -f "$root/HF_TEST_ROOT" ]; then
    exit 97
fi
echo "$@" >> "$root/launchctl.log"
exit 0
EOF
sed -i '' "s|\$root|$root|g" "$root/bin/launchctl"
chmod +x "$root/bin/launchctl"
LAUNCHCTL="$root/bin/launchctl"
export PATH="$root/bin:$PATH"

# Assert HOME is under $root
[[ "$HOME" == "$root"* ]] || { echo "HOME is not under root" >&2; exit 1; }

# Snapshot path list under $root (excluding launchctl.log)
find "$root" ! -name "launchctl.log" | sort > "$snapshot_file"

# Run make install twice
make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME"
make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME"

# Check bundle and plist exist after install
[ -d "$APPDIR/HoverFocus.app" ] || { echo "Bundle missing after install" >&2; exit 1; }
[ -f "$AGENTDIR/com.wilddog64.hoverfocus.plist" ] || { echo "Plist missing after install" >&2; exit 1; }

# Check plist has LimitLoadToSessionType Aqua
session_type=$(plutil -extract LimitLoadToSessionType raw "$AGENTDIR/com.wilddog64.hoverfocus.plist")
if [ "$session_type" != "Aqua" ]; then
    echo "LimitLoadToSessionType is not Aqua: $session_type" >&2
    exit 1
fi

# Check log holds bootout before each bootstrap
uid=$(id -u)
expected_bootout="bootout gui/$uid/com.wilddog64.hoverfocus"
expected_bootstrap="bootstrap gui/$uid $AGENTDIR/com.wilddog64.hoverfocus.plist"

log_line1=$(sed -n '1p' "$root/launchctl.log")
log_line2=$(sed -n '2p' "$root/launchctl.log")
log_line3=$(sed -n '3p' "$root/launchctl.log")
log_line4=$(sed -n '4p' "$root/launchctl.log")

if [ "$log_line1" != "$expected_bootout" ] || [ "$log_line2" != "$expected_bootstrap" ] || \
   [ "$log_line3" != "$expected_bootout" ] || [ "$log_line4" != "$expected_bootstrap" ]; then
    echo "Unexpected launchctl log before uninstall: $(< "$root/launchctl.log")" >&2
    exit 1
fi

# Run make uninstall
make uninstall APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME"

# Check log has bootout for uninstall (5th line)
log_line5=$(sed -n '5p' "$root/launchctl.log")
if [ "$log_line5" != "$expected_bootout" ]; then
    echo "Uninstall did not log expected bootout: $log_line5" >&2
    exit 1
fi

# Check bundle and plist are gone
[ ! -e "$APPDIR/HoverFocus.app" ] || { echo "Bundle still exists after uninstall" >&2; exit 1; }
[ ! -e "$AGENTDIR/com.wilddog64.hoverfocus.plist" ] || { echo "Plist still exists after uninstall" >&2; exit 1; }

# Path list equals the snapshot
find "$root" ! -name "launchctl.log" | sort > "$current_file"
if ! cmp -s "$snapshot_file" "$current_file"; then
    echo "Path list differs from snapshot after uninstall:" >&2
    diff "$snapshot_file" "$current_file" >&2 || true
    exit 1
fi

# make install APPDIR= exits non-zero and changes nothing
snapshot_before=$(find "$root" | sort)
refusal_err=$(mktemp)
if make install APPDIR="" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" 2>"$refusal_err"; then
    echo "make install APPDIR= unexpectedly succeeded" >&2
    rm -f "$refusal_err"
    exit 1
fi
if ! grep -q "APPDIR and AGENTDIR must not be empty" "$refusal_err"; then
    echo "make install APPDIR= failed without refusal guard: $(< "$refusal_err")" >&2
    rm -f "$refusal_err"
    exit 1
fi
rm -f "$refusal_err"
snapshot_after=$(find "$root" | sort)
if [ "$snapshot_before" != "$snapshot_after" ]; then
    echo "make install APPDIR= changed paths" >&2
    exit 1
fi

# Check Info.plist keys
info_plist="build/HoverFocus.app/Contents/Info.plist"
[ "$(plutil -extract CFBundleIdentifier raw "$info_plist")" = "com.wilddog64.hoverfocus" ]
[ "$(plutil -extract CFBundleExecutable raw "$info_plist")" = "hoverfocus" ]
[ "$(plutil -extract CFBundleIconFile raw "$info_plist")" = "AppIcon" ]
[ "$(plutil -extract LSUIElement raw "$info_plist")" = "true" ] || [ "$(plutil -extract LSUIElement raw "$info_plist")" = "1" ]
[ "$(plutil -extract CFBundleShortVersionString raw "$info_plist")" = "0.1.0" ]
[ "$(plutil -extract LSMinimumSystemVersion raw "$info_plist")" = "14.0" ]

# Check AppIcon.icns exists
[ -f "build/HoverFocus.app/Contents/Resources/AppIcon.icns" ]

# Check codesign passes
codesign -v build/HoverFocus.app

echo "install_test passed"
