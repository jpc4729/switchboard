import CoreGraphics
import Foundation
import IOKit.pwr_mgt

/// Runs every display and DDC call on one serial background queue and calls back on the main queue
/// with a plain-words error, or nil. Call it from the main thread only.
final class Switcher {
    enum Action: Equatable { case disable, keepAndSleep, keepRunning }

    /// Saved on every change.
    var config = Config.load() {
        didSet {
            config.save()
            holdAwake()
        }
    }

    private let queue = DispatchQueue(label: "io.github.jpc4729.switchboard.switcher")
    // Created on the queue: DisplayManager is not thread safe.
    private lazy var manager = DisplayManager()
    // The last screen, kept on while it shows a device: the user chose to leave the Mac with no screen.
    // ponytail: in memory only, and a kept screen that comes back by its own button still shows the device
    // until Back to Computer; persist it in Config and track reappearing screens if that confuses users.
    // Changed on main, in the done callbacks. Keep Running holds the Mac awake while any screen is kept on.
    private var keptOn: Set<String> = [] {
        didSet { holdAwake() }
    }
    private var awake: IOPMAssertionID?

    /// The last real active display is never disabled; it stays on, and the Mac sleeps if asked to.
    static func action(isLastRealDisplay: Bool, mode: Config.NoScreenMode) -> Action {
        guard isLastRealDisplay else { return .disable }
        return mode == .sleep ? .keepAndSleep : .keepRunning
    }

    static func didNotSwitch(_ name: String) -> String {
        "“\(name)” did not switch. Turn on DDC/CI in the screen’s own menu. Connect the monitor with HDMI if you can, "
            + "and turn off its picture features such as Input Signal Plus or Dynamic Brightness."
    }

    static func didNotSwitchBack(_ name: String) -> String {
        "“\(name)” did not switch back. Choose the Mac with the screen’s own button."
    }

    /// Runs blocking work on the queue, in order with every other call, and returns the result on main.
    /// NSScreen is main-thread only, so the screen names are read here and handed to the queue.
    func run<T>(_ work: @escaping () -> T, done: @escaping (T) -> Void) {
        let names = DisplayManager.screenNames()
        queue.async {
            self.manager.remember(names)
            let result = work()
            DispatchQueue.main.async { done(result) }
        }
    }

    func displays(_ done: @escaping ([Display]) -> Void) {
        run({ self.manager.displays() }, done: done)
    }

    func switchScreen(_ screen: Display, to choice: Config.Choice, done: @escaping (String?) -> Void) {
        let (id, key) = (screen.id, screen.key)
        if choice == .mac { return bringBack(only: id, done: done) }
        let mode = config.noScreenMode
        let name = config.screens[key]?.name ?? screen.name
        // shown: the screen shows the choice, so it is saved even when a later step fails.
        // kept: the screen is still on in macOS, so a screen change must not reset it to Mac.
        run({ () -> (error: String?, shown: Bool, kept: Bool) in
            let all = self.manager.displays()
            let display = all.first { $0.id == id }
            let isLast = !all.contains { $0.id != id && $0.isEnabled && !DisplayManager.isVirtual($0.id) }

            if case .device(let input) = choice, !DDC.writeInput(input, to: id) {
                return (Self.didNotSwitch(name), false, false)
            }
            if choice == .off, isLast { return ("“\(name)” is the last screen, so it stays on.", false, false) }
            switch Self.action(isLastRealDisplay: isLast, mode: mode) {
            case .disable:
                // Gone from the list or already off: the monitor dropped hot-plug, nothing left to do.
                guard display?.isEnabled == true, !self.manager.setEnabled(false, for: id) else { return (nil, true, false) }
                return choice == .off
                    ? ("“\(name)” did not turn off. Try again.", false, false)
                    : ("“\(name)” switched, but the Mac could not stop using it. Choose it again.", true, true)
            case .keepAndSleep: return (Self.sleepNow(), true, true)
            case .keepRunning: return (nil, true, true)
            }
        }) { result in
            if result.shown {
                self.config.choices[key] = choice
                if result.kept { self.keptOn.insert(key) } else { self.keptOn.remove(key) }
            }
            done(result.error)
        }
    }

    /// The user chose the Mac with these screens' own buttons, so they are no longer kept on.
    func backOnMac(_ keys: [String]) {
        keptOn.subtract(keys)
    }

    /// Turns every screen the app turned off back on, then switches each set-up screen to the Mac.
    /// Safe to run again, and before or after the user presses the screen's own button.
    func backToComputer(done: @escaping (String?) -> Void) {
        bringBack(only: nil, done: done)
    }

    /// Call on every screen change: screens active again show the Mac, and if no real screen is
    /// left on and the user did not choose that, every screen comes back to the Mac.
    func screensChanged(done: @escaping (String?) -> Void) {
        run({ (self.manager.lostAllDisplays, self.manager.displays().filter(\.isEnabled).map(\.key)) }) { lost, active in
            if lost, self.keptOn.isEmpty { return self.backToComputer(done: done) }
            for key in active where !self.keptOn.contains(key) {
                self.config.choices[key] = nil
            }
            done(nil)
        }
    }

    private func bringBack(only: CGDirectDisplayID?, done: @escaping (String?) -> Void) {
        let screens = config.screens
        run({ () -> (errors: [String], keys: [String]) in
            var errors: [String] = []
            var keys: [String] = []
            // The list includes every display the app turned off, so this also turns them all back on.
            for display in self.manager.displays() where only == nil || display.id == only {
                let name = screens[display.key]?.name ?? display.name
                let on = display.isEnabled || self.manager.setEnabled(true, for: display.id)
                if !on { errors.append("“\(name)” did not turn back on. Unplug it and plug it back in.") }
                var switched = true
                if let screen = screens[display.key] {
                    switched = DDC.writeInput(screen.computerInput, to: display.id)
                    // ponytail: one 2 s retry for a display that just turned back on; tune it on real monitors.
                    if !switched, !display.isEnabled {
                        sleep(2)
                        switched = DDC.writeInput(screen.computerInput, to: display.id)
                    }
                    if !switched { errors.append(Self.didNotSwitchBack(name)) }
                }
                // Only a screen that is back on the Mac shows Mac; a failed one keeps its choice.
                if on, switched { keys.append(display.key) }
            }
            return (errors, keys)
        }) { result in
            for key in result.keys {
                self.config.choices[key] = nil
                self.keptOn.remove(key)
            }
            done(result.errors.isEmpty ? nil : result.errors.joined(separator: "\n"))
        }
    }

    /// Follows both keptOn and the mode, so a mode change while a screen is kept on applies at once.
    private func holdAwake() {
        let on = !keptOn.isEmpty && config.noScreenMode == .keepRunning
        if on, awake == nil {
            var id = IOPMAssertionID(0)
            let type = kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
            let reason = "Switchboard keeps the Mac running with no screen" as CFString
            if IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id) == kIOReturnSuccess {
                awake = id
            }
        } else if !on, let id = awake {
            IOPMAssertionRelease(id)
            awake = nil
        }
    }

    private static func sleepNow() -> String? {
        // ponytail: pmset, no public sleep-now API; IOPMSleepSystem if pmset goes away
        do {
            try Process.run(URL(fileURLWithPath: "/usr/bin/pmset"), arguments: ["sleepnow"])
            return nil
        } catch {
            return "The screen switched, but the Mac could not go to sleep."
        }
    }
}
