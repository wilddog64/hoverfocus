import Darwin

public struct Modifiers: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let command = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)
}

public struct PointerSample: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let timeMs: UInt64
    public let buttonsDown: Bool
    public let modifiers: Modifiers
    public init(x: Double, y: Double, timeMs: UInt64, buttonsDown: Bool, modifiers: Modifiers) {
        self.x = x; self.y = y; self.timeMs = timeMs; self.buttonsDown = buttonsDown; self.modifiers = modifiers
    }
}

public struct WindowTarget: Sendable, Equatable {
    public let windowID: UInt32
    public let pid: Int32
    public let bundleID: String?
    public let isStandardWindow: Bool
    public init(windowID: UInt32, pid: Int32, bundleID: String?, isStandardWindow: Bool) {
        self.windowID = windowID; self.pid = pid; self.bundleID = bundleID; self.isStandardWindow = isStandardWindow
    }
}

public struct SystemState: Sendable, Equatable {
    public let focusedWindowID: UInt32?
    public let menuOpen: Bool
    public let missionControlActive: Bool
    public init(focusedWindowID: UInt32?, menuOpen: Bool, missionControlActive: Bool) {
        self.focusedWindowID = focusedWindowID; self.menuOpen = menuOpen; self.missionControlActive = missionControlActive
    }
}

public enum Decision: Sendable, Equatable {
    case none
    case focus(WindowTarget)
    case focusAndRaise(WindowTarget)
}

public enum PauseModifier: String, Codable, Sendable, Equatable {
    case none, control, option, command, function
}

public struct Config: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var dwellMs: Int
    public var stillnessPx: Double
    public var ignoreWhenButtonDown: Bool
    public var pauseModifier: PauseModifier
    public var ignoreApps: [String]
    public var raiseApps: [String]
    public init(enabled: Bool = true, dwellMs: Int = 150, stillnessPx: Double = 4,
                ignoreWhenButtonDown: Bool = true, pauseModifier: PauseModifier = .function,
                ignoreApps: [String] = [], raiseApps: [String] = []) {
        self.enabled = enabled; self.dwellMs = dwellMs; self.stillnessPx = stillnessPx
        self.ignoreWhenButtonDown = ignoreWhenButtonDown; self.pauseModifier = pauseModifier
        self.ignoreApps = ignoreApps; self.raiseApps = raiseApps
    }
}

public enum ConfigError: Error, Equatable {
    case unreadable(path: String)
    case invalid(path: String, reason: String)
}

public protocol FocusDeciding {
    mutating func observe(_ sample: PointerSample, under target: WindowTarget?, state: SystemState) -> Decision
    mutating func tick(nowMs: UInt64, state: SystemState) -> Decision
}

public enum ControllerError: Error, Equatable {
    case accessibilityNotTrusted
    case privateAPIUnavailable(symbol: String)
    case eventTapFailed
}

public struct StartChecks: Sendable {
    public var isTrusted: @Sendable () -> Bool
    public var missingPrivateSymbol: @Sendable () -> String?
    public var canListenToEvents: @Sendable () -> Bool
    public init(isTrusted: @escaping @Sendable () -> Bool,
                missingPrivateSymbol: @escaping @Sendable () -> String?,
                canListenToEvents: @escaping @Sendable () -> Bool) {
        self.isTrusted = isTrusted
        self.missingPrivateSymbol = missingPrivateSymbol
        self.canListenToEvents = canListenToEvents
    }
}

public enum MonotonicClock {
    public static func nowMs() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1_000_000 }
}

@MainActor
public protocol FocusControlling: AnyObject {
    var isRunning: Bool { get }
    var isPaused: Bool { get set }
    func start() throws
    func stop()
    func apply(_ config: Config)
}
