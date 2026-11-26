#!/usr/bin/env bash
set -euo pipefail
unset CODESIGN_IDENTITY SIGNING_NAME

# Build the bundle first (ad-hoc) and verify with real codesign
make bundle CODESIGN_IDENTITY=-
/usr/bin/codesign -v build/HoverFocus.app

# Create scratch root
root=$(mktemp -d)
snapshot_file=$(mktemp)
current_file=$(mktemp)
trap 'rm -rf "$root" "$snapshot_file" "$current_file"' EXIT

touch "$root/HF_TEST_ROOT"
mkdir -p "$root/home" "$root/bin" "$root/stubs"
export HOME="$root/home"
APPDIR="$root/home/Applications"
AGENTDIR="$root/home/Library/LaunchAgents"
mkdir -p "$APPDIR" "$AGENTDIR"

CODESIGN="$root/stubs/codesign"
OPENSSL="$root/stubs/openssl"
export CODESIGN OPENSSL

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
if [ ! -f "$root/HF_TEST_ROOT" ]; then
    exit 97
fi
echo "$@" >> "$root/sudo.log"
exit 97
EOF
sed -i '' "s|__ROOT__|$root|g" "$root/bin/sudo"
chmod +x "$root/bin/sudo"

# Stub security in $root/bin (on PATH)
cat << 'EOF' > "$root/bin/security"
#!/usr/bin/env bash
root="__ROOT__"
if [ ! -f "$root/HF_TEST_ROOT" ]; then
    exit 97
fi

redact_next=0
for arg in "$@"; do
    if [ "$redact_next" -eq 1 ]; then
        if [ -z "$arg" ]; then
            echo "security stub: empty password after -P" >&2
            exit 1
        fi
        echo "<redacted>" >> "$root/security.log"
        redact_next=0
    else
        echo "<$arg>" >> "$root/security.log"
        if [ "$arg" = "-P" ]; then
            redact_next=1
        fi
    fi
done

cmd="${1:-}"
case "$cmd" in
    find-certificate)
        if [ -f "$root/security.state" ] && [ "$(cat "$root/security.state")" != "absent" ]; then
            exit 0
        else
            exit 1
        fi
        ;;
    find-identity)
        has_v=0
        for a in "$@"; do
            if [ "$a" = "-v" ]; then
                has_v=1
            fi
        done
        if [ "$has_v" -eq 1 ]; then
            exit 0
        fi
        if [ -f "$root/security.state" ] && [ "$(cat "$root/security.state")" = "present" ]; then
            echo '  1) 1234567890abcdef1234567890abcdef12345678 "HoverFocus Local Signing" (CSSMERR_TP_NOT_TRUSTED)'
        fi
        exit 0
        ;;
    import)
        if [ ! -f "$root/security.import-noop" ]; then
            echo "present" > "$root/security.state"
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
sed -i '' "s|__ROOT__|$root|g" "$root/bin/security"
chmod +x "$root/bin/security"

# Stub codesign in $root/stubs (not on PATH)
cat << 'EOF' > "$root/stubs/codesign"
#!/usr/bin/env bash
root="__ROOT__"
if [ ! -f "$root/HF_TEST_ROOT" ]; then
    exit 97
fi
for arg in "$@"; do
    echo "<$arg>" >> "$root/codesign.log"
done
sign_value=""
want_sign_value=0
for arg in "$@"; do
    if [ "$want_sign_value" -eq 1 ]; then
        sign_value="$arg"
        want_sign_value=0
    elif [ "$arg" = "--sign" ]; then
        want_sign_value=1
    fi
done
if [ -f "$root/codesign.fail-any" ] || { [ -f "$root/codesign.fail" ] && [ "$sign_value" != "-" ]; }; then
    exit 1
fi
exit 0
EOF
sed -i '' "s|__ROOT__|$root|g" "$root/stubs/codesign"
chmod +x "$root/stubs/codesign"

# Stub openssl in $root/stubs (not on PATH)
cat << 'EOF' > "$root/stubs/openssl"
#!/usr/bin/env bash
root="__ROOT__"
if [ ! -f "$root/HF_TEST_ROOT" ]; then
    exit 97
fi
for arg in "$@"; do
    echo "<$arg>" >> "$root/openssl.log"
done

