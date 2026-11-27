import Foundation

public struct MenuBarIconKey: Equatable, Sendable {
    public let style: MenuBarIconStyle
    public let darkBar: Bool
    public let dimmed: Bool

    public init(style: MenuBarIconStyle, darkBar: Bool, dimmed: Bool) {
        self.style = style
        self.darkBar = darkBar
        self.dimmed = dimmed
    }
}

public struct MenuBarIconState: Sendable {
    private var lastApplied: MenuBarIconKey?

    public init() {}

    public mutating func needsApply(_ key: MenuBarIconKey) -> Bool {
        guard lastApplied != key else { return false }
        lastApplied = key
        return true
    }

    public mutating func invalidate() {
        lastApplied = nil
    }
}
