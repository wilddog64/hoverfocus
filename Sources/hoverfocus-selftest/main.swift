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

var sameAppEngine = Engine(config: Config(dwellMs: 10))
let sameAppTarget = WindowTarget(windowID: 7, pid: 42, bundleID: "test.app", isStandardWindow: true)
let sameAppState = SystemState(focusedWindowID: 3, menuOpen: false, missionControlActive: false)
_ = sameAppEngine.observe(sample, under: sameAppTarget, state: sameAppState)
check(sameAppEngine.tick(nowMs: 110, state: sameAppState) == .focus(sameAppTarget), "Engine same-app different window focuses")
var sameWindowEngine = Engine(config: Config(dwellMs: 10))
let sameWindowTarget = WindowTarget(windowID: 3, pid: 42, bundleID: "test.app", isStandardWindow: true)
_ = sameWindowEngine.observe(sample, under: sameWindowTarget, state: sameAppState)
check(sameWindowEngine.tick(nowMs: 110, state: sameAppState) == .none, "Engine same-app same window stays none")

var recent = RecentCache<String, Int>(capacity: 2)
recent.set(1, for: "a"); recent.set(2, for: "b"); _ = recent.value(for: "a"); recent.set(3, for: "c")
check(recent.value(for: "b") == nil && recent.value(for: "a") == 1 && recent.value(for: "c") == 3 && recent.count == 2,
      "RecentCache hit refreshes recency and evicts least recent")
recent.set(10, for: "a"); recent.set(3, for: "c")
check(recent.value(for: "a") == 10 && recent.value(for: "c") == 3 && recent.count == 2,
      "RecentCache replacement preserves count")
var oneRecent = RecentCache<Int, Int>(capacity: 1)
oneRecent.set(1, for: 1); oneRecent.set(2, for: 2)
check(oneRecent.count == 1 && oneRecent.value(for: 2) == 2 && oneRecent.value(for: 1) == nil, "RecentCache capacity one")

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
final class OpsLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    private var records: [[UInt8]] = []
    private var psns: [[UInt32]] = []
    private var codes: [String: [Int32]] = [:]
    private var requestedPid: Int32 = 0
    func reset() { lock.lock(); values = []; records = []; psns = []; codes = [:]; requestedPid = 0; lock.unlock() }
    func append(_ value: String) { lock.lock(); values.append(value); lock.unlock() }
    func addRecord(_ bytes: [UInt8]) { lock.lock(); records.append(bytes); lock.unlock() }
    func addPSN(_ value: UnsafeMutablePointer<hf_psn>?) { lock.lock(); if let value { psns.append([value.pointee.high, value.pointee.low]) }; lock.unlock() }
    func result(_ key: String, index: Int) -> Int32 { lock.lock(); defer { lock.unlock() }; return codes[key].flatMap { index < $0.count ? $0[index] : nil } ?? 0 }
    func setCodes(_ key: String, _ value: [Int32]) { lock.lock(); codes[key] = value; lock.unlock() }
    func setPid(_ value: Int32) { lock.lock(); requestedPid = value; lock.unlock() }
    func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return values }
    func recordSnapshot() -> [[UInt8]] { lock.lock(); defer { lock.unlock() }; return records }
    func psnSnapshot() -> [[UInt32]] { lock.lock(); defer { lock.unlock() }; return psns }
    func pid() -> Int32 { lock.lock(); defer { lock.unlock() }; return requestedPid }
}
enum OpsFixture { static let log = OpsLog() }
func fakeGetPSN(_ pid: Int32, _ psn: UnsafeMutablePointer<hf_psn>?) -> Int32 {
    OpsFixture.log.append("get_psn"); OpsFixture.log.setPid(pid)
    psn?.pointee.high = 0x1234; psn?.pointee.low = 0x5678
    return OpsFixture.log.result("get", index: 0)
}
func fakeSetFront(_ psn: UnsafeMutablePointer<hf_psn>?, _ wid: UInt32, _ mode: UInt32) -> Int32 {
    OpsFixture.log.addPSN(psn)
    OpsFixture.log.append("set_front(\(wid), \(mode))")
    return OpsFixture.log.result("set", index: 0)
}
func fakePost(_ psn: UnsafeMutablePointer<hf_psn>?, _ record: UnsafeMutablePointer<UInt8>?) -> Int32 {
    OpsFixture.log.addPSN(psn)
    let bytes = record.map { Array(UnsafeBufferPointer(start: $0, count: Int(HF_RECORD_SIZE))) } ?? []
    OpsFixture.log.addRecord(bytes)
    let label: String
    if bytes.count > 0x8a && bytes[0x08] == 0x0d { label = bytes[0x8a] == 2 ? "deactivate" : "activate" }
    else { label = "make-key \(bytes.count > 8 ? bytes[0x08] : 0)" }
    OpsFixture.log.append("post(\(label) \(bytes.count > 0x3f ? UInt32(bytes[0x3c]) | UInt32(bytes[0x3d]) << 8 | UInt32(bytes[0x3e]) << 16 | UInt32(bytes[0x3f]) << 24 : 0))")
    let posts = OpsFixture.log.snapshot().filter { $0.hasPrefix("post(") }.count - 1
    return OpsFixture.log.result("post", index: posts)
}
func fakeSleep(_ microseconds: UInt32) { OpsFixture.log.append("sleep(\(microseconds))") }
var fakeOps = hf_focus_ops(get_psn: fakeGetPSN, set_front: fakeSetFront, post: fakePost, sleep_us: fakeSleep)

