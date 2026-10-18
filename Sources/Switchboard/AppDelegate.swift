import AppKit
import os
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let switcher = Switcher()
    private var statusItem: NSStatusItem!
    /// Nil when another app holds ⌃⌥⌘B exclusively; the menu then says so.
    private(set) var hotKey: HotKey?
    // menuNeedsUpdate is synchronous, so the menu is built from this list, refreshed on launch,
    // after each action and on every screen change.
    var screens: [Display] = []
    private var failed = false
    private var leaving = false
    private var reading = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        hotKey = HotKey { [weak self] in self?.backToComputer() }
        switcher.onKeptRead = { [weak self] in self?.updateIcon() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screensChanged), name: NSWorkspace.didWakeNotification, object: nil
        )
        // The same check as a screen change, so screens left off by a crash come back when none is on.
        checkScreens()
        if switcher.config.screens.isEmpty { setUp() }
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
            if screen == nil, !display.isBuiltin {
                add("Set Up This Screen…", #selector(setUp), to: sub)
                sub.addItem(.separator())
            }
            for (title, choice) in choices(for: display) {
                let row = add(title, #selector(pick(_:)), to: sub)
                row.representedObject = (display, choice)
                row.state = choice == current ? .on : .off
            }
            item.submenu = sub
            menu.addItem(item)
        }

        menu.addItem(.separator())
        if hotKey == nil {
            add("Back to Computer", #selector(backToComputer), to: menu)
            menu.addItem(withTitle: "Another app uses ⌃⌥⌘B", action: nil, keyEquivalent: "").isEnabled = false
        } else {
            let back = add("Back to Computer", #selector(backToComputer), to: menu, key: "b")
            back.keyEquivalentModifierMask = [.control, .option, .command]
        }
        let modes = NSMenu()
        for (title, value) in [("Sleep", Config.NoScreenMode.sleep), ("Keep Running", .keepRunning)] {
            let row = add(title, #selector(pickMode(_:)), to: modes)
            row.representedObject = value
            row.state = switcher.config.noScreenMode == value ? .on : .off
        }
        menu.addItem(withTitle: "When No Screen Is Left", action: nil, keyEquivalent: "").submenu = modes
        let login = add("Open at Login", #selector(toggleLogin(_:)), to: menu)
        // Mixed: registered, but the user turned it off in Login Items, so a click opens that pane.
        let status = SMAppService.mainApp.status
        login.state = status == .enabled ? .on : status == .requiresApproval ? .mixed : .off
        add("Ask Before Links", #selector(toggleAskBeforeLinks), to: menu).state = switcher.config.askBeforeLinks ? .on : .off
        menu.addItem(.separator())
        add("Open Window", #selector(openWindow), to: menu, key: "o")
        add("Set Up Screens…", #selector(setUp), to: menu, key: ",")
        add("Quit Switchboard", #selector(NSApplication.terminate(_:)), to: menu, key: "q").target = NSApp
    }

    // Reads each enabled, set-up screen's input so the checkmarks follow the screen's own button.
    // ponytail: the menu is built first, so a change shows on the next open; set item states in place to fix.
    func menuWillOpen(_ menu: NSMenu) {
        guard !reading else { return }
        reading = true
        switcher.readInputs(of: Set(switcher.config.screens.keys)) { [weak self] in
            self?.reading = false
            self?.updateIcon()
        }
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? Config.NoScreenMode else { return }
        switcher.config.noScreenMode = mode
    }

    @objc func backToComputer() {
        switcher.backToComputer(done: finish)
    }

    /// One change sends a burst of notifications, so the screens are checked once, 1 s after the last.
    @objc private func screensChanged() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(checkScreens), object: nil)
        perform(#selector(checkScreens), with: nil, afterDelay: 1, inModes: [.common])
    }

    // A screen change follows each switch, so a change with no error keeps the warning of a failed switch.
    @objc private func checkScreens() {
        switcher.screensChanged { [weak self] error in
            guard let self else { return }
            if error == nil, failed { refresh() } else { finish(error) }
        }
    }

    func finish(_ error: String?) {
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
        ControlWindow.update(controlView())
    }

    @objc func setUp() {
        SetupWindow.show(switcher: switcher) { [weak self] in self?.refresh() }
    }

    // Every way out (Quit, logout, restart) brings the screens back first and waits for it here,
    // so applicationWillTerminate has nothing left to do. The flag stops a second run.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !leaving else { return .terminateLater }
        leaving = true
        // ponytail: errors only go to the log on the way out; save them and show them at the next launch if users miss them.
        switcher.backToComputer { error in
            if let error { Logger.app.error("Back to Computer at quit: \(error, privacy: .public)") }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func showError(_ message: String) {
        runAlert {
            let alert = NSAlert()
            alert.messageText = "Switchboard"
            alert.informativeText = message
            alert.alertStyle = .warning
            return alert
        }
    }
}

/// Shows the alert from a run-loop block. A modal alert started inside a main-queue block, such as a
/// `Switcher.run` callback, stops every other main-queue block until it closes: the hotkey's result,
/// the menu bar state and the reply to Quit would wait for the user.
@MainActor
func runAlert(
    _ make: @escaping @MainActor () -> NSAlert,
    then: @escaping @MainActor (NSAlert, NSApplication.ModalResponse) -> Void = { _, _ in }
) {
    RunLoop.main.perform(inModes: [.common]) {
        MainActor.assumeIsolated {
            let alert = make()
            NSApp.bringToFront()
            then(alert, alert.runModal())
        }
    }
}

extension NSApplication {
    // ponytail: activate(ignoringOtherApps:) is deprecated in macOS 14 but still brings an accessory app
    // to the front; switch to activate() when the minimum is macOS 14 and it is enough there.
    func bringToFront() {
        activate(ignoringOtherApps: true)
    }
}
