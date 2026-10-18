import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let switcher = Switcher()
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    // menuNeedsUpdate is synchronous, so the menu is built from this list, refreshed on launch,
    // after each action and on every screen change.
    private var screens: [Display] = []
    private var failed = false
    private var leaving = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        hotKey = HotKey { [weak self] in self?.backToComputer() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        refresh()
        if switcher.config.screens.isEmpty { setUp() }
        if hotKey == nil { showError("Another app uses ⌃⌥⌘B, so Back to Computer has no shortcut. Use the menu.") }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Screens", action: nil, keyEquivalent: "").isEnabled = false

        for display in screens {
            let screen = switcher.config.screens[display.key]
            let current = switcher.config.choice(for: display.key)
            let item = NSMenuItem(title: screen?.name ?? display.name, action: nil, keyEquivalent: "")
            item.image = NSImage(
                systemSymbolName: display.isBuiltin ? "laptopcomputer" : "display", accessibilityDescription: nil
            )
            let sub = NSMenu()
            let choices: [(String, Config.Choice)] = [("Mac", .mac)]
                + (screen?.devices ?? []).map { ($0.name, .device($0.input)) } + [("Off", .off)]
            for (title, choice) in choices {
                let row = add(title, #selector(pick(_:)), to: sub)
                row.representedObject = (display, choice)
                row.state = choice == current ? .on : .off
            }
            item.submenu = sub
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let back = add("Back to Computer", #selector(backToComputer), to: menu, key: "b")
        back.keyEquivalentModifierMask = [.control, .option, .command]
        let modes = NSMenu()
        for (title, value) in [("Sleep", Config.NoScreenMode.sleep), ("Keep Running", .keepRunning)] {
            let row = add(title, #selector(pickMode(_:)), to: modes)
            row.representedObject = value
            row.state = switcher.config.noScreenMode == value ? .on : .off
        }
        menu.addItem(withTitle: "When No Screen Is Left", action: nil, keyEquivalent: "").submenu = modes
        menu.addItem(.separator())
        add("Set Up Screens…", #selector(setUp), to: menu, key: ",")
        add("Quit Switchboard", #selector(NSApplication.terminate(_:)), to: menu, key: "q").target = NSApp
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let (display, choice) = sender.representedObject as? (Display, Config.Choice) else { return }
        switcher.switchScreen(display, to: choice, done: finish)
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? Config.NoScreenMode else { return }
        switcher.config.noScreenMode = mode
    }

    @objc private func backToComputer() {
        switcher.backToComputer(done: finish)
    }

    @objc private func screensChanged() {
        switcher.screensChanged(done: finish)
    }

    private func finish(_ error: String?) {
        failed = error != nil
        refresh()
        if let error { showError(error) }
    }

    private func refresh() {
        switcher.displays { [weak self] list in
            self?.screens = list
            self?.updateIcon()
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let config = switcher.config
        let names = screens.map { display -> String in
            switch config.choice(for: display.key) {
            case .mac: return "Mac"
            case .off: return "Off"
            case .device(let input):
                return config.screens[display.key]?.devices.first { $0.input == input }?.name ?? "Input \(input)"
            }
        }
        let away = names.contains { $0 != "Mac" }
        let state = away ? "Screens show \(names.joined(separator: ", "))" : "All screens show the Mac"
        let words = "Switchboard. " + (failed ? "The last action failed. " : "") + state
        button.image = NSImage(
            systemSymbolName: failed ? "exclamationmark.triangle" : "display.2", accessibilityDescription: words
        )
        button.image?.isTemplate = true
        button.title = away ? names.joined(separator: " · ") : ""
        button.setAccessibilityLabel(words)
        button.toolTip = words
    }

    @objc private func setUp() {
        SetupWindow.show(switcher: switcher) { [weak self] in self?.refresh() }
    }

    // Every way out (Quit, logout, restart) brings the screens back first and waits for it here,
    // so applicationWillTerminate has nothing left to do. The flag stops a second run.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !leaving else { return .terminateLater }
        leaving = true
        // ponytail: errors are dropped on the way out; an alert while quitting would not help much.
        switcher.backToComputer { _ in sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Switchboard"
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