func expectedRecord(phase: UInt8, wid: UInt32, key: Bool) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: Int(HF_RECORD_SIZE))
    bytes[4] = 0xf8; bytes[8] = phase
    if key { bytes[0x3a] = 0x10; for i in 0..<16 { bytes[0x20 + i] = 0xff } }
    for i in 0..<4 { bytes[0x3c + i] = UInt8(truncatingIfNeeded: wid >> (8 * i)) }
    if phase == 0x0d { bytes[0x8a] = wid == 3 ? 2 : 1 }
    return bytes
}
var record = [UInt8](repeating: 0xaa, count: Int(HF_RECORD_SIZE))
record.withUnsafeMutableBufferPointer { hf_record_make_key($0.baseAddress, 7, 1) }
let keyOne = record == expectedRecord(phase: 1, wid: 7, key: true)
record = [UInt8](repeating: 0xaa, count: Int(HF_RECORD_SIZE))
record.withUnsafeMutableBufferPointer { hf_record_make_key($0.baseAddress, 7, 2) }
let keyTwo = record == expectedRecord(phase: 2, wid: 7, key: true)
record = [UInt8](repeating: 0xaa, count: Int(HF_RECORD_SIZE))
record.withUnsafeMutableBufferPointer { hf_record_activation($0.baseAddress, 3, false) }
let deactivateCorrect = record == expectedRecord(phase: 0x0d, wid: 3, key: false)
record = [UInt8](repeating: 0xaa, count: Int(HF_RECORD_SIZE))
record.withUnsafeMutableBufferPointer { hf_record_activation($0.baseAddress, 7, true) }
let activateCorrect = record == expectedRecord(phase: 0x0d, wid: 7, key: false)
hf_record_make_key(nil, 7, 1); hf_record_activation(nil, 7, true)
check(keyOne && keyTwo && deactivateCorrect && activateCorrect, "record layouts and zeroing")

OpsFixture.log.reset()
let differentRC = hf_focus_sequence(&fakeOps, 10, 7, 20, 3)
check(differentRC == 0 && OpsFixture.log.snapshot() == ["get_psn", "set_front(7, 512)", "post(make-key 1 7)", "post(make-key 2 7)"], "focus different-app order")
OpsFixture.log.reset()
let sameRC = hf_focus_sequence(&fakeOps, 10, 7, 10, 3)
check(sameRC == 0 && OpsFixture.log.snapshot() == ["get_psn", "post(deactivate 3)", "sleep(40000)", "post(activate 7)", "set_front(7, 512)", "post(make-key 1 7)", "post(make-key 2 7)"], "focus same-app order")
check(OpsFixture.log.recordSnapshot().allSatisfy { $0.count == Int(HF_RECORD_SIZE) }, "post copies complete record bytes")
check(OpsFixture.log.pid() == 10 && OpsFixture.log.psnSnapshot().count == 5 &&
      OpsFixture.log.psnSnapshot().allSatisfy { $0 == [0x1234, 0x5678] }, "PSN plumbing")
