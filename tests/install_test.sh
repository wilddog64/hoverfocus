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
# m4-air, macOS 26.5.2, 2026-11-23: print of a missing service rc 113; managername over SSH prints Background
cat << 'EOF' > "$root/bin/launchctl"
#!/usr/bin/env bash
# m4-air, macOS 26.5.2, 2026-11-23: print of a missing service rc 113; managername over SSH prints Background
root="__ROOT__"
if [ ! -f "$root/HF_TEST_ROOT" ]; then
    exit 97
fi
echo "$@" >> "$root/launchctl.log"

cmd="${1:-}"
case "$cmd" in
    managername)
        if [ -f "$root/managername" ]; then
            cat "$root/managername"
        else
            echo "Aqua"
        fi
        exit 0
        ;;
    print)
        loaded=0
        if [ -f "$root/print_loaded" ]; then
            loaded=$(cat "$root/print_loaded")
        fi
        if [ "$loaded" -gt 0 ]; then
            echo $((loaded - 1)) > "$root/print_loaded"
            exit 0
        else
            exit 113
        fi
        ;;
    *)
        exit 0
        ;;
esac
EOF
sed -i '' "s|__ROOT__|$root|g" "$root/bin/launchctl"
chmod +x "$root/bin/launchctl"
LAUNCHCTL="$root/bin/launchctl"

# Stub sudo in $root/bin (first on PATH)
cat << 'EOF' > "$root/bin/sudo"
#!/usr/bin/env bash
root="__ROOT__"
echo "$@" >> "$root/sudo.log"
exit 97
EOF
sed -i '' "s|__ROOT__|$root|g" "$root/bin/sudo"
chmod +x "$root/bin/sudo"

export PATH="$root/bin:$PATH"

# Assert HOME is under $root
[[ "$HOME" == "$root"* ]] || { echo "HOME is not under root" >&2; exit 1; }

assert_no_sudo() {
    if [ -f "$root/sudo.log" ] && [ -s "$root/sudo.log" ]; then
        echo "Unexpected sudo call logged: $(< "$root/sudo.log")" >&2
        exit 1
    fi
}

reset_scratch() {
    rm -rf "${root:?}/home" "$root/launchctl.log" "$root/sudo.log"
    mkdir -p "$root/home"
    export HOME="$root/home"
    APPDIR="$root/home/Applications"
    AGENTDIR="$root/home/Library/LaunchAgents"
    mkdir -p "$APPDIR" "$AGENTDIR"
    echo "Aqua" > "$root/managername"
    echo "0" > "$root/print_loaded"
}

uid=$(id -u)
expected_bootout="bootout gui/$uid/com.wilddog64.hoverfocus"
expected_print="print gui/$uid/com.wilddog64.hoverfocus"
expected_bootstrap="bootstrap gui/$uid $AGENTDIR/com.wilddog64.hoverfocus.plist"

# ==============================================================================
# Case 1: Default path (v0.0.1 checks + plutil extracts + log order checks)
# ==============================================================================
reset_scratch

# Snapshot path list under $root (excluding launchctl.log and sudo.log)
find "$root" ! -name "launchctl.log" ! -name "sudo.log" | sort > "$snapshot_file"

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

# Check ProgramArguments count and exact binary path
plutil -lint "$AGENTDIR/com.wilddog64.hoverfocus.plist"
[ "$(plutil -extract ProgramArguments raw "$AGENTDIR/com.wilddog64.hoverfocus.plist")" = "1" ]
[ "$(plutil -extract ProgramArguments.0 raw "$AGENTDIR/com.wilddog64.hoverfocus.plist")" = "$APPDIR/HoverFocus.app/Contents/MacOS/hoverfocus" ]
[ "$(grep -c __PROGRAM__ "$AGENTDIR/com.wilddog64.hoverfocus.plist")" -eq 0 ]

# Check log holds bootout/print/bootstrap before each subsequent operation
filtered_log=$(grep -v '^managername' "$root/launchctl.log")
line1=$(echo "$filtered_log" | sed -n '1p')
line2=$(echo "$filtered_log" | sed -n '2p')
line3=$(echo "$filtered_log" | sed -n '3p')
line4=$(echo "$filtered_log" | sed -n '4p')
line5=$(echo "$filtered_log" | sed -n '5p')
line6=$(echo "$filtered_log" | sed -n '6p')
line7=$(echo "$filtered_log" | sed -n '7p')