cmd="${1:-}"
case "$cmd" in
    rand)
        echo "STUB_P12_SECRET"
        exit 0
        ;;
    req)
        config_file=""
        keyout_file=""
        out_file=""
        prev=""
        for a in "$@"; do
            if [ "$prev" = "-config" ]; then
                config_file="$a"
            elif [ "$prev" = "-keyout" ]; then
                keyout_file="$a"
            elif [ "$prev" = "-out" ]; then
                out_file="$a"
            fi
            prev="$a"
        done
        if [ -n "$config_file" ] && [ -f "$config_file" ]; then
            cp "$config_file" "$root/req.cnf.seen"
            cfg_dir=$(dirname "$config_file")
            if /usr/bin/stat -f "%Lp" "$cfg_dir" >/dev/null 2>&1; then
                /usr/bin/stat -f "%Lp" "$cfg_dir" > "$root/req_dir_mode"
            else
                stat -c "%a" "$cfg_dir" > "$root/req_dir_mode"
            fi
        fi
        if [ -n "$keyout_file" ]; then
            touch "$keyout_file"
        fi
        if [ -n "$out_file" ]; then
            touch "$out_file"
        fi
        exit 0
        ;;
    pkcs12)
        out_file=""
        prev=""
        for a in "$@"; do
            if [ "$prev" = "-out" ]; then
                out_file="$a"
            fi
            prev="$a"
        done
        if [ -n "$out_file" ]; then
            touch "$out_file"
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
sed -i '' "s|__ROOT__|$root|g" "$root/stubs/openssl"
chmod +x "$root/stubs/openssl"

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
    rm -rf "${root:?}/home" "$root/launchctl.log" "$root/sudo.log" \
           "$root/security.log" "$root/codesign.log" "$root/openssl.log" \
           "$root/security.state" "$root/security.import-noop" \
           "$root/req.cnf.seen" "$root/req_dir_mode" \
           "$root/codesign.fail" "$root/codesign.fail-any"
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

# Snapshot path list under $root (excluding stub logs, states and $root/stubs)
find "$root" ! -name "launchctl.log" ! -name "sudo.log" ! -name "security.log" ! -name "codesign.log" ! -name "openssl.log" ! -name "security.state" ! -name "security.import-noop" ! -name "req.cnf.seen" ! -name "req_dir_mode" ! -name "codesign.fail" ! -name "codesign.fail-any" ! -path "$root/stubs" ! -path "$root/stubs/*" | sort > "$snapshot_file"

# Run make install twice
make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL"
make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL"

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
make uninstall APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL"

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
find "$root" ! -name "launchctl.log" ! -name "sudo.log" ! -name "security.log" ! -name "codesign.log" ! -name "openssl.log" ! -name "security.state" ! -name "security.import-noop" ! -name "req.cnf.seen" ! -name "req_dir_mode" ! -name "codesign.fail" ! -name "codesign.fail-any" ! -path "$root/stubs" ! -path "$root/stubs/*" | sort > "$current_file"
if ! cmp -s "$snapshot_file" "$current_file"; then
    echo "Path list differs from snapshot after uninstall:" >&2
    diff "$snapshot_file" "$current_file" >&2 || true
    exit 1
fi

assert_no_sudo
echo "case 1: PASS"

# ==============================================================================
# Case 2: wait (print_loaded=3 -> 1 bootout, 4 prints, 1 bootstrap)
# ==============================================================================
reset_scratch
echo "3" > "$root/print_loaded"

make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL"
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
echo "case 2: PASS"

# ==============================================================================
# Case 3: timeout (print_loaded=1000, BOOTOUT_WAIT_TRIES=3 -> fail, no bootstrap)
# ==============================================================================
reset_scratch
echo "1000" > "$root/print_loaded"
timeout_err=$(mktemp)

if make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" BOOTOUT_WAIT_TRIES=3 CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" 2>"$timeout_err"; then
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
echo "case 3: PASS"

# ==============================================================================
# Case 4: SSH session (managername=Background)
# ==============================================================================
reset_scratch
echo "Background" > "$root/managername"
find "$root" ! -name "launchctl.log" ! -name "sudo.log" ! -name "security.log" ! -name "codesign.log" ! -name "openssl.log" ! -name "security.state" ! -name "security.import-noop" ! -name "req.cnf.seen" ! -name "req_dir_mode" ! -name "codesign.fail" ! -name "codesign.fail-any" ! -path "$root/stubs" ! -path "$root/stubs/*" | sort > "$snapshot_file"

