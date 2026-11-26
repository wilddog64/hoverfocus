public enum Health: Equatable, Sendable {
    case ok
    case configError(ConfigError)
    case startError(ControllerError)
}

public struct ErrorNotifier {
    private var lastObserved: Health = .ok

    public init() {}

    public mutating func observe(_ health: Health) -> Health? {
        defer { lastObserved = health }
        guard health != .ok, health != lastObserved else { return nil }
        return health
    }
}
