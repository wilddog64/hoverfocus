import CoreFoundation
import Foundation

public enum ConfigLoader {
    public static func load(from url: URL) throws -> Config {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else { return Config() }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError.unreadable(path: path)
        }
        func invalid(_ reason: String) -> ConfigError {
            .invalid(path: path, reason: reason)
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw invalid("invalid JSON")
        }
        guard let values = object as? [String: Any] else {
            throw invalid("top-level value must be an object")
        }
        let knownKeys: Set<String> = [
            "enabled", "dwellMs", "stillnessPx", "ignoreWhenButtonDown",
            "pauseModifier", "ignoreApps", "raiseApps", "menuBarIcon",
            "focusIndicator"
        ]
        for key in values.keys where !knownKeys.contains(key) {
            throw invalid("unknown key: \(key)")
        }

        var config = Config()
        func readBoolean(_ key: String, set: (Bool) -> Void) throws {
            guard let value = values[key] else { return }
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw invalid("\(key) must be boolean")
            }
            set(number.boolValue)
        }
        try readBoolean("enabled") { config.enabled = $0 }
        try readBoolean("ignoreWhenButtonDown") { config.ignoreWhenButtonDown = $0 }
        try readBoolean("focusIndicator") { config.focusIndicator = $0 }

        if let value = values["dwellMs"] {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.rounded() == number.doubleValue,
                  (0...5000).contains(number.intValue) else {
                throw invalid("dwellMs must be an integer from 0 to 5000")
            }
            config.dwellMs = number.intValue
        }
        if let value = values["stillnessPx"] {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  (0.0...200.0).contains(number.doubleValue) else {
                throw invalid("stillnessPx must be a number from 0 to 200")
            }
            config.stillnessPx = number.doubleValue
        }
        for key in ["ignoreApps", "raiseApps"] {
            guard let value = values[key] else { continue }
            guard let apps = value as? [String] else {
                throw invalid("\(key) must be an array of strings")
            }
            if key == "ignoreApps" { config.ignoreApps = apps }
            else { config.raiseApps = apps }
        }
        if let value = values["pauseModifier"] {
            guard let raw = value as? String,
                  let modifier = PauseModifier(rawValue: raw) else {
                throw invalid("pauseModifier has unknown value")
            }
            config.pauseModifier = modifier
        }
        if let value = values["menuBarIcon"] {
            guard let raw = value as? String,
                  let style = MenuBarIconStyle(rawValue: raw) else {
                throw invalid("menuBarIcon has unknown value")
            }
            config.menuBarIcon = style
        }
        return config
    }
}