ssh_err=$(mktemp)
make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" 2>"$ssh_err"

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
make uninstall APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" 2>"$ssh_uninst_err"

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
echo "case 4: PASS"

# ==============================================================================
# Case 5: odd path (APPDIR with space, &, |, <, >, ')
# ==============================================================================
reset_scratch
odd_appdir="$root/home/Apps & Co|x <y> 'z'"
mkdir -p "$odd_appdir"
find "$root" ! -name "launchctl.log" ! -name "sudo.log" ! -name "security.log" ! -name "codesign.log" ! -name "openssl.log" ! -name "security.state" ! -name "security.import-noop" ! -name "req.cnf.seen" ! -name "req_dir_mode" ! -name "codesign.fail" ! -name "codesign.fail-any" ! -path "$root/stubs" ! -path "$root/stubs/*" | sort > "$snapshot_file"

make install APPDIR="$odd_appdir" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL"
plutil -lint "$AGENTDIR/com.wilddog64.hoverfocus.plist"
[ "$(plutil -extract ProgramArguments raw "$AGENTDIR/com.wilddog64.hoverfocus.plist")" = "1" ]
[ "$(plutil -extract ProgramArguments.0 raw "$AGENTDIR/com.wilddog64.hoverfocus.plist")" = "$odd_appdir/HoverFocus.app/Contents/MacOS/hoverfocus" ]
[ "$(grep -c __PROGRAM__ "$AGENTDIR/com.wilddog64.hoverfocus.plist")" -eq 0 ]
[ -d "$odd_appdir/HoverFocus.app" ] || { echo "Bundle missing after odd path install" >&2; exit 1; }
assert_no_sudo

make uninstall APPDIR="$odd_appdir" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL"
[ ! -e "$odd_appdir/HoverFocus.app" ] || { echo "Bundle still exists after odd path uninstall" >&2; exit 1; }
[ ! -e "$AGENTDIR/com.wilddog64.hoverfocus.plist" ] || { echo "Plist still exists after odd path uninstall" >&2; exit 1; }
assert_no_sudo

find "$root" ! -name "launchctl.log" ! -name "sudo.log" ! -name "security.log" ! -name "codesign.log" ! -name "openssl.log" ! -name "security.state" ! -name "security.import-noop" ! -name "req.cnf.seen" ! -name "req_dir_mode" ! -name "codesign.fail" ! -name "codesign.fail-any" ! -path "$root/stubs" ! -path "$root/stubs/*" | sort > "$current_file"
if ! cmp -s "$snapshot_file" "$current_file"; then
    echo "Path list differs from snapshot after odd path uninstall:" >&2
    diff "$snapshot_file" "$current_file" >&2 || true
    exit 1
fi
echo "case 5: PASS"

# ==============================================================================
# Case 6: hint (CODESIGN_IDENTITY=-)
# ==============================================================================
reset_scratch
hint_out=$(mktemp)
make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" CODESIGN_IDENTITY="-" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" >"$hint_out"
if ! grep -Fq "tccutil reset Accessibility com.wilddog64.hoverfocus" "$hint_out"; then
    echo "Expected hint in install output: $(< "$hint_out")" >&2
    rm -f "$hint_out"
    exit 1
fi
rm -f "$hint_out"
assert_no_sudo
echo "case 6: PASS"

# ==============================================================================
# Regression checks from v0.0.1
# ==============================================================================
# make install APPDIR= exits non-zero and changes nothing
reset_scratch
snapshot_before=$(find "$root" ! -name "launchctl.log" ! -name "sudo.log" ! -name "security.log" ! -name "codesign.log" ! -name "openssl.log" ! -name "security.state" ! -name "security.import-noop" ! -name "req.cnf.seen" ! -name "req_dir_mode" ! -name "codesign.fail" ! -name "codesign.fail-any" ! -path "$root/stubs" ! -path "$root/stubs/*" | sort)
refusal_err=$(mktemp)
if make install APPDIR="" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" 2>"$refusal_err"; then
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
snapshot_after=$(find "$root" ! -name "launchctl.log" ! -name "sudo.log" ! -name "security.log" ! -name "codesign.log" ! -name "openssl.log" ! -name "security.state" ! -name "security.import-noop" ! -name "req.cnf.seen" ! -name "req_dir_mode" ! -name "codesign.fail" ! -name "codesign.fail-any" ! -path "$root/stubs" ! -path "$root/stubs/*" | sort)
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

