# hoverfocus

HoverFocus provides focus-follows-mouse behaviour for macOS without raising windows.

The application runs as a lightweight accessory process with an `NSStatusItem` in the macOS menu bar.

## Building

Building requires macOS 14+ and Swift 6.

```bash
# Compile release binary
make build

# Run unit / integration self-tests
make selftest

# Generate application icon and assemble HoverFocus.app bundle
make bundle
```

By default, `make bundle` signs the app using the "HoverFocus Local Signing" identity when the login Keychain has it, else ad-hoc (`-`). You can supply a custom signing identity:

```bash
make bundle CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

## Installation

Run `make signing-identity` once at the Mac (Keychain prompt: enter the login password, click **Always Allow**), then `make install`; later builds keep the Accessibility grant. Without it builds are ad-hoc and each install needs a re-grant.

Signing with the local identity needs the login Keychain unlocked, so run `make install` at the Mac's keyboard; over SSH it stops with a message rather than installing an unsigned build. `CODESIGN_IDENTITY=-` opts into an ad-hoc build, which needs an Accessibility re-grant.

```bash
make signing-identity
make install
```

This installs `HoverFocus.app` into `~/Applications/` and registers a user LaunchAgent in `~/Library/LaunchAgents/com.wilddog64.hoverfocus.plist`. You can customize the target directories with `APPDIR` and `AGENTDIR`.

Re-installing with `make install` while HoverFocus is running is safe: it unloads the existing agent and waits for it to stop before bootstrapping the new one.

In a non-GUI session (such as over SSH or in a tmux session where `launchctl managername` is not `Aqua`), the files are installed but the LaunchAgent is not loaded directly. `make install` prints the `sudo launchctl asuser` commands to load the agent:

```bash
sudo launchctl asuser <uid> launchctl bootout gui/<uid>/com.wilddog64.hoverfocus
sudo launchctl asuser <uid> launchctl bootstrap gui/<uid> '<plist>'
```

To uninstall:

```bash
make uninstall
```

In a non-GUI session, `make uninstall` removes the files and prints the `sudo launchctl asuser <uid> launchctl bootout gui/<uid>/com.wilddog64.hoverfocus` command. Neither target requires `sudo`.

## Granting Accessibility Permissions

HoverFocus requires macOS Accessibility permission to monitor pointer movement and manage window focus:

1. On initial launch, the menu bar item indicates `Needs Accessibility permission`.
2. Click **Grant Accessibility…** in the menu bar menu, or navigate to **System Settings > Privacy & Security > Accessibility**.
3. Enable HoverFocus in the list.

HoverFocus notices the permission grant within a few seconds without requiring an application restart.

When using ad-hoc code signing, macOS invalidates Accessibility trust whenever the binary is recompiled. After rebuilding an ad-hoc build, reset permissions before re-granting:

```bash
tccutil reset Accessibility com.wilddog64.hoverfocus
```

After `tccutil reset`, quit System Settings if already open, reopen **System Settings > Privacy & Security > Accessibility**, remove HoverFocus with **−**, then add it again with **+**.

## Menu Bar Interface

The menu bar item displays current operational status and controls:

- **Status line**: Displays `Running`, `Paused`, `Off`, `Needs Accessibility permission`, `Unavailable: <symbol>`, `Error: event tap`, or `Error: config <reason>`.
- **Enabled**: Toggles hover focus on or off in memory.
- **Pause for 30 minutes / Resume**: Temporarily suspends focus management for 30 minutes or resumes immediately.
- **Menu Bar Icon**: Submenu to choose icon appearance:
  - `Automatic`: Template icon adapting automatically to system appearance.
  - `Colour`: Accent-coloured icon adapting to light/dark menu bar.
  - `Light bar`: High-contrast icon optimized for light menu bar.
  - `Dark bar`: High-contrast icon optimized for dark menu bar.
- **Grant Accessibility…**: Prompts macOS for accessibility access (visible when ungranted).
- **Reload Config**: Re-reads configuration from disk.
- **Open Config**: Opens configuration in default editor, generating default configuration if missing.
- **Quit**: Exits the application.

## Diagnostics and Logs

To view live diagnostic logs from HoverFocus:

```bash
log stream --predicate 'subsystem == "com.wilddog64.hoverfocus"'
```

## Configuration

See [docs/config.md](docs/config.md) for full descriptions of all configuration keys and options. A template configuration is available in `config.example.json`.

## Tested apps

| App | Typing lands without raise | Cmd shortcuts | Notes |
|---|---|---|---|
| TextEdit | yes | not tried | |
| TextEdit second window (same app) | yes | not tried | |
| Safari | yes | yes (Cmd+L) | Safari brings its own window forward on Cmd+L and when you hover its page content |
| Chrome | yes | yes | |
| Mail | yes | not tried | |
| Terminal.app | yes | yes | |
| iTerm2 | yes | not tried | |
| Slack | yes | not tried | message area and window buttons |
| VS Code | yes | not tried | editor text and title bar |

Checked live on macOS 26.5.1 (m2-air, 2026-11-25) with each app behind another window and the pointer resting on it.
Hovering the Dock does not move keyboard focus.

## Known Limitations

- Uses private system APIs (SkyLight) that may change or require updates across macOS releases.
- Ad-hoc signed builds require re-granting Accessibility permission after rebuilding.
- Electron applications and full-screen spaces may handle window focus differently.
- Intended for personal workstations and development environments.
- Some apps raise their own window when they receive focus: Safari on macOS 26 comes forward when you hover its page content or press Cmd+L (its title bar does not). Add such apps to ignoreApps (bundle IDs), for example "ignoreApps": ["com.apple.Safari"].
- Hovering another window of the app that is already in front does not move focus (live-checked on macOS 26,
  2026-11-23); click to switch windows within one app. Planned fix: v0.0.2.
- After hover focus returns to a terminal (iTerm2, Terminal.app), its cursor can be drawn as unfocused (hollow) even
  though keystrokes reach it; one click restores it. Planned fix: v0.0.2.
- The border is drawn by HoverFocus, so the focused app still looks inactive (title bar, cursor shape); the border disappears within about a second after a keyboard focus change.

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
