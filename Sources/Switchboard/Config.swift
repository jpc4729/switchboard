import Foundation
import os

/// Everything the user set up, saved as one JSON value in UserDefaults.
struct Config: Codable, Equatable {
    enum NoScreenMode: String, Codable { case sleep, keepRunning }
    /// What a screen shows. A device is named by its input value on that screen.
    enum Choice: Codable, Hashable { case mac, device(UInt8), off }
    struct Device: Codable, Equatable {
        var name: String
        var input: UInt8
    }
    struct Screen: Codable, Equatable {
        var name: String
        var computerInput: UInt8
        var devices: [Device] = []
    }

    private static let defaultsKey = "config"
    /// A saved config that did not decode, kept because the next save replaces it.
    private static let unreadableKey = "config.unreadable"

    /// Keyed by `Display.key`.
    var screens: [String: Screen] = [:]
    var noScreenMode: NoScreenMode = .sleep
    // Corrected from DDC.readInput on menu open for enabled, set-up screens; a screen the app
    // turned off keeps its tracked choice.
    // Saved so the menu and Back to Computer survive a crash. A missing key means Mac.
    var choices: [String: Choice] = [:]
    /// Links that turn a screen off or switch it to a device ask first.
    var askBeforeLinks = true
    /// Keys of the screens kept on while they show a device. Saved so a relaunch still holds the Mac
    /// awake and still does not bring them back on its own.
    var kept: Set<String> = []

    func choice(for key: String) -> Choice {
        choices[key] ?? .mac
    }

    static func load() -> Config {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            UserDefaults.standard.set(data, forKey: unreadableKey)
            Logger.app.error("Config did not decode, saved under \(unreadableKey, privacy: .public): \(error)")
            return Config()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

// Synthesized Decodable needs every key, even one with a default, so a field added later would
// lose the whole config. Here every field but `screens` keeps its default when it is missing or
// holds a value from another version.
extension Config {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        screens = try values.decodeIfPresent([String: Screen].self, forKey: .screens) ?? [:]
        if let mode = try? values.decodeIfPresent(NoScreenMode.self, forKey: .noScreenMode) { noScreenMode = mode }
        if let choices = try? values.decodeIfPresent([String: Choice].self, forKey: .choices) { self.choices = choices }
        if let ask = try? values.decodeIfPresent(Bool.self, forKey: .askBeforeLinks) { askBeforeLinks = ask }
        if let kept = try? values.decodeIfPresent(Set<String>.self, forKey: .kept) { self.kept = kept }
    }
}

extension Config.Screen {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        computerInput = try values.decode(UInt8.self, forKey: .computerInput)
        if let devices = try? values.decodeIfPresent([Config.Device].self, forKey: .devices) { self.devices = devices }
    }
}

extension Logger {
    static let app = Logger(subsystem: "io.github.jpc4729.switchboard", category: "app")
}