OpsFixture.log.reset(); _ = hf_focus_sequence(&fakeOps, 10, 7, 10, 0)
check(OpsFixture.log.snapshot() == ["get_psn", "set_front(7, 512)", "post(make-key 1 7)", "post(make-key 2 7)"], "same-app without front window")
OpsFixture.log.reset(); _ = hf_focus_sequence(&fakeOps, 10, 7, 10, 7)
check(OpsFixture.log.snapshot() == ["get_psn", "set_front(7, 512)", "post(make-key 1 7)", "post(make-key 2 7)"], "same-app same window")
OpsFixture.log.reset(); _ = hf_focus_sequence(&fakeOps, 0, 7, 0, 0); _ = hf_focus_sequence(&fakeOps, -1, 7, 0, 0)
check(OpsFixture.log.snapshot().isEmpty, "focus invalid pid guards")
check(hf_focus_sequence(nil, 10, 7, 0, 0) == -1, "focus null ops guard")
OpsFixture.log.reset(); OpsFixture.log.setCodes("get", [-1])
check(hf_focus_sequence(&fakeOps, 10, 7, 20, 3) == -1 && OpsFixture.log.snapshot() == ["get_psn"], "get psn error stops")
OpsFixture.log.reset(); OpsFixture.log.setCodes("set", [1002])
check(hf_focus_sequence(&fakeOps, 10, 7, 20, 3) == 1002 && OpsFixture.log.snapshot().count == 4, "errors do not stop sequence")
OpsFixture.log.reset(); OpsFixture.log.setCodes("post", [5, 0, 0, 0]); OpsFixture.log.setCodes("set", [1002])
check(hf_focus_sequence(&fakeOps, 10, 7, 10, 3) == 5 && OpsFixture.log.snapshot().count == 7, "first rc wins")
var nullSleepOps = hf_focus_ops(get_psn: fakeGetPSN, set_front: fakeSetFront, post: fakePost, sleep_us: nil)
OpsFixture.log.reset()
check(hf_focus_sequence(&nullSleepOps, 10, 7, 0, 0) == -1 && OpsFixture.log.snapshot().isEmpty, "null op guard")
if skipSkyLight {
    print("skylight: skipped")
} else {
    let status = hf_skylight_resolve()
    if !status.available, let missing = status.missing_symbol {
        print("skylight: missing \(String(cString: missing))")
    }
    check(status.available && status.missing_symbol == nil, "private symbols resolve")
    let overridden = hf_skylight_resolve_with_symbol_override("SLPSPostEventRecordTo")
    check(!overridden.available && String(cString: overridden.missing_symbol!) == "SLPSPostEventRecordTo", "post symbol override reports missing")
    check(hf_skylight_resolve().available, "override leaves real cache intact")
}
check(hf_ax_window_id(nil, nil) != 0, "AX null guards")
check(hf_focus_without_raise(-1, 0, 0, 0) != 0, "non-positive pid guard")

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
    do {
        var notifier = ErrorNotifier()
        let a = Health.configError(.invalid(path: "a", reason: "one"))
        let b = Health.configError(.invalid(path: "a", reason: "two"))
        let access = Health.startError(.accessibilityNotTrusted)
        let tap = Health.startError(.eventTapFailed)
        check(notifier.observe(.ok) == nil, "Notifier ok stays quiet")
        check(notifier.observe(a) == a, "Notifier ok to config announces")
        check(notifier.observe(a) == nil, "Notifier same config stays quiet")
        check(notifier.observe(b) == b, "Notifier changed config announces")
        check(notifier.observe(access) == access, "Notifier config to start announces")
        check(notifier.observe(tap) == tap, "Notifier changed start error announces")
        check(notifier.observe(tap) == nil, "Notifier same start error stays quiet")
        check(notifier.observe(.ok) == nil, "Notifier error to ok stays quiet")
        check(notifier.observe(tap) == tap, "Notifier same error after ok announces")
    }
    do {
        let controller = FakeController()
        var trusted = true
        let coordinator = AppCoordinator(controller: controller, isTrusted: { trusted })
        coordinator.load(.success(Config()))
        trusted = false
        coordinator.trustTick()
        check(controller.calls.filter { $0 == "stop" }.count == 1 && !controller.isRunning &&
              coordinator.startError == .accessibilityNotTrusted && coordinator.watchingTrust &&
              coordinator.health == .startError(.accessibilityNotTrusted), "Loss detected")
    }
    do {
        let controller = FakeController()
        var trusted = true
        let coordinator = AppCoordinator(controller: controller, isTrusted: { trusted })
        coordinator.load(.success(Config()))
        trusted = false
        coordinator.trustTick()
        let startsAtLoss = controller.calls.filter { $0 == "start" }.count
        trusted = true
        coordinator.trustTick()
        check(controller.calls.filter { $0 == "start" }.count == startsAtLoss + 1 && controller.isRunning &&
              coordinator.health == .ok, "Loss recovers")
    }
    do {
        let controller = FakeController()
        var trusted = true
        let coordinator = AppCoordinator(controller: controller, isTrusted: { trusted })
        coordinator.load(.success(Config()))
        trusted = false
        coordinator.load(.success(Config()))
        let stillRunning = controller.isRunning && coordinator.watchingTrust
        coordinator.trustTick()
        check(stillRunning && controller.calls.filter { $0 == "stop" }.count == 1 &&
              coordinator.health == .startError(.accessibilityNotTrusted), "Reload while lost")
    }
    do {
        let offController = FakeController()
        offController.startError = .accessibilityNotTrusted
        let offCoordinator = AppCoordinator(controller: offController, isTrusted: { false })
        offCoordinator.load(.success(Config(enabled: false)))
        let pausedController = FakeController()
        pausedController.startError = .accessibilityNotTrusted
        pausedController.isPaused = true
        let pausedCoordinator = AppCoordinator(controller: pausedController, isTrusted: { false })
        pausedCoordinator.load(.success(Config()))
        check(offCoordinator.health == .ok && pausedCoordinator.health == .ok, "Off/Paused stay quiet")
    }
    do {
        let controller = FakeController()
        let coordinator = AppCoordinator(controller: controller, isTrusted: { true })
        coordinator.load(.success(Config()))
        for _ in 0..<100 { coordinator.trustTick() }
        check(controller.calls.filter { $0 == "stop" }.isEmpty &&
              controller.calls.filter { $0 == "start" }.count == 1, "No false loss")
    }
    do {
        let controller = FakeController()
        controller.startError = .eventTapFailed
        let coordinator = AppCoordinator(controller: controller, isTrusted: { true })
        coordinator.load(.success(Config()))
        coordinator.load(.failure(.invalid(path: "test", reason: "broken")))
        let configWins = coordinator.health == .configError(.invalid(path: "test", reason: "broken"))
        check(configWins, "Health precedence config error wins")
        let runningController = FakeController()
        runningController.startError = .eventTapFailed
        let runningCoordinator = AppCoordinator(controller: runningController, isTrusted: { true })
        runningCoordinator.load(.success(Config()))
        runningController.startError = nil
        try? runningController.start()
        check(runningController.isRunning && runningCoordinator.health == .ok,
              "Health precedence running hides start error")
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

@MainActor
func windowResolverChecks() {
    do {
        var role: [Int: String] = [20: "AXWindow", 21: "AXApplication"]
        for i in 0...19 { role[i] = "AXGroup" }
        var parent: [Int: Int] = [:]
        for i in 0...21 { parent[i] = i + 1 }
        let windowAttr = [0: 20]
        let result = WindowResolver.resolve(
            hit: 0,
            window: { windowAttr[$0] },
            role: { role[$0] },
            parent: { parent[$0] }
        )
        check(result == 20, "Resolver deep content uses window attribute")
    }
    do {
        var role: [Int: String] = [4: "AXWindow", 5: "AXApplication"]
        for i in 0...3 { role[i] = "AXGroup" }
        var parent: [Int: Int] = [:]
        for i in 0...10 { parent[i] = i + 1 }
        let windowAttr: [Int: Int] = [:]
        let result = WindowResolver.resolve(
            hit: 0,
            window: { windowAttr[$0] },
            role: { role[$0] },
            parent: { parent[$0] }
        )
        check(result == 4, "Resolver shallow walk finds window")
    }
    do {
        var role: [Int: String] = [20: "AXWindow", 21: "AXApplication"]
        for i in 0...19 { role[i] = "AXGroup" }
        var parent: [Int: Int] = [:]
        for i in 0...21 { parent[i] = i + 1 }
        let windowAttr: [Int: Int] = [:]
        let result = WindowResolver.resolve(
            hit: 0,
            window: { windowAttr[$0] },
            role: { role[$0] },
            parent: { parent[$0] }
        )
        check(result == 8, "Resolver deep fallback stops after 8 steps")
    }
    do {
        var role: [Int: String] = [3: "AXWindow", 4: "AXApplication"]
        for i in 0...2 { role[i] = "AXGroup" }
        var parent: [Int: Int] = [:]
        for i in 0...10 { parent[i] = i + 1 }
        let windowAttr = [0: 1]
        let result = WindowResolver.resolve(
            hit: 0,
            window: { windowAttr[$0] },
            role: { role[$0] },
            parent: { parent[$0] }
        )
        check(result == 3, "Resolver ignores non-window attribute")
    }
    do {
        let role = [0: "AXWindow", 1: "AXApplication"]
        var parent: [Int: Int] = [:]
        for i in 0...10 { parent[i] = i + 1 }
        let windowAttr: [Int: Int] = [:]
        let result = WindowResolver.resolve(
            hit: 0,
            window: { windowAttr[$0] },
            role: { role[$0] },
            parent: { parent[$0] }
        )
        check(result == 0, "Resolver hit is the window")
    }
    do {
        var role: [Int: String] = [:]
        for i in 0...2 { role[i] = "AXGroup" }
        let parent = [0: 1, 1: 2]
        let windowAttr: [Int: Int] = [:]
        let result = WindowResolver.resolve(
            hit: 0,
            window: { windowAttr[$0] },
            role: { role[$0] },
            parent: { parent[$0] }
        )
        check(result == 2, "Resolver walk stops at nil parent")
    }
}

windowResolverChecks()

print("selftest: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }
