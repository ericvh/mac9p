import XCTest
@testable import Mac9PCore

final class NinePClientTests: XCTestCase {
    func testConfigParsesHostPortUserAndVers() throws {
        let cfg = try NinePClient.Config.from(mountString: "9p://alice@host.example:1234/?vers=9P2000.u")
        XCTAssertEqual(cfg.host, "host.example")
        XCTAssertEqual(cfg.port, 1234)
        XCTAssertEqual(cfg.user, "alice")
        XCTAssertEqual(cfg.requestedVersion, "9P2000.u")
    }

    func testConfigDefaultsPort564() throws {
        let cfg = try NinePClient.Config.from(mountString: "9p://host.example/")
        XCTAssertEqual(cfg.port, 564)
    }

    func testVersionCandidatesDefaultOrder() {
        XCTAssertEqual(NinePClient.versionCandidates(requested: nil),
                       ["9P2000.L", "9P2000.u", "9P2000"])
    }

    func testVersionCandidatesRequestedFirstAndDeduped() {
        XCTAssertEqual(NinePClient.versionCandidates(requested: "9P2000"),
                       ["9P2000", "9P2000.L", "9P2000.u"])
    }
}

