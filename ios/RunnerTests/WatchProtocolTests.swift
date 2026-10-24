import XCTest
@testable import Runner

final class WatchProtocolTests: XCTestCase {
    private func fixture() throws -> WatchJSON {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "watch_sync_v2", withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? WatchJSON)
    }
    func testSharedFixturePreservesMetadataAndFractionalRPE() throws {
        let envelope = try fixture()
        let roundtrip = WatchProtocol.decode(WatchProtocol.encode(envelope))
        XCTAssertEqual(WatchProtocol.int(roundtrip["schemaVersion"]), 2)
        let exercises = try XCTUnwrap(WatchProtocol.payload(roundtrip)["exercises"] as? [WatchJSON])
        let set = try XCTUnwrap((exercises.first?["sets"] as? [WatchJSON])?.first)
        XCTAssertEqual(WatchProtocol.number(set["rpe"]), 8.5)
        let meta = WatchProtocol.decode(set["setTypeMetaJson"])
        XCTAssertEqual(meta["miniSets"] as? [Int], [3, 2])
        XCTAssertEqual(meta["unknownFutureField"] as? Bool, true)
    }
    func testCrossedSnapshotsMergeEachFieldIndependently() throws {
        let remote: WatchJSON = ["weight": 80, "reps": 10, "completed": true,
            "syncVersions": ["weight": ["revision": 10, "origin": "phone"],
                             "reps": ["revision": 30, "origin": "watch"],
                             "completion": ["revision": 30, "origin": "watch"]]]
        let local: WatchJSON = ["weight": 85, "reps": 8, "completed": false,
            "syncVersions": ["weight": ["revision": 20, "origin": "phone"],
                             "reps": ["revision": 10, "origin": "watch"],
                             "completion": ["revision": 10, "origin": "watch"]]]
        let merged = WatchProtocol.mergeSet(remote, local: local, fallback: [:])
        XCTAssertEqual(WatchProtocol.int(merged["weight"]), 85)
        XCTAssertEqual(WatchProtocol.int(merged["reps"]), 10)
        XCTAssertEqual(merged["completed"] as? Bool, true)
    }
    func testRevisionTiesUseTheSameOriginOrderingAsDart() {
        XCTAssertTrue(WatchProtocol.newer(["revision": 7, "origin": "watch"], than: ["revision": 7, "origin": "phone"]))
        XCTAssertFalse(WatchProtocol.newer(["revision": 7, "origin": "phone"], than: ["revision": 7, "origin": "watch"]))
    }
}
