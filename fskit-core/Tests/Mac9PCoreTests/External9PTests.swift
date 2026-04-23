import XCTest
@testable import Mac9PCore

final class External9PTests: XCTestCase {
    func testAgainstExternalServerIfProvided() async throws {
        // Provide a URL like: 9p://127.0.0.1:5640/?vers=9P2000
        // (Note: this is a mount-style string; we parse it ourselves.)
        guard let s = ProcessInfo.processInfo.environment["MAC9P_E2E_URL"], !s.isEmpty else {
            throw XCTSkip("MAC9P_E2E_URL not set")
        }

        let cfg = try NinePClient.Config.from(mountString: s)
        let c = NinePAsyncClient(config: cfg)
        try await c.connectAndNegotiate()
        try await c.attach()

        let root = try await c.root()
        _ = try await c.open(fid: root, mode: 0)

        // Basic: enumerate root
        let entries = try await c.readDir(fid: root)
        XCTAssertFalse(entries.isEmpty)

        // Optional: read a known file if provided.
        if let path = ProcessInfo.processInfo.environment["MAC9P_E2E_READ_FILE"], !path.isEmpty {
            let fid = await c.allocateFid()
            _ = try await c.walk(from: root, newfid: fid, names: path.split(separator: "/").map(String.init))
            _ = try await c.open(fid: fid, mode: 0)
            let d = try await c.read(fid: fid, offset: 0, count: 4096)
            XCTAssertGreaterThan(d.count, 0)
            try await c.clunk(fid: fid)
            await c.releaseFid(fid)
        }

        try await c.clunk(fid: root)
        await c.disconnect()
    }
}

