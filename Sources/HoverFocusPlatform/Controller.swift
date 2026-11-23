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
    public var isPaused = false
    private var engine: Engine
    private let checks: StartChecks
    private let tapState = TapState()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var lastPointer: CGPoint?
    private var elements: [UInt32: AXUIElement] = [:]
    private let logger = Logger(subsystem: "com.wilddog64.hoverfocus", category: "focus")

    public init(config: Config, checks: StartChecks = HoverFocusController.liveChecks) {
        engine = Engine(config: config)
        self.checks = checks
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
        isRunning = true
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
        guard !isPaused else { return }
        let state = systemState()
        let decision = engine.tick(nowMs: MonotonicClock.nowMs(), state: state)
        applyDecision(decision)
    }

    private func handle(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard !isPaused else { return }
        let now = MonotonicClock.nowMs()
        let point = event.location
        lastPointer = point
        let target = tapState.target(at: now) { lookup(x: point.x, y: point.y) }
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
        applyDecision(engine.observe(sample, under: target, state: systemState()))
    }

    private func lookup(x: Double, y: Double) -> WindowTarget? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var value: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(system, Float(x), Float(y), &value)
        guard result == .success, let value,
              CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
        var element = value
        for _ in 0..<8 {
            var role: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            if role as? String == kAXWindowRole as String { break }
            var parent: CFTypeRef?
            let parentResult = AXUIElementCopyAttributeValue(
                element, kAXParentAttribute as CFString, &parent
            )
            guard parentResult == .success, let parent,
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            element = unsafeBitCast(parent, to: AXUIElement.self)
        }
        var windowID: UInt32 = 0
        let idResult = hf_ax_window_id(Unmanaged.passUnretained(element).toOpaque(), &windowID)
        guard idResult == 0 else { return nil }
        var subrole: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        var owner: pid_t = 0
        AXUIElementGetPid(element, &owner)
        let app = NSRunningApplication(processIdentifier: owner)
        elements[windowID] = element
        return WindowTarget(
            windowID: windowID,
            pid: Int32(owner),
            bundleID: app?.bundleIdentifier,
            isStandardWindow: subrole as? String == kAXStandardWindowSubrole as String
        )
    }

    private func systemState() -> SystemState {
        var focusedWindowID: UInt32?
        if let app = NSWorkspace.shared.frontmostApplication {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            var focused: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                application, kAXFocusedWindowAttribute as CFString, &focused
            )
            if result == .success, let focused,
               CFGetTypeID(focused) == AXUIElementGetTypeID() {
                let element = unsafeBitCast(focused, to: AXUIElement.self)
                var windowID: UInt32 = 0
                if hf_ax_window_id(Unmanaged.passUnretained(element).toOpaque(), &windowID) == 0 {
                    focusedWindowID = windowID
                }
            }
        }
        let point = lastPointer
        let x = point?.x ?? 0
        let y = point?.y ?? 0
        let menuOpen = point != nil && menuWindowIsAt(x: x, y: y)
        // Mission Control detection is best effort because its window level is private system state.
        let missionControlActive = windowAtLevel(
            x: x, y: y, level: CGWindowLevelForKey(.dockWindow), owner: "com.apple.dock"
        )
        return SystemState(
            focusedWindowID: focusedWindowID,
            menuOpen: menuOpen,
            missionControlActive: missionControlActive
        )
    }

    private func menuWindowIsAt(x: CGFloat, y: CGFloat) -> Bool {
        windowAtLevel(x: x, y: y, level: CGWindowLevelForKey(.popUpMenuWindow)) ||
            windowAtLevel(x: x, y: y, level: CGWindowLevelForKey(.mainMenuWindow))
    }

    private func windowAtLevel(
        x: CGFloat,
        y: CGFloat,
        level: CGWindowLevel,
        owner: String? = nil
    ) -> Bool {
        guard let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] else { return false }
        return info.contains { window in
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  layer == Int(level),
                  let alpha = window[kCGWindowAlpha as String] as? Double,
                  alpha > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let left = bounds["X"], let top = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"] else { return false }
            if let owner {
                guard let pid = window[kCGWindowOwnerPID as String] as? Int,
                      NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier == owner else {
                    return false
                }
            }
            return x >= left && x <= left + width && y >= top && y <= top + height
        }
    }

    private func applyDecision(_ decision: Decision) {
        let target: WindowTarget
        let raise: Bool
        switch decision {
        case .none: return
        case .focus(let value): target = value; raise = false
        case .focusAndRaise(let value): target = value; raise = true
        }
        var result: Int32
        if raise {
            let application = AXUIElementCreateApplication(pid_t(target.pid))
            let value = NSNumber(value: true)
            let appResult = AXUIElementSetAttributeValue(
                application, kAXFrontmostAttribute as CFString, value
            )
            let windowResult = elements[target.windowID].map {
                AXUIElementPerformAction($0, kAXRaiseAction as CFString)
            } ?? .failure
            result = appResult == .success && windowResult == .success ? 0 : -1
        } else {
            result = Int32(hf_focus_without_raise(target.pid, target.windowID))
        }
        if result != 0 {
            logger.error("focus failed for window \(target.windowID, privacy: .public)")
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        isRunning = false
    }

    public func apply(_ config: Config) {
        engine.update(config)
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
