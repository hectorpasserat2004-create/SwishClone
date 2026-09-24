import XCTest
@testable import SwishGestures

/// Le thread du tap, sans tap : ce qui doit être vrai pour que le callback ne
/// touche jamais le thread principal.
final class EventLoopThreadTests: XCTestCase {

    /// Boîte partagée avec le thread : une classe, pas une variable capturée.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int] = []
        private var mainFlags: [Bool] = []

        func record(_ value: Int) {
            lock.lock(); defer { lock.unlock() }
            values.append(value)
            mainFlags.append(Thread.isMainThread)
        }
        var recorded: [Int] { lock.lock(); defer { lock.unlock() }; return values }
        var anyOnMain: Bool { lock.lock(); defer { lock.unlock() }; return mainFlags.contains(true) }
    }

    func testSetUpAndTearDownRunOnTheLoopThreadNotTheMainThread() {
        let loop = EventLoopThread(name: "test.loop")
        let recorder = Recorder()

        XCTAssertTrue(loop.start {
            recorder.record(1)
            return true
        })
        loop.stop {
            recorder.record(2)
        }

        XCTAssertEqual(recorder.recorded, [1, 2])
        XCTAssertFalse(recorder.anyOnMain)
    }

    func testBlocksRunInOrderOnTheLoopThread() {
        let loop = EventLoopThread(name: "test.loop")
        let recorder = Recorder()
        XCTAssertTrue(loop.start { true })

        for i in 0 ..< 200 { loop.async { recorder.record(i) } }
        loop.stop() // le tearDown passe après tout ce qui était déjà en file

        XCTAssertEqual(recorder.recorded, Array(0 ..< 200))
        XCTAssertFalse(recorder.anyOnMain)
    }

    func testATimerAddedOnTheLoopFiresOnTheLoopThread() {
        let loop = EventLoopThread(name: "test.loop")
        let recorder = Recorder()
        let fired = expectation(description: "timer")
        XCTAssertTrue(loop.start { true })

        loop.async {
            let timer = Timer(timeInterval: 0.05, repeats: false) { _ in
                recorder.record(7)
                fired.fulfill()
            }
            RunLoop.current.add(timer, forMode: .common)
        }
        wait(for: [fired], timeout: 2)
        loop.stop()

        XCTAssertEqual(recorder.recorded, [7])
        XCTAssertFalse(recorder.anyOnMain)
    }

    func testIsCurrentIsTrueOnlyOnTheLoopThread() {
        let loop = EventLoopThread(name: "test.loop")
        let recorder = Recorder()
        XCTAssertTrue(loop.start { true })
        XCTAssertFalse(loop.isCurrent)

        loop.async { recorder.record(loop.isCurrent ? 1 : 0) }
        loop.stop()
        XCTAssertEqual(recorder.recorded, [1])
    }

    func testStopJoinsIsIdempotentAndLaterBlocksAreIgnored() {
        let loop = EventLoopThread(name: "test.loop")
        let recorder = Recorder()
        XCTAssertTrue(loop.start { true })

        loop.stop()
        loop.stop()
        loop.async { recorder.record(1) }

        XCTAssertEqual(recorder.recorded, [])
    }

    func testAFailedSetUpReportsFalseAndCanBeRetried() {
        let loop = EventLoopThread(name: "test.loop")
        XCTAssertFalse(loop.start { false })
        loop.stop() // sans effet

        XCTAssertTrue(loop.start { true })
        loop.stop()
    }
}
