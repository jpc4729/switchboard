import AppKit
import ServiceManagement

extension AppDelegate {
    @objc func pick(_ sender: NSMenuItem) {
        guard let (display, choice) = sender.representedObject as? (Display, Config.Choice) else { return }
        pick(display, choice)
    }

    /// The one switch path for the menu, the window and links.
    func pick(_ display: Display, _ choice: Config.Choice) {
        guard confirmLidClosed(for: display, to: choice) else { return }
        switcher.switchScreen(display, to: choice, done: finish)
    }

    /// Mac, each set-up device, then Off, in the order the menu and the window show them.
    func choices(for display: Display) -> [(title: String, choice: Config.Choice)] {
        let devices = switcher.config.screens[display.key]?.devices ?? []
        return [("Mac", .mac)] + devices.map { ($0.name, .device($0.input)) } + [("Off", .off)]
    }

    @objc func openWindow() {
        ControlWindow.show(controlView())
    }

    /// Opening the app again, for example from Finder, shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWindow()
        return false
    }

    func controlView() -> ControlView {
        let config = switcher.config
        let rows = screens.map { display in
            ControlView.Row(
                display: display, name: config.screens[display.key]?.name ?? display.name,
                choices: choices(for: display), current: config.choice(for: display.key)
            )
        }
        return ControlView(
            rows: rows,
            pick: { [weak self] in self?.pick($0, $1) },
            back: { [weak self] in self?.backToComputer() },
            setUp: { [weak self] in self?.setUp() }
        )
    }

    /// Asks first when the switch would leave a closed-lid Mac running with no screen. False means cancel.
    func confirmLidClosed(for display: Display, to choice: Config.Choice) -> Bool {
        let isLast = !screens.contains { $0.id != display.id && $0.isEnabled && !DisplayManager.isVirtual($0.id) }
        guard case .device = choice, Switcher.action(isLastRealDisplay: isLast, mode: switcher.config.noScreenMode)
            == .keepRunning, DisplayManager.isLidClosed() else { return true }
        let alert = NSAlert()
        alert.messageText = "The lid is closed"
        alert.informativeText = "No screen will show the Mac, and the Mac keeps running. Press ⌃⌥⌘B to come back."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError("Switchboard could not change Open at Login. Try again in System Settings > General > Login Items.")
        }
    }

    // ponytail: URL scheme only; App Intents and Focus filters when the app moves to an Xcode build
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let value = { (name: String) in query.first { $0.name == name }?.value ?? "" }
            switch url.host?.lowercased() {
            case "back": backToComputer()
            case "switch":
                // The cached list is empty or stale if the menu never opened, so read it fresh.
                switcher.displays { [weak self] list in
                    self?.screens = list
                    self?.switchScreen(named: value("screen"), to: value("to"))
                }
            default: showError("Switchboard does not know the link “\(url.absoluteString)”.")
            }
        }
    }

    private func switchScreen(named name: String, to target: String) {
        let config = switcher.config
        let same = { (a: String, b: String) in a.caseInsensitiveCompare(b) == .orderedSame }
        guard let display = screens.first(where: { same(config.screens[$0.key]?.name ?? $0.name, name) }) else {
            return showError("Switchboard does not know the screen “\(name)”.")
        }
        let screen = config.screens[display.key]
        let choice: Config.Choice
        switch target.lowercased() {
        case "mac": choice = .mac
        case "off": choice = .off
        default:
            guard let device = screen?.devices.first(where: { same($0.name, target) }) else {
                return showError("“\(screen?.name ?? display.name)” has no device “\(target)”.")
            }
            choice = .device(device.input)
        }
        pick(display, choice)
    }
}
