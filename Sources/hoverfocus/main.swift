import AppKit
import Foundation
import HoverFocusCore
import HoverFocusPlatform

let args = CommandLine.arguments

if args.contains("--print-status") {
    var config = Config()
    var cfgErr: ConfigError?
    do {
        config = try MenuModel.loadConfig()
    } catch let err as ConfigError {
        cfgErr = err
    } catch {
        cfgErr = .invalid(path: MenuModel.configPath(), reason: error.localizedDescription)
    }

    if let err = cfgErr {
        print(MenuModel.statusLine(for: err))
        exit(0)
    }

    let controller = HoverFocusController(config: config, checks: HoverFocusController.liveChecks)
    do {
        try controller.start()
        print(controller.isPaused ? "Paused" : (config.enabled ? "Running" : "Off"))
    } catch let err as ControllerError {
        print(MenuModel.statusLine(for: err))
    } catch {
        print("Error: \(error.localizedDescription)")
    }
    controller.stop()
    exit(0)
}

if args.contains("--print-status-table") {
    MenuModel.printStatusTable()
    exit(0)
}

if args.contains("--print-config") {
    do {
        let config = try MenuModel.loadConfig()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        if let jsonStr = String(data: data, encoding: .utf8) {
            print(jsonStr)
        }
        exit(0)
    } catch let err as ConfigError {
        FileHandle.standardError.write(Data((MenuModel.statusLine(for: err) + "\n").utf8))
        exit(2)
    } catch {
        FileHandle.standardError.write(Data("Error: config \(error.localizedDescription)\n".utf8))
        exit(2)
    }
}

// Single instance check: exit 0 if another process has com.wilddog64.hoverfocus
let currentPID = ProcessInfo.processInfo.processIdentifier
let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.wilddog64.hoverfocus")
let others = running.filter { $0.processIdentifier != currentPID }
if !others.isEmpty {
    print("hoverfocus: already running (pid \(others.first?.processIdentifier ?? 0)), exiting")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