# ==============================================================================
# Case 8: identity absent (positive control)
# ==============================================================================
reset_scratch
hint_out=$(mktemp)
make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" >"$hint_out"

[ -f "$root/codesign.log" ] || { echo "codesign.log missing in case 8" >&2; exit 1; }
sign_line=$(grep -n '^<--sign>$' "$root/codesign.log" | cut -d: -f1)
val_line=$((sign_line + 1))
[ "$(sed -n "${val_line}p" "$root/codesign.log")" = "<->" ]

if ! grep -Fq "tccutil reset Accessibility com.wilddog64.hoverfocus" "$hint_out"; then
    echo "Expected tccutil hint in case 8 output: $(< "$hint_out")" >&2
    rm -f "$hint_out"
    exit 1
fi
if ! grep -Fq "make signing-identity" "$hint_out"; then
    echo "Expected make signing-identity hint in case 8 output: $(< "$hint_out")" >&2
    rm -f "$hint_out"
    exit 1
fi
rm -f "$hint_out"
assert_no_sudo
echo "case 8: PASS"

# ==============================================================================
# Case 7: identity present
# ==============================================================================
reset_scratch
echo "present" > "$root/security.state"

make bundle CODESIGN="$CODESIGN" OPENSSL="$OPENSSL"
[ -f "$root/codesign.log" ] || { echo "codesign.log missing in case 7" >&2; exit 1; }
sign_line=$(grep -n '^<--sign>$' "$root/codesign.log" | cut -d: -f1)
val_line=$((sign_line + 1))
[ "$(sed -n "${val_line}p" "$root/codesign.log")" = "<HoverFocus Local Signing>" ]

hint_out=$(mktemp)
make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" >"$hint_out"
if grep -Fq "tccutil" "$hint_out"; then
    echo "Unexpected tccutil hint in case 7 output: $(< "$hint_out")" >&2
    rm -f "$hint_out"
    exit 1
fi
rm -f "$hint_out"
assert_no_sudo
echo "case 7: PASS"

# ==============================================================================
# Case 9: explicit override
# ==============================================================================
reset_scratch
echo "present" > "$root/security.state"

make bundle CODESIGN_IDENTITY="-" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL"
[ -f "$root/codesign.log" ] || { echo "codesign.log missing in case 9" >&2; exit 1; }
sign_line=$(grep -n '^<--sign>$' "$root/codesign.log" | cut -d: -f1)
val_line=$((sign_line + 1))
[ "$(sed -n "${val_line}p" "$root/codesign.log")" = "<->" ]

if [ -f "$root/security.log" ] && grep -Fq "<find-identity>" "$root/security.log"; then
    echo "Unexpected find-identity call logged in case 9: $(< "$root/security.log")" >&2
    exit 1
fi
echo "case 9: PASS"

# ==============================================================================
# Case 10: signing-identity script
# ==============================================================================
# Sub-case: SSH_CONNECTION=x -> rc 2, no openssl call
reset_scratch
rm -rf "${root:?}/tmp"
mkdir -p "$root/tmp"
ssh_out=$(mktemp)
rc=0
SSH_CONNECTION=x TMPDIR="$root/tmp" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" SECURITY="$root/bin/security" \
    packaging/signing-identity.sh >"$ssh_out" 2>&1 || rc=$?
if [ "$rc" -ne 2 ]; then
    echo "Expected rc 2 when SSH_CONNECTION is set, got $rc: $(< "$ssh_out")" >&2
    rm -f "$ssh_out"
    exit 1
fi
if [ -f "$root/openssl.log" ] && [ -s "$root/openssl.log" ]; then
    echo "Unexpected openssl call when SSH_CONNECTION is set: $(< "$root/openssl.log")" >&2
    rm -f "$ssh_out"
    exit 1
fi
rm -f "$ssh_out"

# Sub-case: Cert absent -> req, rand, pkcs12, import, find-identity, tmp empty, no leak
reset_scratch
rm -rf "${root:?}/tmp"
mkdir -p "$root/tmp"
script_out=$(mktemp)
rc=0
env -u SSH_CONNECTION TMPDIR="$root/tmp" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" SECURITY="$root/bin/security" \
    packaging/signing-identity.sh >"$script_out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "Expected rc 0 for signing-identity script, got $rc. Output: $(< "$script_out")" >&2
    rm -f "$script_out"
    exit 1
fi

