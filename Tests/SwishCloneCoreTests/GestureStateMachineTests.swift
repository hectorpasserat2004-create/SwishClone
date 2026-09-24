import XCTest
@testable import SwishCloneCore

private typealias Machine = GestureStateMachine

/// Joue le rôle de l'hôte : une horloge, un test de cible, et un réveil à
/// chaque `nextDeadline` — exactement ce que fera le timer du tap.
private struct Driver {
    var machine: Machine
    var now: TimeInterval = 0
    var onTarget = true
    private(set) var hitTests = 0
    private(set) var effects: [Machine.Effect] = []
    private(set) var dispositions: [Machine.Disposition] = []

    init(blocks: Bool = true, configure: (inout Machine.Configuration) -> Void = { _ in }) {
        var configuration = Machine.Configuration()
        configuration.blocksEvents = blocks
        configure(&configuration)
        machine = Machine(configuration: configuration)
    }

    var commits: [WindowAction] {
        effects.compactMap { if case let .commit(action) = $0 { action } else { nil } }
    }

    var haptics: [Machine.Haptic] {
        effects.compactMap { if case let .haptic(haptic) = $0 { haptic } else { nil } }
    }

    var previews: [Machine.Preview?] {
        effects.compactMap {
            switch $0 {
            case let .showPreview(preview): .some(preview)
            case .hidePreview: .some(nil)
            default: nil
            }
        }
    }

    /// Avance l'horloge en réveillant la machine à chacune de ses échéances.
    mutating func wait(_ duration: TimeInterval) {
        let end = now + duration
        while let deadline = machine.nextDeadline, deadline <= end {
            now = max(now, deadline)
            send(.tick, after: 0)
        }
        now = end
    }

    @discardableResult
    mutating func send(_ event: Machine.Event, after delay: TimeInterval = 0.01) -> Machine.Disposition {
        if delay > 0 { wait(delay) }
        let isOnTarget = onTarget
        var calls = 0
        let output = machine.handle(event, at: now) {
            calls += 1
            return isOnTarget
        }
        hitTests += calls
        effects += output.effects
        if event != .tick { dispositions.append(output.disposition) }
        return output.disposition
    }

    mutating func scroll(_ phase: Machine.Phase, dx: Double = 0, dy: Double = 0) {
        send(.scroll(phase: phase, momentum: nil, dx: dx, dy: dy))
    }

    /// Un mouvement continu, découpé en événements `changed` de 10 ms.
    mutating func move(dx: Double = 0, dy: Double = 0, events: Int = 5) {
        for _ in 0 ..< events {
            scroll(.changed, dx: dx / Double(events), dy: dy / Double(events))
        }
    }

    mutating func momentum(events: Int = 3) {
        send(.scroll(phase: nil, momentum: .began, dx: 1, dy: 0))
        for _ in 0 ..< events { send(.scroll(phase: nil, momentum: .changed, dx: 1, dy: 0)) }
        send(.scroll(phase: nil, momentum: .ended, dx: 0, dy: 0))
    }

    /// Un swipe complet : posé, glissé, levé.
    mutating func swipe(dx: Double = 0, dy: Double = 0) {
        scroll(.began)
        move(dx: dx, dy: dy)
        scroll(.ended)
    }

    mutating func pinch(to magnitudes: [Double], phase: Machine.Phase? = nil) {
        for magnitude in magnitudes {
            send(.magnify(cumulative: magnitude, phase: phase))
        }
    }
}

final class GestureStateMachineTests: XCTestCase {

    // MARK: - Un swipe, une action, au lever

    func testSimpleSwipesMapToTheirActions() {
        let cases: [(dx: Double, dy: Double, action: WindowAction)] = [
            (-40, 0, .leftHalf),
            (40, 0, .rightHalf),
            (0, -40, .maximize), // dy < 0 = haut (convention scrollWheel)
            (0, 40, .minimize),
        ]
        for (dx, dy, action) in cases {
            var driver = Driver()
            driver.swipe(dx: dx, dy: dy)
            XCTAssertEqual(driver.commits, [action], "dx=\(dx) dy=\(dy)")
        }
    }

    func testActionWaitsForTheLift() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dx: -40)
        XCTAssertEqual(driver.commits, [], "rien ne doit partir tant que les doigts sont posés")
        XCTAssertEqual(driver.previews.last, .action(.leftHalf), "mais l'aperçu montre déjà la cible")

        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [.leftHalf])
        XCTAssertEqual(driver.previews.last, .some(nil), "l'aperçu disparaît au lever")
    }

    func testBelowThresholdDoesNothing() {
        var driver = Driver()
        driver.swipe(dx: -10)
        XCTAssertEqual(driver.commits, [])
        XCTAssertEqual(driver.previews, [], "aucun aperçu sans direction candidate")
    }

    // MARK: - Enchaînement sans lever les doigts

    func testDownPauseRightSnapsToBottomRightQuarter() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dy: 40)
        XCTAssertEqual(driver.previews.last, .action(.minimize))

        driver.wait(0.35) // pause : l'étape ↓ est validée
        XCTAssertEqual(driver.haptics, [.step])

        driver.move(dx: 40)
        XCTAssertEqual(driver.previews.last, .action(.bottomRightQuarter))
        driver.scroll(.ended)

        XCTAssertEqual(driver.commits, [.bottomRightQuarter])
    }

    func testQuartersWorkInBothOrders() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dx: 40)
        driver.wait(0.35)
        driver.move(dy: 40)
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [.bottomRightQuarter])

        var other = Driver()
        other.scroll(.began)
        other.move(dy: -40)
        other.wait(0.35)
        other.move(dx: -40)
        other.scroll(.ended)
        XCTAssertEqual(other.commits, [.topLeftQuarter])
    }

    func testDoubleVerticalSwipesSnapToHalves() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dy: -40)
        driver.wait(0.35)
        driver.move(dy: -40)
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [.topHalf])

        var down = Driver()
        down.scroll(.began)
        down.move(dy: 40)
        down.wait(0.35)
        down.move(dy: 40)
        down.scroll(.ended)
        XCTAssertEqual(down.commits, [.bottomHalf])
    }

    func testWithoutPauseTheGestureStaysOneStep() {
        // Bas puis droite d'un seul mouvement : une seule étape, dont la
        // direction dominante l'emporte. C'est la pause qui fait le quart.
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dy: 30)
        driver.move(dx: 60)
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [.rightHalf])
        XCTAssertEqual(driver.haptics, [])
    }

    func testUnknownSequenceIsPreviewedAsSuchAndDoesNothing() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dx: -40)
        driver.wait(0.35)
        driver.move(dx: -40)
        XCTAssertEqual(driver.previews.last, .unrecognized)
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [])
    }

    // MARK: - Annulation

    func testStayingStillCancels() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dx: -40)
        driver.wait(0.9)

        XCTAssertTrue(driver.effects.contains(.cancelled(.stillness)))
        XCTAssertEqual(driver.previews.last, .some(nil))

        driver.move(dx: 40)
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [], "un geste annulé ne fait rien, même si on rebouge")
    }

    func testPauseValidatesAStepThenLongerStillnessCancels() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dy: 40)
        driver.wait(0.35)
        XCTAssertEqual(driver.haptics, [.step])
        driver.wait(0.5) // 0,85 s d'immobilité en tout
        XCTAssertEqual(driver.haptics, [.step, .cancel])
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [])
    }

    func testEscapeCancels() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dx: 40)
        XCTAssertEqual(driver.send(.escape), .swallow, "Échap ne doit pas atteindre l'app pendant un geste")
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [])
        XCTAssertTrue(driver.effects.contains(.cancelled(.escape)))
    }

    func testSystemInterruptionIsReportedAsSuch() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dx: 40)
        driver.scroll(.cancelled)
        XCTAssertTrue(driver.effects.contains(.cancelled(.interrupted)))
    }

    // MARK: - Point 1 du test manuel : ce que la machine fait aujourd'hui
    //
    // Ces deux tests décrivent le comportement actuel, pour le diagnostic —
    // ils ne disent pas que c'est le bon.

    func testStillnessIsCountedFromTheLastMovementNotFromTheGestureStart() {
        // Un long premier mouvement (1 s) ne consomme pas le délai : c'est
        // l'immobilité qui compte.
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dx: -40, events: 100)
        driver.wait(0.35)
        XCTAssertEqual(driver.haptics, [.step])
        driver.wait(0.4) // 0,75 s d'immobilité : pas encore annulé
        driver.move(dy: 40)
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [.bottomLeftQuarter])
    }

    func testChangedEventsWithoutDeltaDoNotCountAsMovement() {
        // Si macOS verrouille l'axe du défilement après « gauche », le
        // « bas » qui suit arrive en `changed` à deltas nuls : la machine n'y
        // voit aucun mouvement et annule.
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dx: -40)
        driver.wait(0.35)
        for _ in 0 ..< 60 { driver.scroll(.changed, dx: 0, dy: 0) } // 0,6 s de « bas » écrasé
        XCTAssertTrue(driver.effects.contains(.cancelled(.stillness)))
    }

    func testEscapeOutsideAGesturePasses() {
        var driver = Driver()
        XCTAssertEqual(driver.send(.escape), .pass)
    }

    func testRestingFingersThenLiftingIsNotAFailedGesture() {
        var driver = Driver()
        driver.scroll(.mayBegin)
        driver.scroll(.cancelled)
        XCTAssertEqual(driver.effects, [], "ni aperçu, ni haptique, ni « annulé »")
    }

    // MARK: - Ce qui est avalé, et quand

    func testCapturedGestureIsSwallowedAsAWholeIncludingMomentum() {
        var driver = Driver(blocks: true)
        driver.swipe(dx: 40)
        driver.momentum()
        XCTAssertEqual(Set(driver.dispositions), [.swallow])
    }

    func testMayBeginArmsTheSameGesture() {
        var driver = Driver()
        driver.scroll(.mayBegin)
        driver.scroll(.began)
        driver.move(dx: 40)
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [.rightHalf])
        XCTAssertEqual(driver.hitTests, 1)
        XCTAssertEqual(Set(driver.dispositions), [.swallow])
    }

    func testOffTargetGesturePassesEntirely() {
        var driver = Driver()
        driver.onTarget = false
        driver.swipe(dx: 40)
        driver.momentum()
        XCTAssertEqual(Set(driver.dispositions), [.pass])
        XCTAssertEqual(driver.effects, [])
        XCTAssertEqual(driver.hitTests, 1, "une seule vérification de cible par geste")
    }

    func testNonBlockingModeTracksButLetsEverythingPass() {
        var driver = Driver(blocks: false)
        driver.swipe(dx: 40)
        driver.momentum()
        XCTAssertEqual(Set(driver.dispositions), [.pass])
        XCTAssertEqual(driver.commits, [.rightHalf])
    }

    func testMouseWheelIsNeverAGesture() {
        var driver = Driver()
        driver.send(.scroll(phase: nil, momentum: nil, dx: 0, dy: 40))
        XCTAssertEqual(driver.dispositions, [.pass])
        XCTAssertEqual(driver.hitTests, 0)
    }

    func testMomentumOfAnUncapturedScrollPasses() {
        var driver = Driver()
        driver.momentum()
        XCTAssertEqual(Set(driver.dispositions), [.pass])
    }

    func testDisabledSwipeSkipsTheHitTest() {
        var driver = Driver { $0.swipeEnabled = false }
        driver.swipe(dx: 40)
        XCTAssertEqual(driver.commits, [])
        XCTAssertEqual(driver.hitTests, 0)
        XCTAssertEqual(Set(driver.dispositions), [.pass])
    }

    // MARK: - Pincement

    func testPinchOutTogglesFullScreenAfterTheSilence() {
        var driver = Driver()
        driver.pinch(to: [0.02, 0.06, 0.12, 0.15])
        XCTAssertEqual(driver.commits, [], "rien avant le lever")
        driver.wait(0.2) // silence > pinchSessionGap
        XCTAssertEqual(driver.commits, [.toggleFullScreen])
    }

    func testPinchInCentersForNow() {
        var driver = Driver()
        driver.pinch(to: [-0.03, -0.08, -0.14])
        driver.wait(0.2)
        XCTAssertEqual(driver.commits, [.centerReduced])
    }

    func testPinchDecidesOnItsPeakNotOnItsLastValue() {
        // Le relâchement des doigts fait retomber la magnitude sous le seuil
        // juste avant le lever (constaté en Phase 5) : le pic doit l'emporter.
        var driver = Driver()
        driver.pinch(to: [0.05, 0.12, 0.08, 0.04])
        driver.wait(0.2)
        XCTAssertEqual(driver.commits, [.toggleFullScreen])
    }

    func testPinchWithPhaseEndsOnEndedAndCanChainSteps() {
        var driver = Driver()
        driver.pinch(to: [-0.05, -0.12], phase: .changed)
        driver.wait(0.35)
        XCTAssertEqual(driver.haptics, [.step], "avec la phase, une pause valide l'étape")
        driver.pinch(to: [-0.18, -0.26], phase: .changed)
        XCTAssertEqual(driver.previews.last, .unrecognized, "« resserrer ×2 » n'a pas encore d'action (P1 : quitter)")
        driver.send(.magnify(cumulative: -0.26, phase: .ended))
        XCTAssertEqual(driver.commits, [])
    }

    func testPinchWithoutPhaseCannotChain() {
        // Sans phase, le silence de 150 ms vaut lever — il arrive avant la
        // pause d'étape de 300 ms. Le double pincement exigera la phase.
        var driver = Driver()
        driver.pinch(to: [-0.05, -0.12])
        driver.wait(0.35)
        XCTAssertEqual(driver.haptics, [])
        XCTAssertEqual(driver.commits, [.centerReduced])
    }

    func testOffTargetPinchPassesAndIsCheckedOnce() {
        var driver = Driver()
        driver.onTarget = false
        driver.pinch(to: [0.05, 0.1, 0.15, 0.2])
        driver.wait(0.2)
        XCTAssertEqual(Set(driver.dispositions), [.pass])
        XCTAssertEqual(driver.hitTests, 1)
        XCTAssertEqual(driver.commits, [])

        driver.onTarget = true
        driver.pinch(to: [0.05, 0.15]) // nouveau pincement : nouvelle vérification
        driver.wait(0.2)
        XCTAssertEqual(driver.hitTests, 2)
        XCTAssertEqual(driver.commits, [.toggleFullScreen])
    }

    func testLateHostStillSeparatesTwoPinches() {
        // Un hôte qui n'a pas envoyé de tick : le pincement suivant, arrivé
        // après le silence, clôt le précédent avant de commencer.
        var driver = Driver()
        driver.pinch(to: [0.05, 0.15])
        driver.now += 0.5 // sans tick
        driver.send(.magnify(cumulative: -0.05, phase: nil), after: 0)
        driver.pinch(to: [-0.15])
        driver.wait(0.2)
        XCTAssertEqual(driver.commits, [.toggleFullScreen, .centerReduced])
    }

    // MARK: - Remise à zéro

    func testResetAbandonsTheGestureWithoutActingAndHidesThePreview() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dx: 40)
        XCTAssertEqual(driver.machine.reset(), [.hidePreview])
        XCTAssertFalse(driver.machine.isTracking)
        XCTAssertNil(driver.machine.nextDeadline)

        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [], "la fin d'un geste abandonné ne déclenche rien")
    }

    // MARK: - Échéances

    func testNoDeadlineWhenIdle() {
        let machine = Machine()
        XCTAssertNil(machine.nextDeadline)
    }

    func testDeadlineIsTheStepPauseOnceADirectionIsCandidate() {
        var driver = Driver()
        driver.scroll(.began)
        XCTAssertEqual(driver.machine.nextDeadline!, driver.now + 0.8, accuracy: 1e-9)
        driver.move(dx: 40)
        XCTAssertEqual(driver.machine.nextDeadline!, driver.now + 0.3, accuracy: 1e-9)
    }
}
