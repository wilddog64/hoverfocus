import HoverFocusCore

@MainActor
public final class HoverFocusController: FocusControlling {
    public private(set) var isRunning = false
    public var isPaused = false
    public init(config: Config, checks: StartChecks = HoverFocusController.liveChecks) {}
    public func start() throws { throw ControllerError.privateAPIUnavailable(symbol: "not implemented") }
    public func stop() { isRunning = false }
    public func apply(_ config: Config) {}
    public nonisolated static let liveChecks = StartChecks(
        isTrusted: { false },
        missingPrivateSymbol: { "not implemented" },
        canListenToEvents: { false })
}

public enum AccessibilityPermission {
    public static func isTrusted(prompt: Bool) -> Bool { false }
}
