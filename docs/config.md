# HoverFocus Configuration

HoverFocus reads its configuration from `~/.config/hoverfocus/config.json`.
The configuration path can be overridden by setting the `HOVERFOCUS_CONFIG` environment variable.

If the configuration file is missing, default values are used. If the file contains invalid JSON or invalid values, HoverFocus shows `Error: config <reason>` and stops focusing until a valid file is loaded with Reload Config.

## Configuration Keys

| Key | Type | Default | Description / Allowed Values |
|---|---|---|---|
| `dwellMs` | Integer | `150` | Dwell duration in milliseconds before focusing the window under the mouse cursor. Range: `0`–`5000`. |
| `enabled` | Boolean | `true` | Master toggle to enable or disable focus following mouse. |
| `focusIndicator` | Boolean | `true` | Draws a thin accent-colour border around the window focused by hover; set false to turn it off. |
| `ignoreApps` | Array of Strings | `[]` | Bundle identifiers of applications to exclude from focus changes. |
| `ignoreWhenButtonDown` | Boolean | `true` | When true, hover focus is suppressed while any mouse button is pressed (e.g. during drag operations). |
| `menuBarIcon` | String | `"auto"` | Menu bar icon appearance. Allowed values: `"auto"`, `"color"`, `"light"`, `"dark"`. |
| `pauseModifier` | String | `"function"` | Modifier key that temporarily pauses hover focus while held down. Allowed values: `"none"`, `"control"`, `"option"`, `"command"`, `"function"`. |
| `raiseApps` | Array of Strings | `[]` | Bundle identifiers of applications whose windows should be raised when focused. |
| `stillnessPx` | Number | `4` | Movement threshold in pixels within which the cursor is considered still during dwelling. Range: `0`–`200`. |

Unknown keys, wrong value types and values outside these ranges are rejected. The menu status line names the invalid key.
