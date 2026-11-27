import Foundation
import XCTest
@testable import HelperCore

/// The pause gate (docs/worker.md, "The pause gate"): an outside file that pauses Slipstream
/// while it says `closed`, and only ever ends the pause it set itself.
final class PauseGateTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testParse() {
        XCTAssertEqual(PauseGate.parse("open\n\n1795812110\n"), .open)
        XCTAssertEqual(PauseGate.parse("closed\nactive on-battery\n1795812110\n"), .closed(reasons: ["active", "on-battery"]))
        XCTAssertEqual(PauseGate.parse("closed\n"), .closed(reasons: []))
        XCTAssertEqual(PauseGate.parse("closed"), .closed(reasons: []))
    }

    /// The guard: anything that is not a gate's word is no gate, so a broken file never stops the Mac.
    func testGarbageIsNoGate() {
        XCTAssertNil(PauseGate.parse(""))
        XCTAssertNil(PauseGate.parse("CLOSED\n"))
        XCTAssertNil(PauseGate.parse("maybe\nactive\n"))
        XCTAssertNil(PauseGate.read(URL(fileURLWithPath: "/nonexistent/gate/state")))
    }

    func testReadsAFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state")
        try "closed\naway\n1\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(PauseGate.read(file), .closed(reasons: ["away"]))
        // A file far too big for a gate is no gate.
        try String(repeating: "closed\n", count: 1000).write(to: file, atomically: true, encoding: .utf8)
        XCTAssertNil(PauseGate.read(file))
    }

    func testMenuLine() {
        XCTAssertEqual(PauseGate.open.menuLine, "Sperre: offen")
        XCTAssertEqual(PauseGate.closed(reasons: ["active", "on-battery", "lunch"]).menuLine,
                       "Sperre: geschlossen (in Benutzung, Akku, lunch)")
        XCTAssertEqual(PauseGate.closed(reasons: []).menuLine, "Sperre: geschlossen")
    }

    func testClosedGatePausesNow() {
        let closed = PauseGate.closed(reasons: ["active"])
        XCTAssertEqual(PauseGate.decide(gate: closed, gatePaused: false, pausedUntil: nil, mode: .now, now: now),
                       .pause(until: now.addingTimeInterval(PauseGate.hold)))
        // A pause of the gate's that ran out (the Mac slept through it) starts again.
        XCTAssertEqual(PauseGate.decide(gate: closed, gatePaused: true, pausedUntil: now.addingTimeInterval(-1), mode: .now, now: now),
                       .pause(until: now.addingTimeInterval(PauseGate.hold)))
    }

    func testGatePauseIsRenewedAnHourBeforeItEnds() {
        let closed = PauseGate.closed(reasons: ["active"])
        XCTAssertEqual(PauseGate.decide(gate: closed, gatePaused: true, pausedUntil: now.addingTimeInterval(PauseGate.hold - 60), mode: .now, now: now), .none)
        XCTAssertEqual(PauseGate.decide(gate: closed, gatePaused: true, pausedUntil: now.addingTimeInterval(PauseGate.hold - 3601), mode: .now, now: now),
                       .pause(until: now.addingTimeInterval(PauseGate.hold)))
    }

    /// The user's own pause stays the user's: the gate stops a running job that the pause let
    /// finish, keeps the user's end, and never ends that pause when it opens.
    func testUsersPauseStaysTheUsers() {
        let closed = PauseGate.closed(reasons: ["active"])
        let until = now.addingTimeInterval(1800)
        XCTAssertEqual(PauseGate.decide(gate: closed, gatePaused: false, pausedUntil: until, mode: .afterJob, now: now),
                       .stopRunningJob(until: until))
        XCTAssertEqual(PauseGate.decide(gate: closed, gatePaused: false, pausedUntil: until, mode: .now, now: now), .none)
        XCTAssertEqual(PauseGate.decide(gate: .open, gatePaused: false, pausedUntil: until, mode: .now, now: now), .none)
    }

    func testOpenGateEndsOnlyItsOwnPause() {
        let until = now.addingTimeInterval(3600)
        XCTAssertEqual(PauseGate.decide(gate: .open, gatePaused: true, pausedUntil: until, mode: .now, now: now), .resume)
        // No gate any more (file gone, setting off) ends the gate's pause too.
        XCTAssertEqual(PauseGate.decide(gate: nil, gatePaused: true, pausedUntil: until, mode: .now, now: now), .resume)
        XCTAssertEqual(PauseGate.decide(gate: .open, gatePaused: false, pausedUntil: nil, mode: .now, now: now), .none)
    }
}
