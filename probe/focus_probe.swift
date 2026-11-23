// hoverfocus focus probe (throwaway, not part of the app).
// Question: which private SkyLight sequence gives a background window keyboard focus without raising it?
// Variants: A kCPSUserGenerated, B kCPSNoWindows, C = A + make-key records, D = B + deactivate/activate + make-key.
// Event-record byte layout (0xf8 bytes; 0x04=0xf8, 0x08=record kind, 0x20..0x2f=0xff, 0x3a=0x10, 0x3c=window id,
// 0x8a=activate/deactivate) is taken from public write-ups of the technique; written from scratch, no code copied.
// Run: swift focus_probe.swift   (needs Command Line Tools; no sudo, no Accessibility grant needed)
import AppKit
import CoreGraphics
import Darwin

typealias SetFrontFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
typealias PostFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> Int32
typealias GetPSNFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32

func sym<T>(_ lib: String, _ name: String, _: T.Type) -> T {
    guard let h = dlopen(lib, RTLD_LAZY), let p = dlsym(h, name) else {
        print("missing symbol \(name)"); exit(2)
    }
    return unsafeBitCast(p, to: T.self)
}
let sky = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
let appsvc = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
let setFront = sym(sky, "_SLPSSetFrontProcessWithOptions", SetFrontFn.self)
let postRecord = sym(sky, "SLPSPostEventRecordTo", PostFn.self)
let getPSN = sym(appsvc, "GetProcessForPID", GetPSNFn.self)

let kCPSUserGenerated: UInt32 = 0x200
let kCPSNoWindows: UInt32 = 0x400

func wait(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

func onScreen() -> [[String: Any]] {
    (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
}
func num(_ d: [String: Any], _ k: CFString) -> NSNumber? { d[k as String] as? NSNumber }

struct Win { let wid: UInt32; let pid: pid_t; let owner: String }

func windowUnderPointer() -> Win? {
    let pt = CGEvent(source: nil)?.location ?? .zero
    for d in onScreen() {
        guard num(d, kCGWindowLayer)?.intValue == 0,
              let b = d[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b), r.contains(pt),
              let wid = num(d, kCGWindowNumber)?.uint32Value,
              let pid = num(d, kCGWindowOwnerPID)?.int32Value else { continue }
        return Win(wid: wid, pid: pid, owner: d[kCGWindowOwnerName as String] as? String ?? "?")
    }
    return nil
}
func topWindow(of pid: pid_t) -> UInt32? {
    for d in onScreen() where num(d, kCGWindowLayer)?.intValue == 0 && num(d, kCGWindowOwnerPID)?.int32Value == pid {
        return num(d, kCGWindowNumber)?.uint32Value
    }
    return nil
}
func zIndex(_ wid: UInt32) -> Int? {
    onScreen().filter { num($0, kCGWindowLayer)?.intValue == 0 }.firstIndex { num($0, kCGWindowNumber)?.uint32Value == wid }
}
func psn(_ pid: pid_t) -> ProcessSerialNumber? { var p = ProcessSerialNumber(); return getPSN(pid, &p) == 0 ? p : nil }

func record(_ wid: UInt32) -> [UInt8] {
    var b = [UInt8](repeating: 0, count: 0xf8)
    b[0x04] = 0xf8
    b[0x3a] = 0x10
    withUnsafeBytes(of: wid.littleEndian) { for (i, x) in $0.enumerated() { b[0x3c + i] = x } }
    for i in 0x20..<0x30 { b[i] = 0xff }
    return b
}
func send(_ target: ProcessSerialNumber, _ bytes: [UInt8]) -> Int32 {
    var p = target
    var b = bytes
    return b.withUnsafeMutableBufferPointer { postRecord(&p, $0.baseAddress!) }
}
func makeKey(_ target: ProcessSerialNumber, _ wid: UInt32) -> [Int32] {
    var b = record(wid)
    b[0x08] = 0x01
    let r1 = send(target, b)
    b[0x08] = 0x02
    return [r1, send(target, b)]
}
func deactivateActivate(old: ProcessSerialNumber, oldWid: UInt32, new: ProcessSerialNumber, newWid: UInt32) -> [Int32] {
    var d = record(oldWid)
    d[0x8a] = 0x02
    var a = record(newWid)
    a[0x8a] = 0x01
    return [send(old, d), send(new, a)]
}

struct Row { let v: String; let calls: [Int32]; let focusApp: Bool; let raised: Bool; let typed: String }
var rows: [Row] = []
let variants = [("A", "SetFront kCPSUserGenerated"), ("B", "SetFront kCPSNoWindows"),
                ("C", "A + make-key records"), ("D", "B + deactivate/activate + make-key records")]

print("""
hoverfocus focus probe. Setup: open a TextEdit document and place this Terminal so it covers PART of the
TextEdit window. Each variant: put the pointer on the visible part of TextEdit, keep still, and the probe tries
to give TextEdit focus. Success = TextEdit gets your typing AND stays behind this Terminal.
""")
for (v, desc) in variants {
    print("\n== Variant \(v): \(desc)")
    print("Click this Terminal, press Enter, then within 4 s move the pointer onto TextEdit and keep it still.")
    _ = readLine()
    wait(4)
    guard let target = windowUnderPointer() else { print("no window under pointer; skipped"); continue }
    let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    if target.pid == frontPid || target.pid == getpid() {
        print("pointer is on the front app (\(target.owner)); skipped"); continue
    }
    guard var tp = psn(target.pid), let op = psn(frontPid), let oldWid = topWindow(of: frontPid) else {
        print("could not resolve process or window; skipped"); continue
    }
    let zBefore = zIndex(target.wid) ?? -1
    var calls: [Int32] = []
    switch v {
    case "A": calls = [setFront(&tp, target.wid, kCPSUserGenerated)]
    case "B": calls = [setFront(&tp, target.wid, kCPSNoWindows)]
    case "C": calls = [setFront(&tp, target.wid, kCPSUserGenerated)] + makeKey(tp, target.wid)
    default:
        calls = deactivateActivate(old: op, oldWid: oldWid, new: tp, newWid: target.wid)
        calls += [setFront(&tp, target.wid, kCPSNoWindows)] + makeKey(tp, target.wid)
    }
    wait(1.0)
    let focusApp = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid
    let zAfter = zIndex(target.wid) ?? -1
    let raised = zAfter >= 0 && zBefore >= 0 && zAfter < zBefore
    print("calls rc=\(calls) target=\(target.owner) frontmost-now=\(focusApp) raised=\(raised) (z \(zBefore)->\(zAfter))")
    print("Now type  abc  (do not click first). Then click this Terminal, type y if abc appeared in TextEdit, n if not, and press Enter.")
    let line = readLine() ?? ""
    let answer = line.contains("abc") ? "n (abc landed in Terminal)" : String(line.suffix(1))
    rows.append(Row(v: v, calls: calls, focusApp: focusApp, raised: raised, typed: answer))
}

let os = ProcessInfo.processInfo.operatingSystemVersionString
print("\n==== paste everything below to Claude ====")
print("host \(ProcessInfo.processInfo.hostName) · \(os) · \(Date())")
print("variant | calls rc | frontmost=target | raised | typing went to TextEdit")
for r in rows { print("\(r.v) | \(r.calls) | \(r.focusApp) | \(r.raised) | \(r.typed)") }
