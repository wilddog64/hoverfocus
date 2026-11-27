import Foundation

public struct Engine: FocusDeciding {
    public private(set) var config: Config
    private var candidate: (target: WindowTarget, x: Double, y: Double, start: UInt64)?
    private var lastSample: PointerSample?
    private var lastTarget: WindowTarget?
    private var firedWindow: UInt32?

    public init(config: Config) {
        self.config = config
    }

    public var hasPendingCandidate: Bool { candidate != nil }

    public mutating func update(_ config: Config) {
        self.config = config
        candidate = nil
        firedWindow = nil
    }

    private func permitted(_ sample: PointerSample, _ target: WindowTarget?, _ state: SystemState) -> Bool {
        guard config.enabled,
              !(config.ignoreWhenButtonDown && sample.buttonsDown),
              !state.menuOpen,
              !state.missionControlActive,
              let target,
              target.isStandardWindow,
              !(target.bundleID.map(config.ignoreApps.contains) ?? false) else {
            return false
        }
        let bit: Modifiers
        switch config.pauseModifier {
        case .none: bit = []
        case .control: bit = .control
        case .option: bit = .option
        case .command: bit = .command
        case .function: bit = .function
        }
        return bit.isEmpty || !sample.modifiers.contains(bit)
    }

    private func decision(_ target: WindowTarget) -> Decision {
        config.raiseApps.contains(target.bundleID ?? "") ? .focusAndRaise(target) : .focus(target)
    }

    public mutating func observe(
        _ sample: PointerSample,
        under target: WindowTarget?,
        state: SystemState
    ) -> Decision {
        lastSample = sample
        lastTarget = target
        if firedWindow != target?.windowID {
            firedWindow = nil
        }
        guard permitted(sample, target, state), let target else {
            candidate = nil
            return .none
        }
        if target.windowID == state.focusedWindowID {
            candidate = nil
            return .none
        }
        if firedWindow == target.windowID {
            candidate = nil
            return .none
        }
        if let current = candidate {
            let dx = sample.x - current.x
            let dy = sample.y - current.y
            if current.target.windowID != target.windowID || hypot(dx, dy) > config.stillnessPx {
                candidate = (target, sample.x, sample.y, sample.timeMs)
            }
        } else {
            candidate = (target, sample.x, sample.y, sample.timeMs)
        }
        guard let current = candidate else { return .none }
        let elapsed = sample.timeMs >= current.start ? sample.timeMs - current.start : 0
        let dwell = UInt64(max(0, config.dwellMs))
        guard elapsed >= dwell else { return .none }
        firedWindow = target.windowID
        candidate = nil
        return decision(target)
    }

    public mutating func tick(nowMs: UInt64, state: SystemState) -> Decision {
        guard let sample = lastSample,
              let target = lastTarget,
              permitted(sample, target, state),
              target.windowID != state.focusedWindowID,
              firedWindow != target.windowID,
              let current = candidate,
              current.target.windowID == target.windowID else {
            candidate = nil
            return .none
        }
        let elapsed = nowMs >= current.start ? nowMs - current.start : 0
        guard elapsed >= UInt64(max(0, config.dwellMs)) else { return .none }
        firedWindow = target.windowID
        candidate = nil
        return decision(target)
    }
}