if [ "$line1" != "$expected_bootout" ] || [ "$line2" != "$expected_print" ] || [ "$line3" != "$expected_bootstrap" ] || \
   [ "$line4" != "$expected_bootout" ] || [ "$line5" != "$expected_print" ] || [ "$line6" != "$expected_bootstrap" ] || \
   [ -n "$line7" ]; then
    echo "Unexpected launchctl log before uninstall: $(< "$root/launchctl.log")" >&2
    exit 1
fi

assert_no_sudo

# Run make uninstall
make uninstall APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME"

# Check log has bootout for uninstall
filtered_log=$(grep -v '^managername' "$root/launchctl.log")
line7=$(echo "$filtered_log" | sed -n '7p')
line8=$(echo "$filtered_log" | sed -n '8p')
if [ "$line7" != "$expected_bootout" ] || [ -n "$line8" ]; then
    echo "Uninstall did not log expected bootout: $(< "$root/launchctl.log")" >&2
    exit 1
fi

# Check bundle and plist are gone
[ ! -e "$APPDIR/HoverFocus.app" ] || { echo "Bundle still exists after uninstall" >&2; exit 1; }
[ ! -e "$AGENTDIR/com.wilddog64.hoverfocus.plist" ] || { echo "Plist still exists after uninstall" >&2; exit 1; }

# Path list equals the snapshot
find "$root" ! -name "launchctl.log" ! -name "sudo.log" | sort > "$current_file"
if ! cmp -s "$snapshot_file" "$current_file"; then
    echo "Path list differs from snapshot after uninstall:" >&2
    diff "$snapshot_file" "$current_file" >&2 || true
    exit 1
fi

assert_no_sudo

# ==============================================================================
# Case 2: wait (print_loaded=3 -> 1 bootout, 4 prints, 1 bootstrap)
# ==============================================================================
reset_scratch
echo "3" > "$root/print_loaded"

make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME"
assert_no_sudo

wait_log=$(grep -v '^managername' "$root/launchctl.log")
w_line1=$(echo "$wait_log" | sed -n '1p')
w_line2=$(echo "$wait_log" | sed -n '2p')
w_line3=$(echo "$wait_log" | sed -n '3p')
w_line4=$(echo "$wait_log" | sed -n '4p')
w_line5=$(echo "$wait_log" | sed -n '5p')
w_line6=$(echo "$wait_log" | sed -n '6p')
w_line7=$(echo "$wait_log" | sed -n '7p')

if [ "$w_line1" != "$expected_bootout" ] || \
   [ "$w_line2" != "$expected_print" ] || \
   [ "$w_line3" != "$expected_print" ] || \
   [ "$w_line4" != "$expected_print" ] || \
   [ "$w_line5" != "$expected_print" ] || \
   [ "$w_line6" != "$expected_bootstrap" ] || \
   [ -n "$w_line7" ]; then
    echo "Wait case unexpected launchctl log: $(< "$root/launchctl.log")" >&2
    exit 1
fi

# ==============================================================================
# Case 3: timeout (print_loaded=1000, BOOTOUT_WAIT_TRIES=3 -> fail, no bootstrap)
# ==============================================================================
reset_scratch
echo "1000" > "$root/print_loaded"
timeout_err=$(mktemp)

if make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" BOOTOUT_WAIT_TRIES=3 2>"$timeout_err"; then
    echo "make install unexpectedly succeeded during timeout test" >&2
    rm -f "$timeout_err"
    exit 1
fi
if ! grep -q "still loaded" "$timeout_err"; then
    echo "Expected 'still loaded' in stderr: $(< "$timeout_err")" >&2
    rm -f "$timeout_err"
    exit 1
fi
rm -f "$timeout_err"

if grep -q "^bootstrap" "$root/launchctl.log"; then
    echo "Unexpected bootstrap in launchctl.log after timeout" >&2
    exit 1
fi
assert_no_sudo

# ==============================================================================
# Case 4: SSH session (managername=Background)
# ==============================================================================
reset_scratch
echo "Background" > "$root/managername"
find "$root" ! -name "launchctl.log" ! -name "sudo.log" | sort > "$snapshot_file"

ssh_err=$(mktemp)
make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" 2>"$ssh_err"

[ -d "$APPDIR/HoverFocus.app" ] || { echo "Bundle missing after SSH install" >&2; exit 1; }
[ -f "$AGENTDIR/com.wilddog64.hoverfocus.plist" ] || { echo "Plist missing after SSH install" >&2; exit 1; }

