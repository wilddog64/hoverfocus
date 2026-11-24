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

By default, `make bundle` signs the app using ad-hoc code signing (`-`). You can supply a custom signing identity:

```bash
make bundle CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

## Installation

Install the app bundle and launch agent:

```bash
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

then enable HoverFocus in System Settings > Privacy & Security > Accessibility.

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

## Known Limitations

- Uses private system APIs (SkyLight) that may change or require updates across macOS releases.
- Ad-hoc signed builds require re-granting Accessibility permission after rebuilding.
- Electron applications and full-screen spaces may handle window focus differently.
- Intended for personal workstations and development environments.
- Some apps can raise their own window when they receive focus (seen with Safari on macOS 26). Add such apps to ignoreApps (bundle IDs), for example "ignoreApps": ["com.apple.Safari"].
- Hovering another window of the app that is already in front does not move focus (live-checked on macOS 26,
  2026-11-23); click to switch windows within one app. Planned fix: v0.0.2.
- After hover focus returns to a terminal (iTerm2, Terminal.app), its cursor can be drawn as unfocused (hollow) even
  though keystrokes reach it; one click restores it. Planned fix: v0.0.2.

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
