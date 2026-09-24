import XCTest
@testable import SwishGestures

final class HostLockTests: XCTestCase {

    private var path = ""

    override func setUp() {
        path = (NSTemporaryDirectory() as NSString).appendingPathComponent("hostlock-test-\(UUID().uuidString).lock")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: path)
    }

    func testASecondHostIsRefusedAndTheHolderIsNamed() throws {
        let first = HostLock(path: path)
        let second = HostLock(path: path)
        try first.acquire()

        XCTAssertThrowsError(try second.acquire()) { error in
            guard case let HostLock.Failure.heldElsewhere(holder) = error else {
                return XCTFail("mauvaise erreur : \(error)")
            }
            XCTAssertEqual(holder.processID, getpid())
            XCTAssertEqual(holder.name, ProcessInfo.processInfo.processName)
        }
        XCTAssertFalse(second.isHeld)
    }

    func testReleasingLetsAnotherHostIn() throws {
        let first = HostLock(path: path)
        let second = HostLock(path: path)
        try first.acquire()
        first.release()

        XCTAssertNoThrow(try second.acquire())
        XCTAssertTrue(second.isHeld)
    }

    func testAcquiringTwiceIsHarmlessAndStillExcludesOthers() throws {
        let first = HostLock(path: path)
        try first.acquire()
        try first.acquire()
        XCTAssertThrowsError(try HostLock(path: path).acquire())
    }

    func testTheLockIsReleasedWhenItsOwnerGoesAway() throws {
        var first: HostLock? = HostLock(path: path)
        try first?.acquire()
        first = nil // le processus qui meurt libère de même
        XCTAssertNoThrow(try HostLock(path: path).acquire())
    }

    func testAnUnusableLockFileFailsOpen() throws {
        let lock = HostLock(path: "/nonexistent-directory-\(UUID().uuidString)/host.lock")
        XCTAssertNoThrow(try lock.acquire())
        XCTAssertFalse(lock.isHeld, "pas de verrou pris, mais la garde ne bloque pas l'usage normal")
    }
}
