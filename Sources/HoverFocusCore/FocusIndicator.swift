import Foundation

public struct IndicatorRect: Sendable, Equatable {
    public var x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct FocusIndicatorModel: Sendable, Equatable {
    public private(set) var trackedWindowID: UInt32?
    private var isConfirmed = false
    private var decidedMs: UInt64 = 0

    public init() {}

    public mutating func decided(_ decision: Decision, succeeded: Bool, nowMs: UInt64) {
        switch decision {
        case .focus(let target):
            if succeeded {
                trackedWindowID = target.windowID
                isConfirmed = false
                decidedMs = nowMs
            } else {
                reset()
            }
        case .focusAndRaise:
            reset()
        case .none:
            break
        }
    }

    public mutating func mouseDown(onWindow windowID: UInt32?) {
        guard let tracked = trackedWindowID else { return }
        if windowID != tracked {
            reset()
        }
    }

    public mutating func observeFocused(_ focusedWindowID: UInt32?, nowMs: UInt64) {
        guard let tracked = trackedWindowID else { return }
        guard let focused = focusedWindowID else { return }
        if focused == tracked {
            isConfirmed = true
        } else {
            if isConfirmed || (nowMs >= decidedMs && nowMs - decidedMs >= 1000) {
                reset()
            }
        }
    }

    public mutating func reset() {
        trackedWindowID = nil
        isConfirmed = false
        decidedMs = 0
    }

    public func frame(enabled: Bool, paused: Bool, bounds: (UInt32) -> IndicatorRect?, mainHeight: Double) -> IndicatorRect? {
        guard enabled, !paused, let tracked = trackedWindowID else {
            return nil
        }
        guard let b = bounds(tracked) else {
            return nil
        }
        return IndicatorGeometry.cocoaFrame(cgBounds: b, mainHeight: mainHeight)
    }
}

public enum IndicatorGeometry {
    public static let thickness = 3.0

    public static func cocoaFrame(cgBounds: IndicatorRect, mainHeight: Double) -> IndicatorRect {
        IndicatorRect(
            x: cgBounds.x,
            y: mainHeight - (cgBounds.y + cgBounds.height),
            width: cgBounds.width,
            height: cgBounds.height
        )
    }

    public static func strips(around window: IndicatorRect) -> [IndicatorRect] {
        let t = thickness
        let x = window.x
        let y = window.y
        let w = window.width
        let h = window.height
        return [
            IndicatorRect(x: x - t, y: y + h, width: w + 2 * t, height: t),
            IndicatorRect(x: x - t, y: y - t, width: w + 2 * t, height: t),
            IndicatorRect(x: x - t, y: y, width: t, height: h),
            IndicatorRect(x: x + w, y: y, width: t, height: h)
        ]
    }
}
