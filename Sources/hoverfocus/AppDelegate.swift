import AppKit
import HoverFocusCore
import HoverFocusPlatform

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controller: HoverFocusController!
    private var config: Config = Config()
    private var configError: ConfigError?
    private var appearanceObserver: NSKeyValueObservation?
    private var accessibilityTimer: Timer?
    private var pauseTimer: Timer?
    private var accessibilityAttempts = 0

    // Menu item references
    private var statusMenuItem: NSMenuItem!
    private var enabledMenuItem: NSMenuItem!
    private var pauseMenuItem: NSMenuItem!
    private var iconSubmenu: NSMenu!
    private var iconMenuItems: [MenuBarIconStyle: NSMenuItem] = [:]
    private var grantAccessibilityMenuItem: NSMenuItem!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupMenu()
        loadConfiguration()

        controller = HoverFocusController(config: config, checks: HoverFocusController.liveChecks)

        if let button = statusItem.button {
            appearanceObserver = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                Task { @MainActor in
                    self?.updateIcon()
                }
            }
        }

        startController()
        updateUI()
    }

    private func setupMenu() {
        let menu = NSMenu()

        // 1. Status line (disabled item)
        statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())

        // 2. Enabled
        enabledMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledMenuItem.target = self
        menu.addItem(enabledMenuItem)

        // 3. Pause for 30 minutes / Resume
        pauseMenuItem = NSMenuItem(title: "Pause for 30 minutes", action: #selector(togglePause), keyEquivalent: "")
        pauseMenuItem.target = self
        menu.addItem(pauseMenuItem)
        menu.addItem(NSMenuItem.separator())

        // 4. Menu Bar Icon submenu
        let iconMenuParent = NSMenuItem(title: "Menu Bar Icon", action: nil, keyEquivalent: "")
        iconSubmenu = NSMenu()
        let styles: [(MenuBarIconStyle, String)] = [
            (.auto, "Automatic"),
            (.color, "Colour"),
            (.light, "Light bar"),
            (.dark, "Dark bar"),
        ]
        for (style, title) in styles {
            let item = NSMenuItem(title: title, action: #selector(selectIconStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            iconSubmenu.addItem(item)
            iconMenuItems[style] = item
        }
        iconMenuParent.submenu = iconSubmenu
        menu.addItem(iconMenuParent)

        // 5. Grant Accessibility…
        grantAccessibilityMenuItem = NSMenuItem(title: "Grant Accessibility…", action: #selector(grantAccessibility), keyEquivalent: "")
        grantAccessibilityMenuItem.target = self
        menu.addItem(grantAccessibilityMenuItem)
        menu.addItem(NSMenuItem.separator())

        // 6. Reload Config & Open Config
        let reloadItem = NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let openConfigItem = NSMenuItem(title: "Open Config", action: #selector(openConfig), keyEquivalent: "")
        openConfigItem.target = self
        menu.addItem(openConfigItem)
        menu.addItem(NSMenuItem.separator())

        // 7. Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func loadConfiguration() {
        do {
            config = try MenuModel.loadConfig()
            configError = nil
        } catch let err as ConfigError {
            config = Config()
            configError = err
        } catch {
            config = Config()
            configError = .invalid(path: MenuModel.configPath(), reason: error.localizedDescription)
        }
    }

    private func startController() {
        if configError != nil {
            return
        }
        do {
            try controller.start()
        } catch let err as ControllerError {
            statusMenuItem.title = MenuModel.statusLine(for: err)
        } catch {
            statusMenuItem.title = "Error: \(error.localizedDescription)"
        }
    }

    private func updateUI() {
        // Status line
        if let cfgErr = configError {
            statusMenuItem.title = MenuModel.statusLine(for: cfgErr)
        } else if !config.enabled {
            statusMenuItem.title = MenuModel.statusLine(for: .off)
        } else if controller.isPaused {
            statusMenuItem.title = MenuModel.statusLine(for: .paused)
        } else if controller.isRunning {
            statusMenuItem.title = MenuModel.statusLine(for: .running)
        }

        // Enabled state
        enabledMenuItem.state = config.enabled ? .on : .off

        // Pause state
        if controller.isPaused {
            pauseMenuItem.title = "Resume"
        } else {
            pauseMenuItem.title = "Pause for 30 minutes"
        }

        // Icon style checkmarks
        for (style, item) in iconMenuItems {
            item.state = (config.menuBarIcon == style) ? .on : .off
        }

        // Grant Accessibility item visibility
        let trusted = AccessibilityPermission.isTrusted(prompt: false)
        grantAccessibilityMenuItem.isHidden = trusted

        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let isDarkBar = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let isDimmed = !config.enabled || controller.isPaused
        let image = MenuBarIcon.makeImage(style: config.menuBarIcon, darkBar: isDarkBar, dimmed: isDimmed)
        button.image = image
    }

    @objc private func toggleEnabled() {
        config.enabled.toggle()
        controller.apply(config)
        updateUI()
    }

    @objc private func togglePause() {
        if controller.isPaused {
            controller.isPaused = false
            pauseTimer?.invalidate()
            pauseTimer = nil
        } else {
            controller.isPaused = true
            pauseTimer?.invalidate()
            pauseTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.controller.isPaused = false
                    self?.updateUI()
                }
            }
        }
        updateUI()
    }

    @objc private func selectIconStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = MenuBarIconStyle(rawValue: raw) else { return }
        config.menuBarIcon = style
        controller.apply(config)
        updateUI()
    }

    @objc private func grantAccessibility() {
        _ = AccessibilityPermission.isTrusted(prompt: true)
        accessibilityAttempts = 0
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.accessibilityAttempts += 1
                if AccessibilityPermission.isTrusted(prompt: false) {
                    self.accessibilityTimer?.invalidate()
                    self.accessibilityTimer = nil
                    self.startController()
                    self.updateUI()
                } else if self.accessibilityAttempts >= 60 {
                    self.accessibilityTimer?.invalidate()
                    self.accessibilityTimer = nil
                }
            }
        }
    }

    @objc private func reloadConfig() {
        loadConfiguration()
        controller.apply(config)
        if configError == nil {
            startController()
        }
        updateUI()
    }

    @objc private func openConfig() {
        let path = MenuModel.configPath()
        let url = MenuModel.configURL()
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            let parentDir = (path as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(Config()) {
                try? data.write(to: url)
            }
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