[ -f "$root/openssl.log" ] || { echo "openssl.log missing in case 10" >&2; exit 1; }
req_line=$(grep -n '^<req>$' "$root/openssl.log" | cut -d: -f1)
rand_line=$(grep -n '^<rand>$' "$root/openssl.log" | cut -d: -f1)
pkcs12_line=$(grep -n '^<pkcs12>$' "$root/openssl.log" | cut -d: -f1)
if [ -z "$req_line" ] || [ -z "$rand_line" ] || [ -z "$pkcs12_line" ] || \
   [ "$req_line" -ge "$rand_line" ] || [ "$rand_line" -ge "$pkcs12_line" ]; then
    echo "openssl.log calls not in req, rand, pkcs12 order" >&2
    exit 1
fi

passout_line=$(grep -n '^<-passout>$' "$root/openssl.log" | cut -d: -f1)
passout_arg_line=$((passout_line + 1))
[ "$(sed -n "${passout_arg_line}p" "$root/openssl.log")" = "<env:P12_PASS>" ]
if grep -q "pass:" "$root/openssl.log"; then
    echo "pass: found on openssl argv: $(< "$root/openssl.log")" >&2
    exit 1
fi

grep -Fq "<import>" "$root/security.log"
k_line=$(grep -n '^<-k>$' "$root/security.log" | cut -d: -f1)
k_val_line=$((k_line + 1))
[ "$(sed -n "${k_val_line}p" "$root/security.log")" = "<$root/home/Library/Keychains/login.keychain-db>" ]
grep -Fq "<-T>" "$root/security.log"

[ -f "$root/security.state" ] && [ "$(cat "$root/security.state")" = "present" ]

[ -f "$root/req.cnf.seen" ] || { echo "req.cnf.seen missing" >&2; exit 1; }
grep -Fq "prompt = no" "$root/req.cnf.seen"
grep -Fq "x509_extensions = ext" "$root/req.cnf.seen"
grep -Fq "CN = HoverFocus Local Signing" "$root/req.cnf.seen"
grep -Fq "codeSigning" "$root/req.cnf.seen"

[ -f "$root/req_dir_mode" ] && [ "$(cat "$root/req_dir_mode")" = "700" ]

tmp_contents=$(ls -A "$root/tmp")
[ -z "$tmp_contents" ] || { echo "$root/tmp not empty after exit: $tmp_contents" >&2; exit 1; }

if grep -q "STUB_P12_SECRET" "$root/security.log" "$root/codesign.log" "$root/openssl.log" 2>/dev/null; then
    echo "STUB_P12_SECRET leaked in stub logs" >&2
    exit 1
fi
if grep -q "STUB_P12_SECRET" "$script_out"; then
    echo "STUB_P12_SECRET leaked in script output: $(< "$script_out")" >&2
    exit 1
fi
rm -f "$script_out"

# Sub-case: Import no-op (security.import-noop) -> rc 1 and $root/tmp empty
reset_scratch
rm -rf "${root:?}/tmp"
mkdir -p "$root/tmp"
touch "$root/security.import-noop"
noop_out=$(mktemp)
rc=0
env -u SSH_CONNECTION TMPDIR="$root/tmp" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" SECURITY="$root/bin/security" \
    packaging/signing-identity.sh >"$noop_out" 2>&1 || rc=$?
if [ "$rc" -ne 1 ]; then
    echo "Expected rc 1 for import no-op, got $rc" >&2
    rm -f "$noop_out"
    exit 1
fi
tmp_contents=$(ls -A "$root/tmp")
[ -z "$tmp_contents" ] || { echo "$root/tmp not empty after import no-op failure: $tmp_contents" >&2; exit 1; }
rm -f "$noop_out"

# Sub-case: Cert present -> already present, no openssl call
reset_scratch
rm -rf "${root:?}/tmp"
mkdir -p "$root/tmp"
echo "present" > "$root/security.state"
present_out=$(mktemp)
rc=0
env -u SSH_CONNECTION TMPDIR="$root/tmp" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" SECURITY="$root/bin/security" \
    packaging/signing-identity.sh >"$present_out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "Expected rc 0 for cert present, got $rc" >&2
    rm -f "$present_out"
    exit 1
fi
if ! grep -q "already present" "$present_out"; then
    echo "Expected 'already present' in output: $(< "$present_out")" >&2
    rm -f "$present_out"
    exit 1
