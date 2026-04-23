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

    func testReadOnlyMVPAgainstMockServer() async throws {
        let server = try Mock9PServer()
        defer { server.stop() }

        let cfg = NinePClient.Config(host: "127.0.0.1", port: Int(server.port), user: "u", aname: nil, requestedVersion: "9P2000")
        let c = NinePClient(config: cfg)
        try c.connectAndNegotiate()
        XCTAssertEqual(c.negotiatedVersion, .v2000)

        try c.attach()

        // walk to hello.txt, open, read
        let root = UInt32(1) // first allocated by client
        let fidHello = UInt32(2)
        _ = try c.walk(from: root, newfid: fidHello, names: ["hello.txt"])
        _ = try c.open(fid: fidHello, mode: 0)
        let d = try c.read(fid: fidHello, offset: 0, count: 1024)
        XCTAssertEqual(String(data: d, encoding: .utf8), "hello\n")

        // directory listing on root
        _ = try c.open(fid: root, mode: 0)
        let entries = try c.readDir(fid: root)
        XCTAssertTrue(entries.contains(where: { $0.name == "hello.txt" }))

        try c.clunk(fid: fidHello)
        try c.clunk(fid: root)
        c.disconnect()
    }
}

