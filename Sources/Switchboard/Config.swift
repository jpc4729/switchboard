import Foundation

/// Everything the user set up, saved as one JSON value in UserDefaults.
struct Config: Codable {
    enum NoScreenMode: String, Codable { case sleep, keepRunning }
    /// What a screen shows. A device is named by its input value on that screen.
    enum Choice: Codable, Equatable { case mac, device(UInt8), off }
    struct Device: Codable {
        var name: String
        var input: UInt8
    }
    struct Screen: Codable {
        var name: String
        var computerInput: UInt8
        var devices: [Device] = []
    }

    private static let defaultsKey = "config"

    /// Keyed by `Display.key`.
    var screens: [String: Screen] = [:]
    var noScreenMode: NoScreenMode = .sleep
    // ponytail: tracked choice only, no DDC read-back of the current input, so the screen's own
    // button can make it stale; read DDC.readInput on menu open if that confuses users.
    // Saved so the menu and Back to Computer survive a crash. A missing key means Mac.
    var choices: [String: Choice] = [:]

    func choice(for key: String) -> Choice {
        choices[key] ?? .mac
    }

    static func load() -> Config {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
