import AppKit
import ApplicationServices
import CoreFoundation
import CoreGraphics
import Foundation
import HoverFocusCore
import CSkyLight
import os

private final class TapState: @unchecked Sendable {
    private let lock = NSLock()
    private var lookupTime: UInt64 = 0
    private var cachedTarget: WindowTarget?

    func target(at now: UInt64, lookup: () -> WindowTarget?) -> WindowTarget? {
        lock.lock()
        defer { lock.unlock() }
        if now &- lookupTime >= 16 {
            cachedTarget = lookup()
            lookupTime = now
        }
        return cachedTarget
    }
}

@MainActor
public final class HoverFocusController: FocusControlling {
    public private(set) var isRunning = false
    public var isPaused = false {
        didSet {
            guard oldValue != isPaused else { return }
            if isPaused {
                indicator.reset()
                indicatorPanel.hide()
            }
            rearmTimer()
        }
    }
    private var engine: Engine
    private let checks: StartChecks
    private let tapState = TapState()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var lastPointerEventMs: UInt64?
    private var lastPointer: CGPoint?
    private var elements = RecentCache<UInt32, AXUIElement>(capacity: 32)
    private var accessibilityTreePids = RecentCache<Int32, Bool>(capacity: 256)
    private let logger = Logger(subsystem: "com.wilddog64.hoverfocus", category: "focus")
    private var indicator = FocusIndicatorModel()
    private let indicatorPanel = FocusIndicatorPanel()
    private var indicatorEnabled: Bool

    public init(config: Config, checks: StartChecks = HoverFocusController.liveChecks) {
        engine = Engine(config: config)
        self.checks = checks
        indicatorEnabled = config.enabled && config.focusIndicator
    }

    public func start() throws {
        if isRunning { return }
        guard checks.isTrusted() else { throw ControllerError.accessibilityNotTrusted }
        if let symbol = checks.missingPrivateSymbol() {
            throw ControllerError.privateAPIUnavailable(symbol: symbol)
        }
        guard checks.canListenToEvents() else { throw ControllerError.eventTapFailed }

        let mask = eventMask()
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                MainActor.assumeIsolated {
                    guard let refcon else { return }
                    let controller = Unmanaged<HoverFocusController>
                        .fromOpaque(refcon).takeUnretainedValue()
                    controller.handle(proxy, type, event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw ControllerError.eventTapFailed
        }
        tap = created
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else {
            CFMachPortInvalidate(created)
            tap = nil
            throw ControllerError.eventTapFailed
        }
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        isRunning = true
        rearmTimer()
    }

    private func eventMask() -> CGEventMask {
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp
        ]
        return types.reduce(0) { $0 | (1 << $1.rawValue) }
    }