fi
if [ -f "$root/openssl.log" ] && [ -s "$root/openssl.log" ]; then
    echo "Unexpected openssl call when cert already present: $(< "$root/openssl.log")" >&2
    rm -f "$present_out"
    exit 1
fi
rm -f "$present_out"

echo "case 10: PASS"

echo "case 11: starting signing failure checks"
reset_scratch
echo "present" > "$root/security.state"
touch "$root/codesign.fail"
fail_out=$(mktemp)
rc=0
make bundle CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" >"$fail_out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { echo "case 11a: make bundle unexpectedly succeeded" >&2; exit 1; }
[ ! -e build/.codesign-identity ] || { echo "case 11a: identity file left behind" >&2; exit 1; }
[ ! -e build/HoverFocus.app ] || { echo "case 11a: failed bundle left behind" >&2; exit 1; }
grep -Fq 'signing with "HoverFocus Local Signing" failed' "$fail_out"
grep -Fq 'probably' "$fail_out"
if grep -Fq 'unlock-keychain' "$fail_out"; then echo "case 11a: unsafe unlock-keychain advice" >&2; exit 1; fi
rm -f "$fail_out"
echo "case 11a: PASS"

reset_scratch
echo "present" > "$root/security.state"
mkdir -p "$APPDIR/HoverFocus.app" "$AGENTDIR"
echo "installed app marker" > "$APPDIR/HoverFocus.app/marker"
echo "existing agent plist" > "$AGENTDIR/com.wilddog64.hoverfocus.plist"
cp "$APPDIR/HoverFocus.app/marker" "$root/marker.before"
cp "$AGENTDIR/com.wilddog64.hoverfocus.plist" "$root/plist.before"
touch "$root/codesign.fail"
fail_out=$(mktemp)
rc=0
make install APPDIR="$APPDIR" AGENTDIR="$AGENTDIR" LAUNCHCTL="$LAUNCHCTL" HOME="$HOME" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" >"$fail_out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { echo "case 11b: make install unexpectedly succeeded" >&2; exit 1; }
cmp -s "$root/marker.before" "$APPDIR/HoverFocus.app/marker"
cmp -s "$root/plist.before" "$AGENTDIR/com.wilddog64.hoverfocus.plist"
if [ -f "$root/launchctl.log" ] && [ -s "$root/launchctl.log" ]; then echo "case 11b: launchctl was called: $(< "$root/launchctl.log")" >&2; exit 1; fi
rm -f "$fail_out"
echo "case 11b: PASS"

reset_scratch
touch "$root/codesign.fail"
fail_out=$(mktemp)
rc=0
make bundle CODESIGN_IDENTITY="Some Identity" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" >"$fail_out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { echo "case 11c: explicit identity unexpectedly succeeded" >&2; exit 1; }
[ ! -e build/.codesign-identity ] || { echo "case 11c: identity file left behind" >&2; exit 1; }
rm -f "$fail_out"
echo "case 11c: PASS"

reset_scratch
touch "$root/codesign.fail-any"
fail_out=$(mktemp)
rc=0
make bundle CODESIGN_IDENTITY=- CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" >"$fail_out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { echo "case 11d: ad-hoc signing unexpectedly succeeded" >&2; exit 1; }
grep -Fq 'ad-hoc signing failed' "$fail_out"
[ ! -e build/.codesign-identity ] || { echo "case 11d: identity file left behind" >&2; exit 1; }
rm -f "$fail_out"
echo "case 11d: PASS"

reset_scratch
echo "present" > "$root/security.state"
make bundle CODESIGN="$CODESIGN" OPENSSL="$OPENSSL"
[ "$(cat build/.codesign-identity)" = "HoverFocus Local Signing" ]
echo "case 11e: PASS"

reset_scratch
echo "certificate-only" > "$root/security.state"
rm -rf "$root/tmp"
mkdir -p "$root/tmp"
script_out=$(mktemp)
rc=0
env -u SSH_CONNECTION TMPDIR="$root/tmp" CODESIGN="$CODESIGN" OPENSSL="$OPENSSL" SECURITY="$root/bin/security" \
    packaging/signing-identity.sh >"$script_out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { echo "case 12: expected script success, got $rc: $(< "$script_out")" >&2; exit 1; }
if grep -q "already present" "$script_out"; then echo "case 12: certificate-only state reported already present" >&2; exit 1; fi
grep -Fq '<req>' "$root/openssl.log"
rm -f "$script_out"
echo "case 12: PASS"

echo "install_test passed"
