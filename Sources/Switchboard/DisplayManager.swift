import AppKit
import CoreGraphics
import IOKit

// Private CoreGraphics call that logically connects or disconnects a display.
// It is not public API, so Switchboard cannot ship on the Mac App Store.
@_silgen_name("CGSConfigureDisplayEnabled")
private func CGSConfigureDisplayEnabled(_ config: CGDisplayConfigRef, _ display: CGDirectDisplayID, _ enabled: Bool) -> CGError

struct Display {
    let id: CGDirectDisplayID
    /// Config key: the display UUID, stable across reboots and ports, unlike the ID.
    let key: String
    let name: String
    let isBuiltin: Bool
    let isEnabled: Bool
}

/// Not thread safe: callers run every call on one serial queue.
final class DisplayManager {
    private static let disabledKey = "disabledDisplayIDs"

    // A disabled display can drop out of the system lists, so remember every
    // display we have seen, with its name, to offer it again in the menu.
    private var known: [CGDirectDisplayID: String] = [:]
    // ID to UUID, saved: the UUID lookup can fail once the display is off, also after a crash.
    private var keys = UserDefaults.standard.dictionary(forKey: "displayKeys") as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(keys, forKey: "displayKeys") }
    }
    // Saved so a crash or force-quit still lets the next launch turn them back on.
    private var disabledByUs: Set<CGDirectDisplayID> {
        didSet { UserDefaults.standard.set(disabledByUs.map { Int($0) }, forKey: Self.disabledKey) }
    }
    // Displays whose enable failed once in this run.
    private var failedOnce: Set<CGDirectDisplayID> = []

    init() {
        let saved = UserDefaults.standard.array(forKey: Self.disabledKey) as? [Int] ?? []
        let active = Set(Self.list(CGGetActiveDisplayList))
        disabledByUs = Set(saved.map { CGDirectDisplayID($0) }).subtracting(active)
    }

    /// NSScreen is main-thread only: read the names there, then pass them to `remember`.
    @MainActor static func screenNames() -> [CGDirectDisplayID: String] {
        Dictionary(NSScreen.screens.compactMap { s in s.displayID.map { ($0, s.localizedName) } }) { $1 }
    }

    func remember(_ names: [CGDirectDisplayID: String]) {
        known.merge(names) { $1 }
    }

    func displays() -> [Display] {
        let active = Set(Self.list(CGGetActiveDisplayList))
        let online = Self.list(CGGetOnlineDisplayList)

        var ids = online
        for id in disabledByUs where !ids.contains(id) {
            ids.append(id)
        }

        return ids.map { id in
            if let uuid = Self.uuid(for: id), keys[String(id)] != uuid { keys[String(id)] = uuid }
            return Display(
                id: id,
                key: keys[String(id)] ?? String(id),
                name: known[id] ?? "Display \(id)",
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isEnabled: active.contains(id)
            )
        }
        .sorted { ($0.isBuiltin ? 0 : 1, $0.id) < ($1.isBuiltin ? 0 : 1, $1.id) }
    }

    /// True when the display reached the wanted state. The caller keeps the last real display on.
    func setEnabled(_ enabled: Bool, for id: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        if CGBeginDisplayConfiguration(&config) == .success, let config {
            if CGSConfigureDisplayEnabled(config, id, enabled) == .success {
                // .forSession: a logout or restart turns every display back on.
                _ = CGCompleteDisplayConfiguration(config, .forSession)
            } else {
                CGCancelDisplayConfiguration(config)
            }
        }
        // Every call can report an error (the commit even returns 1001) when the change worked,
        // so only the real state counts.
        let ok = (CGDisplayIsActive(id) != 0) == enabled
        if ok {
            if enabled { disabledByUs.remove(id) } else { disabledByUs.insert(id) }
            failedOnce.remove(id)
        } else if enabled, !failedOnce.insert(id).inserted {
            // ponytail: an enable that fails twice in one run most likely means the display was unplugged,
            // so it is forgotten instead of reported forever; replugging or a restart brings it back.
            // One failure keeps it saved, so the next try, also after a relaunch, can still bring it back.
            disabledByUs.remove(id)
        }
        return ok
    }

    /// No real display is on, but some that the app turned off can come back.
    var lostAllDisplays: Bool {
        !disabledByUs.isEmpty && !Self.list(CGGetActiveDisplayList).contains { !Self.isVirtual($0) }
    }

    // ponytail: undocumented AppleClamshellState key, no public lid API; drop the warning if it goes away
    /// A Mac with no lid (a desktop) reads as open.
    static func isLidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let state = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return state?.takeRetainedValue() as? Bool ?? false
    }

    private static func uuid(for id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    // ponytail: macOS adds a 1920x1080 stand-in with no real vendor when no display
    // is connected; a real unknown-vendor 1080p panel would also match. Upgrade path:
    // check the IORegistry for a backing framebuffer if this ever misfires.
    static func isVirtual(_ id: CGDirectDisplayID) -> Bool {
        let vendor = CGDisplayVendorNumber(id)
        let noVendor = vendor == 0 || vendor == 0x756E_6B6E // 'unkn', kDisplayVendorIDUnknown
        return noVendor && CGDisplayIsBuiltin(id) == 0
            && CGDisplayPixelsWide(id) == 1920 && CGDisplayPixelsHigh(id) == 1080
    }

    private static func list(
        _ fetch: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
    ) -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard fetch(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard fetch(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
