import Foundation
import HoverFocusCore
import HoverFocusPlatform

public struct RGBA: Equatable, Sendable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8
    public let a: Double

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public var hexString: String {
        let aByte = UInt8((a * 255.0).rounded())
        if a >= 0.999 {
            return String(format: "#%02X%02X%02X", r, g, b)
        } else {
            return String(format: "#%02X%02X%02X%02X", r, g, b, aByte)
        }
    }
}

public enum AppStatus: Equatable {
    case running
    case paused
    case off
    case controllerError(ControllerError)
    case configError(ConfigError)
}

public enum MenuModel {
    public static func configPath() -> String {
        if let envPath = ProcessInfo.processInfo.environment["HOVERFOCUS_CONFIG"], !envPath.isEmpty {
            return (envPath as NSString).expandingTildeInPath
        }
        return ("~/.config/hoverfocus/config.json" as NSString).expandingTildeInPath
    }

    public static func configURL() -> URL {
        URL(fileURLWithPath: configPath())
    }

    private struct PartialConfig: Decodable {
        var enabled: Bool?
        var dwellMs: Int?
        var stillnessPx: Double?
        var ignoreWhenButtonDown: Bool?
        var pauseModifier: PauseModifier?
        var ignoreApps: [String]?
        var raiseApps: [String]?
        var menuBarIcon: MenuBarIconStyle?
    }

    public static func loadConfig(at url: URL = configURL()) throws -> Config {
        _ = try? ConfigLoader.load(from: url)
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            return Config()
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError.unreadable(path: path)
        }
        do {
            let decoder = JSONDecoder()
            let partial = try decoder.decode(PartialConfig.self, from: data)
            var config = Config()
            if let val = partial.enabled { config.enabled = val }
            if let val = partial.dwellMs { config.dwellMs = val }
            if let val = partial.stillnessPx { config.stillnessPx = val }
            if let val = partial.ignoreWhenButtonDown { config.ignoreWhenButtonDown = val }
            if let val = partial.pauseModifier { config.pauseModifier = val }
            if let val = partial.ignoreApps { config.ignoreApps = val }
            if let val = partial.raiseApps { config.raiseApps = val }
            if let val = partial.menuBarIcon { config.menuBarIcon = val }
            return config
        } catch {
            throw ConfigError.invalid(path: path, reason: error.localizedDescription)
        }
    }

    public static func statusLine(for status: AppStatus) -> String {
        switch status {
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .off:
            return "Off"
        case .controllerError(let err):
            return statusLine(for: err)
        case .configError(let err):
            return statusLine(for: err)
        }
    }

    public static func statusLine(for err: ControllerError) -> String {
        switch err {
        case .accessibilityNotTrusted:
            return "Needs Accessibility permission"
        case .privateAPIUnavailable(let symbol):
            return "Unavailable: \(symbol)"
        case .eventTapFailed:
            return "Error: event tap"
        }
    }

    public static func statusLine(for err: ConfigError) -> String {
        switch err {
        case .unreadable(let path):
            return "Error: config \(path): unreadable"
        case .invalid(let path, let reason):
            return "Error: config \(path): \(reason)"
        }
    }

    public static func iconColors(style: MenuBarIconStyle, darkBar: Bool, dimmed: Bool) -> (template: Bool, glyph: RGBA, track: RGBA, arc: RGBA) {
        let dimFactor = dimmed ? 0.40 : 1.0
        switch style {
        case .auto:
            return (
                template: true,
                glyph: RGBA(0x00, 0x00, 0x00, 1.0 * dimFactor),
                track: RGBA(0x00, 0x00, 0x00, 0.25 * dimFactor),
                arc: RGBA(0x00, 0x00, 0x00, 1.0 * dimFactor)
            )
        case .color:
            if !darkBar {
                return (
                    template: false,
                    glyph: RGBA(0x11, 0x11, 0x11, 1.0 * dimFactor),
                    track: RGBA(0x11, 0x11, 0x11, 0.20 * dimFactor),
                    arc: RGBA(0x0B, 0x8F, 0x7C, 1.0 * dimFactor)
                )
            } else {
                return (
                    template: false,
                    glyph: RGBA(0xFF, 0xFF, 0xFF, 1.0 * dimFactor),
                    track: RGBA(0xFF, 0xFF, 0xFF, 0.25 * dimFactor),
                    arc: RGBA(0x4F, 0xD8, 0xBF, 1.0 * dimFactor)
                )
            }
        case .light:
            return (
                template: false,
                glyph: RGBA(0x11, 0x11, 0x11, 1.0 * dimFactor),
                track: RGBA(0x11, 0x11, 0x11, 0.25 * dimFactor),
                arc: RGBA(0x11, 0x11, 0x11, 1.0 * dimFactor)
            )
        case .dark:
            return (
                template: false,
                glyph: RGBA(0xFF, 0xFF, 0xFF, 1.0 * dimFactor),
                track: RGBA(0xFF, 0xFF, 0xFF, 0.30 * dimFactor),
                arc: RGBA(0xFF, 0xFF, 0xFF, 1.0 * dimFactor)
            )
        }
    }

    public static func printStatusTable() {
        let ctrlErrors: [(String, ControllerError)] = [
            ("accessibilityNotTrusted", .accessibilityNotTrusted),
            ("privateAPIUnavailable(symbol: \"symbol\")", .privateAPIUnavailable(symbol: "symbol")),
            ("eventTapFailed", .eventTapFailed),
        ]
        for (caseName, err) in ctrlErrors {
            print("\(caseName) -> \(statusLine(for: err))")
        }

        let cfgErrors: [(String, ConfigError)] = [
            ("unreadable(path: \"~/.config/hoverfocus/config.json\")", .unreadable(path: "~/.config/hoverfocus/config.json")),
            ("invalid(path: \"~/.config/hoverfocus/config.json\", reason: \"dwellMs must be integer\")", .invalid(path: "~/.config/hoverfocus/config.json", reason: "dwellMs must be integer")),
        ]
        for (caseName, err) in cfgErrors {
            print("\(caseName) -> \(statusLine(for: err))")
        }

        print("Running -> \(statusLine(for: .running))")
        print("Paused -> \(statusLine(for: .paused))")
        print("Off -> \(statusLine(for: .off))")

        for style in MenuBarIconStyle.allCases {
            for dark in [false, true] {
                for dimmed in [false, true] {
                    let colors = iconColors(style: style, darkBar: dark, dimmed: dimmed)
                    print("icon \(style.rawValue) dark=\(dark) dimmed=\(dimmed) template=\(colors.template) glyph=\(colors.glyph.hexString) track=\(colors.track.hexString) arc=\(colors.arc.hexString)")
                }
            }
        }
    }
}