    private func onTick() {
        guard isRunning, !isPaused else { rearmTimer(); return }
        let now = MonotonicClock.nowMs()
        let windows = onScreenWindows()
        let hasCandidate = engine.hasPendingCandidate
        let state = systemState(windows: windows, checkPermits: hasCandidate)
        let decision = engine.tick(nowMs: now, state: state)
        applyDecision(decision)
        indicator.observeFocused(state.focusedWindowID, nowMs: now)
        let mainHeight = Double(CGDisplayBounds(CGMainDisplayID()).height)
        let frame = indicator.frame(
            enabled: indicatorEnabled,
            paused: isPaused,
            bounds: { [weak self] id in self?.windowBounds(for: id, in: windows) },
            mainHeight: mainHeight
        )
        if let frame, let trackedID = indicator.trackedWindowID {
            indicatorPanel.show(
                windowFrame: NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height),
                aboveWindow: trackedID
            )
        } else {
            indicatorPanel.hide()
        }
        rearmTimer()
    }

    private func windowBounds(for windowID: UInt32, in list: [[String: Any]]) -> IndicatorRect? {
        guard let window = list.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == windowID }),
              let isOnscreen = window[kCGWindowIsOnscreen as String] as? Bool, isOnscreen,
              let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
              let dict = window[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dict) else {
            return nil
        }
        return IndicatorRect(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }

    private func handle(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard !isPaused else { return }
        let now = MonotonicClock.nowMs()
        lastPointerEventMs = now
        let point = event.location
        lastPointer = point
        let target = tapState.target(at: now) { lookup(x: point.x, y: point.y) }
        let isMouseDown = [
            CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown
        ].contains(type)
        if isMouseDown {
            indicator.mouseDown(onWindow: target?.windowID)
            if indicator.trackedWindowID == nil {
                indicatorPanel.hide()
            }
        }
        var modifiers: Modifiers = []
        if event.flags.contains(.maskControl) { modifiers.insert(.control) }
        if event.flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if event.flags.contains(.maskCommand) { modifiers.insert(.command) }
        if event.flags.contains(.maskShift) { modifiers.insert(.shift) }
        if event.flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }
        let buttonsDown: Bool = [
            CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
        ].contains(type)
        let sample = PointerSample(
            x: point.x, y: point.y, timeMs: now,
            buttonsDown: buttonsDown, modifiers: modifiers
        )
        applyDecision(
            engine.observe(sample, under: target, state: systemState(windows: onScreenWindows(), checkPermits: true)),
            onlyIfEarlier: true
        )
    }

    private func lookup(x: Double, y: Double) -> WindowTarget? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var value: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(system, Float(x), Float(y), &value)
        guard result == .success, let value else {
            enableAccessibilityTree(pid: ownerPidAt(x: x, y: y))
            return nil
        }
        var originalOwner: pid_t = 0
        AXUIElementGetPid(value, &originalOwner)
        guard CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else {
            enableAccessibilityTree(pid: originalOwner > 0 ? Int32(originalOwner) : ownerPidAt(x: x, y: y))
            return nil
        }
        let element = WindowResolver.resolve(
            hit: value,
            window: { el in
                var attr: CFTypeRef?
                guard AXUIElementCopyAttributeValue(el, kAXWindowAttribute as CFString, &attr) == .success,
                      let attr,
                      CFGetTypeID(attr) == AXUIElementGetTypeID() else { return nil }
                return unsafeDowncast(attr, to: AXUIElement.self)
            },
            role: { el in
                var attr: CFTypeRef?
                guard AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &attr) == .success,
                      let attr else { return nil }
                return attr as? String
            },
            parent: { el in
                var attr: CFTypeRef?
                guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &attr) == .success,
                      let attr,
                      CFGetTypeID(attr) == AXUIElementGetTypeID() else { return nil }
                return unsafeDowncast(attr, to: AXUIElement.self)
            }
        )
        var windowID: UInt32 = 0
        let idResult = hf_ax_window_id(Unmanaged.passUnretained(element).toOpaque(), &windowID)
        guard idResult == 0 else {
            enableAccessibilityTree(pid: originalOwner > 0 ? Int32(originalOwner) : ownerPidAt(x: x, y: y))
            return nil
        }
        var subrole: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        var owner: pid_t = 0
        AXUIElementGetPid(element, &owner)
        let app = NSRunningApplication(processIdentifier: owner)
        elements.set(element, for: windowID)
        return WindowTarget(
            windowID: windowID,
            pid: Int32(owner),
            bundleID: app?.bundleIdentifier,
            isStandardWindow: subrole as? String == kAXStandardWindowSubrole as String
        )
    }

    private func onScreenWindows() -> [[String: Any]] {
        CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    }

    private func systemState(windows: [[String: Any]], checkPermits: Bool) -> SystemState {
        let focusedWindowID = frontmostWindowID()
        let point = lastPointer
        let x = point?.x ?? 0
        let y = point?.y ?? 0
        let dockPid = windows.first(where: { $0[kCGWindowOwnerName as String] as? String == "Dock" })?[kCGWindowOwnerPID as String] as? Int
        let menuOpen = checkPermits && point != nil && menuWindowIsAt(x: x, y: y, windows: windows)
        // Mission Control detection is best effort because its window level is private system state.
        let missionControlActive = checkPermits && (dockPid.map {
            windowAtLevel(x: x, y: y, level: CGWindowLevelForKey(.dockWindow), ownerPid: $0, windows: windows)
        } ?? false)
        return SystemState(
            focusedWindowID: focusedWindowID,
            menuOpen: menuOpen,
            missionControlActive: missionControlActive
        )
    }

    private func frontmostWindowID() -> UInt32? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.2)
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused)
        guard result == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeDowncast(focused, to: AXUIElement.self)
        var windowID: UInt32 = 0
        return hf_ax_window_id(Unmanaged.passUnretained(element).toOpaque(), &windowID) == 0 ? windowID : nil
    }

    private func ownerPidAt(x: Double, y: Double) -> Int32 {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return 0 }
        let currentPid = Int(getpid())
        for window in info {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int,
                  pid != currentPid,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let left = bounds["X"], let top = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  x >= left && x <= left + width && y >= top && y <= top + height else { continue }
            return Int32(pid)
        }
        return 0
    }

    private func enableAccessibilityTree(pid: Int32) {
        guard pid > 0, pid != Int32(getpid()), accessibilityTreePids.value(for: pid) == nil else { return }
        let app = AXUIElementCreateApplication(pid_t(pid))
        AXUIElementSetMessagingTimeout(app, 0.2)
        let rc = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, true as CFTypeRef)
        accessibilityTreePids.set(true, for: pid)
        logger.info("ax-enable pid \(pid, privacy: .public) rc \(rc.rawValue, privacy: .public)")
    }

    private func menuWindowIsAt(x: CGFloat, y: CGFloat, windows: [[String: Any]]) -> Bool {
        windowAtLevel(x: x, y: y, level: CGWindowLevelForKey(.popUpMenuWindow), windows: windows) ||
            windowAtLevel(x: x, y: y, level: CGWindowLevelForKey(.mainMenuWindow), windows: windows)
    }

    private func windowAtLevel(
        x: CGFloat,
        y: CGFloat,
        level: CGWindowLevel,
        ownerPid: Int? = nil,
        windows: [[String: Any]]
    ) -> Bool {
        return windows.contains { window in
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  layer == Int(level),
                  let alpha = window[kCGWindowAlpha as String] as? Double,
                  alpha > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let left = bounds["X"], let top = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"] else { return false }
            if let ownerPid {
                guard let pid = window[kCGWindowOwnerPID as String] as? Int, pid == ownerPid else { return false }
            }
            return x >= left && x <= left + width && y >= top && y <= top + height
        }
    }

    private func applyDecision(_ decision: Decision, onlyIfEarlier: Bool = false) {
        defer { rearmTimer(onlyIfEarlier: onlyIfEarlier) }
        let target: WindowTarget
        let raise: Bool
        switch decision {
        case .none: return
        case .focus(let value): target = value; raise = false
        case .focusAndRaise(let value): target = value; raise = true
        }
        enableAccessibilityTree(pid: target.pid)
        var result: Int32
        if raise {
            let application = AXUIElementCreateApplication(pid_t(target.pid))
            let value = NSNumber(value: true)
            let appResult = AXUIElementSetAttributeValue(
                application, kAXFrontmostAttribute as CFString, value
            )
            let windowResult = elements.value(for: target.windowID).map {
                AXUIElementPerformAction($0, kAXRaiseAction as CFString)
            } ?? .failure
            result = appResult == .success && windowResult == .success ? 0 : -1
        } else {
            let frontPid = Int32(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
            let frontWid = frontmostWindowID() ?? 0
            result = Int32(hf_focus_without_raise(target.pid, target.windowID, frontPid, frontWid))
        }
        if result != 0 {
            logger.error("focus failed for window \(target.windowID, privacy: .public)")
        }
        indicator.decided(decision, succeeded: result == 0, nowMs: MonotonicClock.nowMs())
    }

    public func stop() {
        indicator.reset()
        indicatorPanel.hide()
        timer?.invalidate()
        timer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        isRunning = false
        rearmTimer()
    }

    public func apply(_ config: Config) {
        engine.update(config)
        indicatorEnabled = config.enabled && config.focusIndicator
        if !indicatorEnabled {
            indicator.reset()
            indicatorPanel.hide()
        }
        rearmTimer()
    }

    private func rearmTimer(onlyIfEarlier: Bool = false) {
        guard isRunning, !isPaused else {
            timer?.invalidate()
            timer = nil
            return
        }
        let now = MonotonicClock.nowMs()
        let since = lastPointerEventMs.map { now >= $0 ? now - $0 : 0 }
        guard let interval = TickPolicy.interval(
            candidatePending: engine.hasPendingCandidate,
            tracked: indicator.trackedWindowID != nil,
            msSinceLastPointerEvent: since
        ) else {
            timer?.invalidate()
            timer = nil
            return
        }
        let intervalMs = UInt64((interval * 1_000).rounded())
        if onlyIfEarlier {
            let pendingFireInMs = timer.map { pending in
                UInt64(max(0, (pending.fireDate.timeIntervalSinceNow * 1_000).rounded(.down)))
            }
            guard TickPolicy.shouldReschedule(pendingFireInMs: pendingFireInMs, newIntervalMs: intervalMs) else {
                return
            }
        }
        timer?.invalidate()
        timer = nil
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick() }
        }
        next.tolerance = interval * 0.15
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }

    public nonisolated static let liveChecks = StartChecks(
        isTrusted: { AccessibilityPermission.isTrusted(prompt: false) },
        missingPrivateSymbol: {
            let status = hf_skylight_resolve()
            guard !status.available, let symbol = status.missing_symbol else { return nil }
            return String(cString: symbol)
        },
        canListenToEvents: {
            let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
                userInfo: nil
            ) else { return false }
            CFMachPortInvalidate(tap)
            return true
        }
    )
}

public enum AccessibilityPermission {
    public static func isTrusted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }
}
