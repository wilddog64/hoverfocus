import Foundation
import HoverFocusCore
import HoverFocusPlatform
import CSkyLight

var passed = 0
var failed = 0

@MainActor
func check(_ condition: Bool, _ name: String) {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("FAIL: \(name)")
    }
}

func tempFile(_ contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("hoverfocus-\(UUID().uuidString).json")
    try Data(contents.utf8).write(to: url)
    return url
}

func rejected(_ contents: String, key: String? = nil) -> Bool {
    guard let url = try? tempFile(contents) else { return false }
    defer { try? FileManager.default.removeItem(at: url) }
    do {
        _ = try ConfigLoader.load(from: url)
        return false
    } catch ConfigError.invalid(_, let reason) {
        return key.map(reason.contains) ?? true
    } catch {
        return false
    }
}

let target = WindowTarget(windowID: 2, pid: 42, bundleID: "test.app", isStandardWindow: true)
let state = SystemState(focusedWindowID: 1, menuOpen: false, missionControlActive: false)
let sample = PointerSample(x: 10, y: 10, timeMs: 100, buttonsDown: false, modifiers: [])
var engine = Engine(config: Config(dwellMs: 10))
check(engine.observe(sample, under: target, state: state) == .none, "starts before dwell")
check(engine.tick(nowMs: 109, state: state) == .none, "dwell minus one")
check(engine.tick(nowMs: 110, state: state) == .focus(target), "tick fires at dwell")
check(engine.tick(nowMs: 120, state: state) == .none, "fires once")
let laterSample = PointerSample(x: 10, y: 10, timeMs: 130, buttonsDown: false, modifiers: [])
check(engine.observe(laterSample, under: target, state: state) == .none, "stays latched after firing")
let stillLater = PointerSample(x: 10, y: 10, timeMs: 140, buttonsDown: false, modifiers: [])
check(engine.observe(stillLater, under: target, state: state) == .none, "does not fire twice in one stay")
check(engine.observe(laterSample, under: nil, state: state) == .none, "leaving target resets latch")
check(engine.observe(sample, under: target, state: state) == .none, "return starts a new dwell")
let returned = PointerSample(x: 10, y: 10, timeMs: 110, buttonsDown: false, modifiers: [])
check(engine.observe(returned, under: target, state: state) == .focus(target), "return can fire again")

var moving = Engine(config: Config(dwellMs: 10, stillnessPx: 4))
_ = moving.observe(sample, under: target, state: state)
let moved = PointerSample(x: 15, y: 10, timeMs: 105, buttonsDown: false, modifiers: [])
check(moving.observe(moved, under: target, state: state) == .none, "movement restarts dwell")
check(moving.tick(nowMs: 114, state: state) == .none, "movement dwell minus one")
check(moving.tick(nowMs: 115, state: state) == .focus(target), "movement dwell completes")

var disabled = Engine(config: Config(enabled: false, dwellMs: 0))
check(disabled.observe(sample, under: target, state: state) == .none, "disabled gate")
var ignored = Engine(config: Config(dwellMs: 0, ignoreApps: ["test.app"]))
check(ignored.observe(sample, under: target, state: state) == .none, "ignored app gate")
var paused = Engine(config: Config(dwellMs: 0, pauseModifier: .control))
let controlSample = PointerSample(x: 10, y: 10, timeMs: 100, buttonsDown: false, modifiers: .control)
check(paused.observe(controlSample, under: target, state: state) == .none, "pause modifier gate")
var noPause = Engine(config: Config(dwellMs: 0, pauseModifier: .none))
check(
    noPause.observe(controlSample, under: target, state: state) == .focus(target),
    "none modifier does not pause"
)
var menuGate = Engine(config: Config(dwellMs: 0))
check(menuGate.observe(sample, under: target, state: SystemState(
    focusedWindowID: 1, menuOpen: true, missionControlActive: false
)) == .none, "menu gate")
var missionControlGate = Engine(config: Config(dwellMs: 0))
check(missionControlGate.observe(sample, under: target, state: SystemState(
    focusedWindowID: 1, menuOpen: false, missionControlActive: true
)) == .none, "Mission Control gate")
var nilTargetGate = Engine(config: Config(dwellMs: 0))
check(nilTargetGate.observe(sample, under: nil, state: state) == .none, "nil target gate")
let nonstandard = WindowTarget(windowID: 3, pid: 42, bundleID: "test.app", isStandardWindow: false)
var nonstandardGate = Engine(config: Config(dwellMs: 0))
check(nonstandardGate.observe(sample, under: nonstandard, state: state) == .none, "non-standard target gate")

