@testable import Switchboard
import XCTest

final class ConfigTests: XCTestCase {
    private func decode(_ json: String) throws -> Config {
        try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    }

    /// The JSON that version 0.1.0 saves.
    func testReadsVersion010Config() throws {
        let config = try decode(#"""
            {"screens":{"A":{"name":"Odyssey","computerInput":15,"devices":[{"name":"PS5","input":17}]}},
             "noScreenMode":"keepRunning","choices":{"A":{"device":{"_0":17}}}}
            """#)
        XCTAssertEqual(config.screens["A"]?.name, "Odyssey")
        XCTAssertEqual(config.screens["A"]?.computerInput, 15)
        XCTAssertEqual(config.screens["A"]?.devices.first?.name, "PS5")
        XCTAssertEqual(config.screens["A"]?.devices.first?.input, 17)
        XCTAssertEqual(config.noScreenMode, .keepRunning)
        XCTAssertEqual(config.choices["A"], .device(17))
        XCTAssertTrue(config.askBeforeLinks)
    }

    /// A field that is missing or a value from another version keeps the screens.
    func testUnknownOrMissingValuesKeepTheScreens() throws {
        let config = try decode(#"""
            {"screens":{"A":{"name":"Odyssey","computerInput":15}},
             "noScreenMode":"hibernate","choices":{"A":{"pictureInPicture":{}}}}
            """#)
        XCTAssertEqual(config.screens["A"]?.name, "Odyssey")
        XCTAssertEqual(config.screens["A"]?.devices.count, 0)
        XCTAssertEqual(config.noScreenMode, .sleep)
        XCTAssertEqual(config.choices.count, 0)
        XCTAssertEqual(config.kept, [])
    }

    /// Kept screens survive a save and a load, so a relaunch still holds the Mac awake.
    func testKeepsKeptScreens() throws {
        var config = Config()
        config.kept = ["A"]
        let saved = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        XCTAssertEqual(try decode(saved).kept, ["A"])
    }
}