if grep -q "^bootout" "$root/launchctl.log" 2>/dev/null || grep -q "^bootstrap" "$root/launchctl.log" 2>/dev/null; then
    echo "Unexpected bootout or bootstrap in launchctl.log during SSH install" >&2
    exit 1
fi

expected_ssh_bootstrap="sudo launchctl asuser $uid launchctl bootstrap gui/$uid '$AGENTDIR/com.wilddog64.hoverfocus.plist'"
if ! grep -Fq "$expected_ssh_bootstrap" "$ssh_err"; then
    echo "Expected asuser bootstrap line in stderr: $(< "$ssh_err")" >&2
    rm -f "$ssh_err"
    exit 1
fi
rm -f "$ssh_err"
assert_no_sudo

ssh_uninst_err=$(mktemp)
make uninstall APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" 2>"$ssh_uninst_err"

[ ! -e "$APPDIR/HoverFocus.app" ] || { echo "Bundle still exists after SSH uninstall" >&2; exit 1; }
[ ! -e "$AGENTDIR/com.wilddog64.hoverfocus.plist" ] || { echo "Plist still exists after SSH uninstall" >&2; exit 1; }

if grep -q "^bootout" "$root/launchctl.log" 2>/dev/null; then
    echo "Unexpected bootout in launchctl.log during SSH uninstall" >&2
    exit 1
fi

expected_ssh_bootout="sudo launchctl asuser $uid launchctl bootout gui/$uid/com.wilddog64.hoverfocus"
if ! grep -Fq "$expected_ssh_bootout" "$ssh_uninst_err"; then
    echo "Expected asuser bootout line in stderr: $(< "$ssh_uninst_err")" >&2
    rm -f "$ssh_uninst_err"
    exit 1
fi
rm -f "$ssh_uninst_err"
assert_no_sudo

# ==============================================================================
# Case 5: odd path (APPDIR with space, &, |, <, >, ')
# ==============================================================================
reset_scratch
odd_appdir="$root/home/Apps & Co|x <y> 'z'"
mkdir -p "$odd_appdir"
find "$root" ! -name "launchctl.log" ! -name "sudo.log" | sort > "$snapshot_file"

make install APPDIR="$odd_appdir" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME"
plutil -lint "$AGENTDIR/com.wilddog64.hoverfocus.plist"
[ "$(plutil -extract ProgramArguments raw "$AGENTDIR/com.wilddog64.hoverfocus.plist")" = "1" ]
[ "$(plutil -extract ProgramArguments.0 raw "$AGENTDIR/com.wilddog64.hoverfocus.plist")" = "$odd_appdir/HoverFocus.app/Contents/MacOS/hoverfocus" ]
[ "$(grep -c __PROGRAM__ "$AGENTDIR/com.wilddog64.hoverfocus.plist")" -eq 0 ]
[ -d "$odd_appdir/HoverFocus.app" ] || { echo "Bundle missing after odd path install" >&2; exit 1; }
assert_no_sudo

make uninstall APPDIR="$odd_appdir" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME"
[ ! -e "$odd_appdir/HoverFocus.app" ] || { echo "Bundle still exists after odd path uninstall" >&2; exit 1; }
[ ! -e "$AGENTDIR/com.wilddog64.hoverfocus.plist" ] || { echo "Plist still exists after odd path uninstall" >&2; exit 1; }
assert_no_sudo

find "$root" ! -name "launchctl.log" ! -name "sudo.log" | sort > "$current_file"
if ! cmp -s "$snapshot_file" "$current_file"; then
    echo "Path list differs from snapshot after odd path uninstall:" >&2
    diff "$snapshot_file" "$current_file" >&2 || true
    exit 1
fi

# ==============================================================================
# Case 6: hint (CODESIGN_IDENTITY=-)
# ==============================================================================
reset_scratch
hint_out=$(mktemp)
make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" CODESIGN_IDENTITY="-" >"$hint_out"
if ! grep -Fq "tccutil reset Accessibility com.wilddog64.hoverfocus" "$hint_out"; then
    echo "Expected hint in install output: $(< "$hint_out")" >&2
    rm -f "$hint_out"
    exit 1
fi
rm -f "$hint_out"
assert_no_sudo

# ==============================================================================
# Regression checks from v0.0.1
# ==============================================================================
# make install APPDIR= exits non-zero and changes nothing
reset_scratch
snapshot_before=$(find "$root" ! -name "launchctl.log" ! -name "sudo.log" | sort)
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
snapshot_after=$(find "$root" ! -name "launchctl.log" ! -name "sudo.log" | sort)
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
