import AppKit
import ServiceManagement

extension AppDelegate {
    @objc func pick(_ sender: NSMenuItem) {
        guard let (display, choice) = sender.representedObject as? (Display, Config.Choice) else { return }
        pick(display, choice)
    }

    /// The one switch path for the menu, the window and links. The lid check reads the screens on the
    /// queue, so it sees every switch picked before it.
    func pick(_ display: Display, _ choice: Config.Choice) {
        switcher.leavesClosedLidRunning(display, to: choice) { [weak self] closedLid in
            guard let self else { return }
            guard closedLid else { return switcher.switchScreen(display, to: choice, done: finish) }
            confirmLidClosed { [weak self] in
                guard let self else { return }
                switcher.switchScreen(display, to: choice, done: finish)
            }
        }
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

    /// Asks first when the switch would leave a closed-lid Mac running with no screen. Runs `then` on Continue.
    private func confirmLidClosed(then: @escaping @MainActor () -> Void) {
        // Carbon reports only an app that holds ⌃⌥⌘B exclusively, so the text also covers one it cannot see.
        let back = hotKey == nil
            ? "Another app uses ⌃⌥⌘B, so choose the Mac with the screen’s own button to come back."
            : "Press ⌃⌥⌘B to come back. If it does nothing, another app uses it: choose the Mac with the screen’s own button."
        runAlert({
            let alert = NSAlert()
            alert.messageText = "The lid is closed"
            alert.informativeText = "No screen will show the Mac, and the Mac keeps running. " + back
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            return alert
        }, then: { _, response in
            if response == .alertFirstButtonReturn { then() }
        })
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            // Registered, but turned off in Login Items: only the user can turn it on there.
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try SMAppService.mainApp.register()
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
            // The link's own text is not shown: any web page can open a link with words of its choice.
            default: showError("Switchboard does not know this link.")
            }
        }
    }

    @objc func toggleAskBeforeLinks() {
        switcher.config.askBeforeLinks.toggle()
    }

    /// Any app or web page can open a link, so a link that turns a screen off or switches it away asks first.
    /// Runs `then` on Allow. The names are the user's own, from Setup, never text from the link.
    private func confirmLink(_ action: String, then: @escaping @MainActor () -> Void) {
        guard switcher.config.askBeforeLinks else { return then() }
        runAlert({
            let alert = NSAlert()
            alert.messageText = "Allow this link?"
            alert.informativeText = "A link asks Switchboard to \(action). Links can come from any app or web page."
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Cancel")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Do not ask again"
            return alert
        }, then: { [weak self] alert, response in
            guard let self, response == .alertFirstButtonReturn else { return }
            if alert.suppressionButton?.state == .on { switcher.config.askBeforeLinks = false }
            then()
        })
    }

    private func switchScreen(named name: String, to target: String) {
        let config = switcher.config
        let same = { (a: String, b: String) in a.caseInsensitiveCompare(b) == .orderedSame }
        guard let display = screens.first(where: { same(config.screens[$0.key]?.name ?? $0.name, name) }) else {
            return showError("Switchboard has no screen with the name in the link.")
        }
        let screen = config.screens[display.key]
        let screenName = screen?.name ?? display.name
        let choice: Config.Choice
        let action: String
        switch target.lowercased() {
        case "mac": return pick(display, .mac)
        case "off": (choice, action) = (.off, "turn “\(screenName)” off")
        default:
            guard let device = screen?.devices.first(where: { same($0.name, target) }) else {
                return showError("“\(screenName)” has no device with the name in the link.")
            }
            (choice, action) = (.device(device.input), "switch “\(screenName)” to \(device.name)")
        }
        confirmLink(action) { [weak self] in self?.pick(display, choice) }
    }
}
