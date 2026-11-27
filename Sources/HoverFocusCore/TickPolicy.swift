import Foundation

public enum TickPolicy {
    public static func interval(candidatePending: Bool, tracked: Bool, msSinceLastPointerEvent: UInt64?) -> Double? {
        if candidatePending || (msSinceLastPointerEvent.map { $0 < 500 } ?? false) { return 0.05 }
        if tracked { return 0.25 }
        return nil
    }

    public static func shouldReschedule(pendingFireInMs: UInt64?, newIntervalMs: UInt64) -> Bool {
        guard let pendingFireInMs else { return true }
        return newIntervalMs < pendingFireInMs
    }
}