var negativeDwell = Engine(config: Config(dwellMs: -1))
check(negativeDwell.observe(sample, under: target, state: state) == .focus(target), "negative dwell clamps")
var earlyTick = Engine(config: Config(dwellMs: 10))
_ = earlyTick.observe(sample, under: target, state: state)
check(earlyTick.tick(nowMs: 99, state: state) == .none, "earlier tick is safe")

var buttonGate = Engine(config: Config(dwellMs: 0))
let down = PointerSample(x: 0, y: 0, timeMs: 1, buttonsDown: true, modifiers: [])
check(buttonGate.observe(down, under: target, state: state) == .none, "button gate")
check(buttonGate.observe(sample, under: target, state: state) == .focus(target), "button release")
var raiseEngine = Engine(config: Config(dwellMs: 0, raiseApps: ["test.app"]))
check(raiseEngine.observe(sample, under: target, state: state) == .focusAndRaise(target), "raise app")

let missingURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("hoverfocus-missing-\(UUID().uuidString).json")
check((try? ConfigLoader.load(from: missingURL)) == Config(), "missing config defaults")
check(rejected("{", key: nil), "malformed JSON rejected")
check(rejected("[]"), "top-level array rejected")
check(rejected("{\"enabled\":1}", key: "enabled"), "bridged boolean rejected")
check(rejected("{\"dwellMs\":true}", key: "dwellMs"), "boolean dwell rejected")
check(rejected("{\"dwellMs\":150.5}", key: "dwellMs"), "fractional dwell rejected")
check(rejected("{\"stillnessPx\":\"4\"}", key: "stillnessPx"), "string stillness rejected")
check(rejected("{\"unknown\":true}", key: "unknown"), "unknown key rejected")
check(rejected("{\"pauseModifier\":\"wat\"}", key: "pauseModifier"), "unknown modifier rejected")
check(rejected("{\"menuBarIcon\":\"wat\"}", key: "menuBarIcon"), "unknown icon rejected")
check(rejected("{\"dwellMs\":5001}", key: "dwellMs"), "dwell max plus one rejected")
check(rejected("{\"dwellMs\":-1}", key: "dwellMs"), "negative dwell rejected")
check(rejected("{\"stillnessPx\":201}", key: "stillnessPx"), "stillness max plus one rejected")
let unreadableURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("hoverfocus-unreadable-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: unreadableURL, withIntermediateDirectories: false)
do {
    _ = try ConfigLoader.load(from: unreadableURL)
    check(false, "directory config unreadable")
} catch ConfigError.unreadable {
    check(true, "directory config unreadable")
} catch {
    check(false, "directory config unreadable")
}
try? FileManager.default.removeItem(at: unreadableURL)
for json in ["{\"dwellMs\":0}", "{\"dwellMs\":5000}", "{\"stillnessPx\":0}", "{\"stillnessPx\":200}"] {
    guard let url = try? tempFile(json) else { check(false, "valid range file created"); continue }
    check((try? ConfigLoader.load(from: url)) != nil, "range endpoint accepted: \(json)")
    try? FileManager.default.removeItem(at: url)
}
if let partial = try? tempFile("{\"enabled\":false}") {
    let loaded = try? ConfigLoader.load(from: partial)
    check(loaded?.enabled == false && loaded?.dwellMs == Config().dwellMs, "partial config fills defaults")
    try? FileManager.default.removeItem(at: partial)
}
if let encoded = try? JSONEncoder().encode(Config()),
   let url = try? tempFile(String(decoding: encoded, as: UTF8.self)) {
    check((try? ConfigLoader.load(from: url)) == Config(), "encoded config round trips")
    try? FileManager.default.removeItem(at: url)
}

let skipSkyLight = ProcessInfo.processInfo.environment["HOVERFOCUS_SELFTEST_SKIP_SKYLIGHT"] == "1"
if skipSkyLight {
    print("skylight: skipped")
} else {
    let status = hf_skylight_resolve()
    if !status.available, let missing = status.missing_symbol {
        print("skylight: missing \(String(cString: missing))")
    }
    check(status.available && status.missing_symbol == nil, "private symbols resolve")
    let overridden = hf_skylight_resolve_with_symbol_override("_SLPSSetFrontProcessWithOptions")
    check(!overridden.available && overridden.missing_symbol != nil, "symbol override reports missing")
    check(hf_skylight_resolve().available, "override leaves real cache intact")
}
check(hf_ax_window_id(nil, nil) != 0, "AX null guards")
check(hf_focus_without_raise(-1, 0) != 0, "non-positive pid guard")

final class CheckRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func record(_ value: String) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@MainActor
func checkStart(_ checks: StartChecks, _ expected: ControllerError, _ name: String) {
    let controller = HoverFocusController(config: Config(), checks: checks)
    do {
        try controller.start()
        check(false, name)
    } catch let error as ControllerError {
        check(error == expected, name)
        check(!controller.isRunning, "not running after \(name)")
    } catch {
        check(false, name)
    }
}

@MainActor
final class FakeController: FocusControlling {
    private(set) var isRunning = false
    var isPaused = false
    var startError: ControllerError?
    var calls: [String] = []

    func start() throws {
        calls.append("start")
        guard !isRunning else { return }
        if let startError { throw startError }
        isRunning = true
    }

    func stop() {
        calls.append("stop")
        isRunning = false
    }

    func apply(_ config: Config) {
        calls.append("apply(\(config.dwellMs))")
    }
}

@MainActor
func coordinatorChecks() {
    do {
        let controller = FakeController()
        let coordinator = AppCoordinator(controller: controller, isTrusted: { true })
        coordinator.load(.success(Config(dwellMs: 200)))
        let beforeFailure = controller.calls.count
        coordinator.load(.failure(.invalid(path: "test", reason: "broken")))
        let failedCalls = Array(controller.calls.dropFirst(beforeFailure))
        check(failedCalls == ["stop"] && !controller.isRunning && coordinator.config.dwellMs == 200 && coordinator.configError != nil,
              "A1 fails closed")
        coordinator.load(.success(Config(dwellMs: 300)))
        check(controller.calls.suffix(2).elementsEqual(["apply(300)", "start"]) && controller.isRunning && coordinator.configError == nil,
              "A1 recovers")
    }
    do {
        let controller = FakeController()
        let coordinator = AppCoordinator(controller: controller, isTrusted: { true })
        coordinator.load(.success(Config(enabled: false)))
        check(controller.calls == ["apply(150)", "start"] && coordinator.configError == nil,
              "positive control disabled config starts")
    }
    do {
        let controller = FakeController()
        controller.startError = .accessibilityNotTrusted
        var trusted = false
        let coordinator = AppCoordinator(controller: controller, isTrusted: { trusted })
        coordinator.load(.success(Config()))
        for _ in 0..<100 { coordinator.trustTick() }
        let noExtraStart = controller.calls.filter { $0 == "start" }.count == 1
        trusted = true
        controller.startError = nil
        coordinator.trustTick()
        check(coordinator.startError == nil && coordinator.watchingTrust == false && controller.isRunning &&
              controller.calls.filter { $0 == "start" }.count == 2 && noExtraStart,
              "watch without a click")
    }
    do {
        let controller = FakeController()
        var trusted = false
        let coordinator = AppCoordinator(controller: controller, isTrusted: { trusted })
        coordinator.load(.failure(.invalid(path: "test", reason: "broken")))
        trusted = true
        coordinator.trustTick()
        check(controller.calls == ["stop"] && !controller.isRunning && !coordinator.watchingTrust,
              "config error stays closed")
    }
    do {
        let controller = FakeController()
        let coordinator = AppCoordinator(controller: controller, isTrusted: { true })
        coordinator.load(.success(Config()))
        check(!coordinator.watchingTrust, "trusted at launch")
    }
}

coordinatorChecks()

let trustRecorder = CheckRecorder()
checkStart(StartChecks(
    isTrusted: { trustRecorder.record("trust"); return false },
    missingPrivateSymbol: { trustRecorder.record("symbol"); return "x" },
    canListenToEvents: { trustRecorder.record("tap"); return false }
), .accessibilityNotTrusted, "trust check first")
check(trustRecorder.snapshot() == ["trust"], "later checks skipped after trust failure")

let symbolRecorder = CheckRecorder()
checkStart(StartChecks(
    isTrusted: { symbolRecorder.record("trust"); return true },
    missingPrivateSymbol: { symbolRecorder.record("symbol"); return "x" },
    canListenToEvents: { symbolRecorder.record("tap"); return false }
), .privateAPIUnavailable(symbol: "x"), "symbol check second")
check(symbolRecorder.snapshot() == ["trust", "symbol"], "tap check skipped after symbol failure")

let tapRecorder = CheckRecorder()
checkStart(StartChecks(
    isTrusted: { tapRecorder.record("trust"); return true },
    missingPrivateSymbol: { tapRecorder.record("symbol"); return nil },
    canListenToEvents: { tapRecorder.record("tap"); return false }
), .eventTapFailed, "tap check third")
check(tapRecorder.snapshot() == ["trust", "symbol", "tap"], "start checks run in order")

print("selftest: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }
