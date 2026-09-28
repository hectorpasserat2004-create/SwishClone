import ApplicationServices
import XCTest
import SwishCloneCore
@testable import SwishGestures

/// Le cœur du tap, rejoué sans thread ni tap : horloge, test de cible et
/// sortie sont des doubles.
private final class Harness {
    typealias Engine = GestureTapEngine

    /// Part de 0, comme le `Driver` de la machine. Ce n'est plus une
    /// nécessité : la machine compare `now` à ses échéances telles qu'elle
    /// les calcule, l'arrondi ne peut plus les faire diverger (voir
    /// `testATickExactlyAtTheDeadlineIsEnoughFarFromZero`).
    var time: TimeInterval = 0
    var deliveries: [Engine.Delivery] = []
    var logs: [String] = []
    var hitTests: [(location: CGPoint, zoneHeight: Double)] = []
    /// Ce que coûte un test de cible, en secondes d'horloge simulée.
    var hitTestCost: TimeInterval = 0
    var target: GestureTarget.Target? = .window(
        AXUIElementCreateSystemWide(),
        frame: CGRect(x: 0, y: 0, width: 800, height: 600)
    )

    let store: TapSettingsStore
    private(set) var engine: Engine!

    init(configure: (inout TapSettings) -> Void = { _ in }) {
        var settings = TapSettings()
        configure(&settings)
        store = TapSettingsStore(settings)
        engine = Engine(
            settings: store,
            now: { [unowned self] in time },
            hitTest: { [unowned self] location, height in
                hitTests.append((location, height))
                time += hitTestCost
                return target
            },
            deliver: { [unowned self] in deliveries.append($0) },
            log: { [unowned self] in logs.append($0) }
        )
    }

    var effects: [GestureStateMachine.Effect] { deliveries.flatMap(\.effects) }
    let cursor = CGPoint(x: 10, y: 20)

    @discardableResult
    func scroll(_ phase: GestureStateMachine.Phase, dx: Double = 0, dy: Double = 0) -> GestureStateMachine.Disposition {
        time += 0.01
        return engine.process(.scroll(phase: phase, momentum: nil, dx: dx, dy: dy), at: cursor)
    }

    /// Joue le rôle de l'hôte : réveille l'engine à chacune de ses échéances.
    func wait(_ duration: TimeInterval) {
        let end = time + duration
        var wakeUps = 0
        while let deadline = engine.nextDeadline, deadline <= end {
            time = max(time, deadline)
            engine.tick()
            wakeUps += 1
            precondition(wakeUps < 100, "l'engine ne fait plus avancer son échéance")
        }
        time = end
    }

    /// Un pincement entier, avec phase.
    func pinchIn() {
        for (magnitude, phase) in [(-0.01, GestureStateMachine.Phase.began), (-0.12, .changed), (-0.12, .ended)] {
            time += 0.01
            engine.process(.magnify(cumulative: magnitude, phase: phase), at: cursor)
        }
    }

    /// ↑, pause (étape validée), →, lever : un quart en haut à droite.
    func topRightQuarter() {
        scroll(.began)
        scroll(.changed, dy: -40)
        wait(0.35)
        scroll(.changed, dx: 40)
        scroll(.ended)
    }
}

final class GestureTapEngineTests: XCTestCase {

    func testLiftCommitsTheActionAndCarriesTheTarget() {
        let h = Harness()
        h.scroll(.began)
        h.scroll(.changed, dx: -40)
        h.scroll(.ended)

        XCTAssertTrue(h.effects.contains(.commit(.leftHalf)))
        let commit = h.deliveries.last { $0.effects.contains(.commit(.leftHalf)) }
        guard case .window? = commit?.target else { return XCTFail("la cible du geste doit accompagner l'action") }
    }

    func testTheTargetIsTestedOncePerGestureWithTheConfiguredZoneHeight() {
        let h = Harness { $0.zoneHeight = 55 }
        h.scroll(.began)
        for _ in 0 ..< 3 { h.scroll(.changed, dx: -20) }
        h.scroll(.ended)

        XCTAssertEqual(h.hitTests.count, 1)
        XCTAssertEqual(h.hitTests.first?.zoneHeight, 55)
        XCTAssertEqual(h.hitTests.first?.location, h.cursor)
    }

    func testSettingsChangedBetweenEventsApplyToTheNextGesture() {
        let h = Harness { $0.machine.swipeEnabled = false }
        XCTAssertEqual(h.scroll(.began), .pass)
        XCTAssertTrue(h.hitTests.isEmpty, "swipe éteint : la cible n'est même pas testée")
        XCTAssertTrue(h.effects.isEmpty)

        var settings = h.store.read()
        settings.machine.swipeEnabled = true
        h.store.write(settings)

        h.scroll(.began)
        XCTAssertEqual(h.hitTests.count, 1, "le réglage change sans relancer : le geste suivant le voit")
    }

    func testDispositionIsTheMachinesDecision() {
        let blocking = Harness { $0.machine.blocksEvents = true }
        XCTAssertEqual(blocking.scroll(.began), .swallow)

        let listening = Harness()
        XCTAssertEqual(listening.scroll(.began), .pass)
    }

    func testPreviewAndHapticFollowTheirSettingsButTheActionDoesNot() {
        let on = Harness()
        on.topRightQuarter()
        XCTAssertTrue(on.effects.contains(.haptic(.step)))
        XCTAssertTrue(on.effects.contains { if case .showPreview = $0 { true } else { false } })
        XCTAssertTrue(on.effects.contains(.commit(.topRightQuarter)))

        let off = Harness {
            $0.previewEnabled = false
            $0.hapticsEnabled = false
        }
        off.topRightQuarter()
        XCTAssertFalse(off.effects.contains { if case .haptic = $0 { true } else { false } })
        XCTAssertFalse(off.effects.contains { if case .showPreview = $0 { true } else { false } })
        XCTAssertTrue(off.effects.contains(.commit(.topRightQuarter)), "éteindre l'aperçu n'éteint pas l'action")
    }

    func testASlowTargetTestIsReportedAndAFastOneIsNot() {
        let slow = Harness()
        slow.hitTestCost = 0.02
        slow.scroll(.began)
        XCTAssertEqual(slow.logs.count, 1)
        XCTAssertTrue(slow.logs.first?.contains("lent") == true)

        let fast = Harness()
        fast.scroll(.began)
        XCTAssertTrue(fast.logs.isEmpty)
    }

    func testResetHidesThePreviewAndForgetsTheGesture() {
        let h = Harness()
        h.scroll(.began)
        h.scroll(.changed, dx: -40)
        h.engine.reset()
        XCTAssertEqual(h.effects.last, .hidePreview)

        h.scroll(.ended)
        XCTAssertFalse(h.effects.contains { if case .commit = $0 { true } else { false } },
                       "un geste dont des événements ont été perdus n'agit jamais")
    }

    func testStillnessCancelsThroughTheHostsTicks() {
        let h = Harness()
        h.scroll(.began)
        h.scroll(.changed, dx: -40)
        h.wait(1.0)

        XCTAssertTrue(h.effects.contains(.cancelled(.stillness)))
        XCTAssertTrue(h.effects.contains(.haptic(.cancel)))
    }

    func testNextDeadlineIsExposedWhileAGestureIsTracked() {
        let h = Harness()
        XCTAssertNil(h.engine.nextDeadline)
        XCTAssertFalse(h.engine.isTracking)

        h.scroll(.began)
        h.scroll(.changed, dx: -40)
        XCTAssertNotNil(h.engine.nextDeadline)
        XCTAssertTrue(h.engine.isTracking)
    }
}

final class CallbackMetricsTests: XCTestCase {

    func testEmptyMetricsSaySo() {
        XCTAssertEqual(CallbackMetrics().summary, "aucun callback")
    }

    func testMetricsKeepCountAverageAndMax() {
        var metrics = CallbackMetrics()
        metrics.record(10_000)
        metrics.record(30_000)
        metrics.record(20_000)
        XCTAssertEqual(metrics.count, 3)
        XCTAssertEqual(metrics.maxNanoseconds, 30_000)
        XCTAssertEqual(metrics.summary, "3 callbacks, moyenne 20 µs, max 30 µs")
    }

    /// Une échéance dépassée part avec la cible d'alors : la fermeture qui
    /// attendait un second pincement ne doit pas viser la fenêtre du geste
    /// suivant.
    func testALateDeadlineIsDeliveredWithItsOwnTarget() {
        let h = Harness()
        let first = CGRect(x: 0, y: 0, width: 800, height: 600)
        let second = CGRect(x: 900, y: 0, width: 400, height: 300)
        h.target = .window(AXUIElementCreateSystemWide(), frame: first)
        h.pinchIn()
        h.time += 0.5 // l'hôte n'a pas envoyé de tick
        h.target = .window(AXUIElementCreateSystemWide(), frame: second)
        h.engine.process(.magnify(cumulative: -0.01, phase: .began), at: h.cursor)

        let close = h.deliveries.first { $0.effects.contains(.commit(.close)) }
        guard case let .window(_, frame)? = close?.target else { return XCTFail("la fermeture doit partir") }
        XCTAssertEqual(frame, first, "vers la fenêtre du premier pincement")
        XCTAssertEqual(h.hitTests.count, 2, "le nouveau pincement a bien sa propre cible")
    }
}
