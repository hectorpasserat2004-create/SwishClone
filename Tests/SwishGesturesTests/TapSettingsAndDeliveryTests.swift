import XCTest
import SwishCloneCore
@testable import SwishGestures

final class TapSettingsStoreTests: XCTestCase {

    func testAReadReturnsWhatWasWritten() {
        let store = TapSettingsStore()
        var settings = TapSettings()
        settings.zoneHeight = 77
        settings.machine.swipeThreshold = 12
        store.write(settings)
        XCTAssertEqual(store.read(), settings)
    }

    /// Deux valeurs écrites ensemble se lisent ensemble : une lecture ne voit
    /// jamais la moitié d'une écriture.
    func testConcurrentReadsNeverSeeATornValue() {
        let store = TapSettingsStore()
        func settings(_ n: Double) -> TapSettings {
            var s = TapSettings()
            s.zoneHeight = n
            s.machine.swipeThreshold = n
            return s
        }
        store.write(settings(1))

        let stop = ManagedFlag()
        let writer = Thread {
            var n = 1.0
            while stop.isSet == false {
                n = n == 1 ? 2 : 1
                store.write(settings(n))
                // Un verrou `os_unfair_lock` n'est pas équitable : un écrivain
                // qui le reprend sans pause affamerait les lecteurs.
                usleep(20)
            }
        }
        writer.start()

        let torn = ManagedCounter()
        DispatchQueue.concurrentPerform(iterations: 20_000) { _ in
            let read = store.read()
            if read.zoneHeight != read.machine.swipeThreshold { torn.increment() }
        }
        stop.set()

        XCTAssertEqual(torn.value, 0)
    }

    @MainActor
    func testGestureSettingsMapToTapSettings() {
        let settings = GestureSettings.shared
        let tap = settings.tapSettings
        XCTAssertEqual(tap.machine, settings.machineConfiguration)
        XCTAssertEqual(tap.zoneHeight, settings.gestureZoneHeight)
        XCTAssertEqual(tap.previewEnabled, settings.previewEnabled)
        XCTAssertEqual(tap.hapticsEnabled, settings.hapticsEnabled)
    }
}

private final class ManagedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

private final class ManagedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}

final class MainDeliveryTests: XCTestCase {

    private final class Recorder: @unchecked Sendable {
        var received: [Int] = []
        var allOnMain = true
    }

    func testDeliveriesSentFromAnotherThreadArriveInOrderOnTheMainThread() {
        let original = MainDelivery.handler
        defer { MainDelivery.handler = original }

        let total = 1000
        let recorder = Recorder()
        let done = expectation(description: "toutes les livraisons")
        MainDelivery.handler = { delivery in
            recorder.allOnMain = recorder.allOnMain && Thread.isMainThread
            recorder.received.append(Int(delivery.origin.x))
            if recorder.received.count == total { done.fulfill() }
        }

        DispatchQueue.global().async {
            for i in 0 ..< total {
                MainDelivery.send(.init(effects: [.hidePreview], target: nil, origin: CGPoint(x: i, y: 0)))
            }
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(recorder.received, Array(0 ..< total), "FIFO : l'ordre des effets est celui des événements")
        XCTAssertTrue(recorder.allOnMain)
    }
}
