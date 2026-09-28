import XCTest
@testable import SwishCloneCore

private typealias Machine = GestureStateMachine

/// Joue le rôle de l'hôte : une horloge, un test de cible, et un réveil à
/// chaque `nextDeadline` — exactement ce que fera le timer du tap.
private struct Driver {
    var machine: Machine
    var now: TimeInterval = 0
    var onTarget: GestureTargetKind? = .titlebar
    private(set) var hitTests = 0
    private(set) var effects: [Machine.Effect] = []
    private(set) var dispositions: [Machine.Disposition] = []

    init(blocks: Bool = true, configure: (inout Machine.Configuration) -> Void = { _ in }) {
        var configuration = Machine.Configuration()
        configuration.blocksEvents = blocks
        configure(&configuration)
        machine = Machine(configuration: configuration)
    }

    var commits: [GestureAction] {
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
            // Une échéance que le réveil ne fait pas avancer bouclerait sans
            // fin : un échec vaut mieux qu'un test bloqué.
            if machine.nextDeadline == deadline {
                XCTFail("échéance \(deadline) non tenue par un réveil à l'heure")
                break
            }
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
        let cases: [(dx: Double, dy: Double, action: GestureAction)] = [
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
        driver.swipe(dx: -4)
        XCTAssertEqual(driver.commits, [])
        XCTAssertEqual(driver.previews, [], "aucun aperçu sans direction candidate")
    }

    /// Les seuils par défaut, là où ils basculent : 5 pour le glissement,
    /// 0,02 pour le pincement.
    func testDefaultThresholdsSitAtFiveAndTwoHundredths() {
        var swipe = Driver()
        swipe.swipe(dx: -5)
        XCTAssertEqual(swipe.commits, [.leftHalf], "5 : le seuil est atteint")

        var weakPinch = Driver()
        weakPinch.pinch(to: [0.01, 0.017])
        weakPinch.wait(0.2)
        XCTAssertEqual(weakPinch.commits, [], "0,017 : sous le seuil")

        var pinch = Driver()
        pinch.pinch(to: [0.01, 0.023])
        pinch.wait(0.2)
        XCTAssertEqual(pinch.commits, [.toggleFullScreen], "0,023 : au-dessus")
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
        // Bas puis droite d'un seul mouvement : une seule étape, lue sur le
        // cumul (60, 30). ≈ 27° : trop plat pour une diagonale, la direction
        // dominante l'emporte. Sans diagonale, c'est la pause qui fait le quart.
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dy: 30)
        driver.move(dx: 60)
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [.rightHalf])
        XCTAssertEqual(driver.haptics, [])
    }

    // MARK: - Diagonales : le quart d'un seul mouvement

    func testADiagonalSwipeSnapsToItsQuarterWithoutPause() {
        let cases: [(dx: Double, dy: Double, action: GestureAction)] = [
            (-40, -40, .topLeftQuarter), // dy < 0 = haut
            (40, -40, .topRightQuarter),
            (-40, 40, .bottomLeftQuarter),
            (40, 40, .bottomRightQuarter),
        ]
        for (dx, dy, action) in cases {
            var driver = Driver()
            driver.scroll(.began)
            driver.move(dx: dx, dy: dy)
            XCTAssertEqual(driver.previews.last, .action(action), "aperçu dx=\(dx) dy=\(dy)")
            driver.scroll(.ended)
            XCTAssertEqual(driver.commits, [action], "dx=\(dx) dy=\(dy)")
            XCTAssertEqual(driver.haptics, [], "aucune étape validée : pas de pause")
        }
    }

    /// 30° et 60° : les bords de la zone diagonale.
    func testTheDiagonalZoneSpansThirtyToSixtyDegrees() {
        func action(dx: Double, dy: Double) -> [GestureAction] {
            var driver = Driver()
            driver.swipe(dx: dx, dy: dy)
            return driver.commits
        }
        XCTAssertEqual(action(dx: 40, dy: -22), [.rightHalf], "≈ 29° : une moitié")
        XCTAssertEqual(action(dx: 40, dy: -24), [.topRightQuarter], "≈ 31° : une diagonale")
        XCTAssertEqual(action(dx: 22, dy: -40), [.maximize], "≈ 61° : une moitié (↑)")
        XCTAssertEqual(action(dx: 24, dy: -40), [.topRightQuarter], "≈ 59° : une diagonale")
    }

    func testDiagonalsCanBeTurnedOff() {
        var driver = Driver { $0.diagonalRatio = 1.01 }
        driver.swipe(dx: 40, dy: 39)
        XCTAssertEqual(driver.commits, [.rightHalf])
    }

    func testADiagonalStepThenLeftFallsBackToTheLeftHalf() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dx: 40, dy: -40)
        driver.wait(0.35)
        XCTAssertEqual(driver.haptics, [.step], "la diagonale est une étape comme une autre")
        driver.move(dx: -40)
        XCTAssertEqual(driver.previews.last, .action(.leftHalf))
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [.leftHalf])
    }

    func testADisabledQuarterDisablesItsDiagonal() {
        var driver = Driver { $0.disabledActions = [.topRightQuarter] }
        driver.scroll(.began)
        driver.move(dx: 40, dy: -40)
        XCTAssertEqual(driver.previews.last, .unrecognized)
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [])
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

    // MARK: - Ce qui compte comme immobilité

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
        // Des `changed` sans déplacement (doigts posés, `stationary`) ne
        // repoussent pas l'annulation.
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
        driver.onTarget = nil
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

    func testPinchInClosesTheWindow() {
        var driver = Driver()
        driver.pinch(to: [-0.03, -0.08, -0.14])
        driver.wait(0.6)
        XCTAssertEqual(driver.commits, [.close])
    }

    func testPinchDecidesOnItsPeakNotOnItsLastValue() {
        // Le relâchement des doigts fait retomber la magnitude sous le seuil
        // juste avant le lever (constaté en Phase 5) : le pic doit l'emporter.
        var driver = Driver()
        driver.pinch(to: [0.05, 0.12, 0.08, 0.04])
        driver.wait(0.2)
        XCTAssertEqual(driver.commits, [.toggleFullScreen])
    }

    /// Un pincement n'enchaîne jamais d'étapes sans lever les doigts : en
    /// relâchant après avoir resserré, les doigts écartent un peu, et
    /// « resserrer puis écarter » ne fermerait plus rien.
    func testAPinchNeverChainsStepsEvenWithAPause() {
        var driver = Driver()
        driver.pinch(to: [-0.05, -0.12], phase: .changed)
        driver.wait(0.35)
        XCTAssertEqual(driver.haptics, [], "une pause ne valide pas d'étape")
        driver.pinch(to: [-0.08, -0.05], phase: .changed) // les doigts se relâchent
        XCTAssertEqual(driver.previews.last, .action(.close))
        driver.send(.magnify(cumulative: -0.05, phase: .ended))
        driver.wait(0.5)
        XCTAssertEqual(driver.commits, [.close])
    }

    func testPinchWithoutPhaseEndsOnTheSilenceThenWaitsForASecond() {
        var driver = Driver()
        driver.pinch(to: [-0.05, -0.12])
        driver.wait(0.15 + 0.39)
        XCTAssertEqual(driver.commits, [], "silence de 0,15 s, puis 0,4 s d'attente")
        driver.wait(0.02)
        XCTAssertEqual(driver.commits, [.close])
    }

    func testOffTargetPinchPassesAndIsCheckedOnce() {
        var driver = Driver()
        driver.onTarget = nil
        driver.pinch(to: [0.05, 0.1, 0.15, 0.2])
        driver.wait(0.2)
        XCTAssertEqual(Set(driver.dispositions), [.pass])
        XCTAssertEqual(driver.hitTests, 1)
        XCTAssertEqual(driver.commits, [])

        driver.onTarget = .titlebar
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
        driver.wait(0.6)
        XCTAssertEqual(driver.commits, [.toggleFullScreen, .close])
    }

    // MARK: - Resserrer deux fois

    /// Un pincement entier, avec phase : resserrer puis lever.
    private func pinchIn(_ driver: inout Driver, to peak: Double = -0.12) {
        driver.send(.magnify(cumulative: -0.01, phase: .began))
        driver.pinch(to: [peak / 2, peak], phase: .changed)
        driver.send(.magnify(cumulative: peak, phase: .ended))
    }

    func testPinchingInTwiceQuitsTheApp() {
        var driver = Driver()
        pinchIn(&driver)
        XCTAssertEqual(driver.commits, [], "fermer attend un éventuel second pincement")
        XCTAssertEqual(driver.previews.last, .action(.close), "l'aperçu reste affiché pendant l'attente")
        driver.wait(0.3) // l'écart mesuré entre deux pincements enchaînés
        pinchIn(&driver)
        XCTAssertEqual(driver.previews.dropLast().last, .action(.quitWindowApp), "le second annonce « quitter »")
        XCTAssertEqual(driver.commits, [.quitWindowApp], "quitter, et pas fermer avant")
        XCTAssertEqual(driver.hitTests, 1, "le second pincement vise la même fenêtre")
        driver.wait(1)
        XCTAssertEqual(driver.commits, [.quitWindowApp])
    }

    func testTheCloseWaitsExactlyTheDoubleInterval() {
        var driver = Driver()
        pinchIn(&driver)
        driver.wait(0.39)
        XCTAssertEqual(driver.commits, [])
        driver.wait(0.02)
        XCTAssertEqual(driver.commits, [.close])
        XCTAssertEqual(driver.previews.last, .some(nil), "l'aperçu disparaît avec l'action")
    }

    func testTheIntervalIsASetting() {
        var driver = Driver { $0.doublePinchInterval = 0.2 }
        pinchIn(&driver)
        driver.wait(0.21)
        XCTAssertEqual(driver.commits, [.close])
    }

    func testASecondPinchTooLateIsANewGesture() {
        var driver = Driver()
        pinchIn(&driver)
        driver.wait(0.5)
        pinchIn(&driver)
        driver.wait(0.5)
        XCTAssertEqual(driver.commits, [.close, .close])
        XCTAssertEqual(driver.hitTests, 2)
    }

    func testASecondPinchThatSpreadsStillCloses() {
        var driver = Driver()
        pinchIn(&driver)
        driver.wait(0.2)
        driver.send(.magnify(cumulative: 0.01, phase: .began))
        driver.pinch(to: [0.08, 0.15], phase: .changed)
        XCTAssertEqual(driver.previews.last, .action(.close), "ce qui partira : la fermeture du premier")
        driver.send(.magnify(cumulative: 0.15, phase: .ended))
        XCTAssertEqual(driver.commits, [.close])
    }

    func testWithQuitDisabledTheCloseIsImmediate() {
        var driver = Driver { $0.disabledActions = [.quitWindowApp] }
        pinchIn(&driver)
        XCTAssertEqual(driver.commits, [.close])
    }

    func testWithCloseDisabledPinchingTwiceStillQuits() {
        var driver = Driver { $0.disabledActions = [.close] }
        pinchIn(&driver)
        driver.wait(0.2)
        pinchIn(&driver)
        XCTAssertEqual(driver.commits, [.quitWindowApp])

        var once = Driver { $0.disabledActions = [.close] }
        pinchIn(&once)
        once.wait(1)
        XCTAssertEqual(once.commits, [], "resserrer une fois : rien")
    }

    func testASwipeDuringTheWaitClosesFirstAndIsNotTracked() {
        var driver = Driver()
        pinchIn(&driver)
        driver.wait(0.1)
        driver.scroll(.began)
        XCTAssertEqual(driver.commits, [.close])
        XCTAssertEqual(driver.dispositions.last, .pass)
        XCTAssertEqual(driver.hitTests, 1, "pas de test de cible dans le même appel que la fermeture")
    }

    func testAHostWokenLateSettlesTheWaitBeforeTheNextPinch() {
        var driver = Driver()
        pinchIn(&driver)
        driver.now += 0.5 // sans tick
        driver.send(.magnify(cumulative: -0.01, phase: .began), after: 0)
        XCTAssertEqual(driver.commits, [.close], "trop tard pour un double : la fermeture part")
        XCTAssertEqual(driver.hitTests, 2, "et ce pincement-ci est un nouveau geste")
    }

    func testPinchingInTwiceOnADockIconQuitsImmediatelyEachTime() {
        var driver = Driver()
        driver.onTarget = .dockApp
        pinchIn(&driver)
        XCTAssertEqual(driver.commits, [.quitApp], "pas de double sur le Dock : aucune attente")
    }

    // MARK: - Toucher deux fois

    func testDoubleTapCentersTheWindow() {
        var driver = Driver()
        driver.send(.smartMagnify)
        XCTAssertEqual(driver.commits, [.centerReduced])
        XCTAssertEqual(driver.hitTests, 1)
    }

    func testDoubleTapElsewhereDoesNothing() {
        var off = Driver()
        off.onTarget = nil
        off.send(.smartMagnify)
        XCTAssertEqual(off.commits, [])
        XCTAssertEqual(off.dispositions, [.pass], "le zoom intelligent reste à l'app")

        var dock = Driver()
        dock.onTarget = .dockApp
        dock.send(.smartMagnify)
        XCTAssertEqual(dock.commits, [])
    }

    func testDisabledDoubleTapSkipsTheHitTest() {
        var driver = Driver { $0.disabledActions = [.centerReduced] }
        driver.send(.smartMagnify)
        XCTAssertEqual(driver.commits, [])
        XCTAssertEqual(driver.hitTests, 0)
    }

    func testDoubleTapDuringAGestureIsIgnored() {
        var driver = Driver()
        driver.scroll(.began)
        driver.send(.smartMagnify)
        XCTAssertEqual(driver.commits, [])
        XCTAssertEqual(driver.hitTests, 1)
    }

    func testDoubleTapDuringTheWaitClosesInstead() {
        var driver = Driver()
        pinchIn(&driver)
        driver.send(.smartMagnify)
        XCTAssertEqual(driver.commits, [.close])
    }

    // MARK: - Icône du Dock

    func testPinchInOnADockIconQuitsTheApp() {
        var driver = Driver()
        driver.onTarget = .dockApp
        driver.pinch(to: [-0.03, -0.08, -0.14])
        XCTAssertEqual(driver.previews.last, .action(.quitApp), "l'aperçu annonce « quitter » avant le lever")
        driver.wait(0.2)
        XCTAssertEqual(driver.commits, [.quitApp])
    }

    func testPinchOutOnADockIconDoesNothingYet() {
        var driver = Driver()
        driver.onTarget = .dockApp
        driver.pinch(to: [0.05, 0.15])
        XCTAssertEqual(driver.previews.last, .unrecognized)
        driver.wait(0.2)
        XCTAssertEqual(driver.commits, [])
    }

    func testSwipeOnADockIconIsLeftToTheDock() {
        var driver = Driver(blocks: true)
        driver.onTarget = .dockApp
        driver.swipe(dx: 40)
        driver.momentum()
        XCTAssertEqual(driver.commits, [])
        XCTAssertEqual(driver.effects, [], "ni aperçu ni retour haptique")
        XCTAssertEqual(Set(driver.dispositions), [.pass], "jamais capturé, donc jamais avalé à l'étape 5")
    }

    func testTitlebarPinchInStillClosesTheWindow() {
        var driver = Driver()
        driver.pinch(to: [-0.05, -0.14])
        driver.wait(0.6)
        XCTAssertEqual(driver.commits, [.close], "la cible décide : fermer une fenêtre, pas quitter l'app")
    }

    // MARK: - Gestes désactivés un par un

    func testADisabledGestureNeitherPreviewsNorActs() {
        var driver = Driver { $0.disabledActions = [.minimize] }
        driver.scroll(.began)
        driver.move(dy: 40)
        XCTAssertEqual(driver.previews.last, .unrecognized, "un geste coupé ne s'annonce pas")
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [])
    }

    func testOtherGesturesOfTheFamilyStillWork() {
        var driver = Driver { $0.disabledActions = [.minimize] }
        driver.scroll(.began)
        driver.move(dy: 40)
        driver.wait(0.35)
        driver.move(dx: 40)
        XCTAssertEqual(driver.previews.last, .action(.bottomRightQuarter))
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [.bottomRightQuarter], "↓ coupé, ↓ puis → marche toujours")

        var halves = Driver { $0.disabledActions = [.minimize] }
        halves.scroll(.began)
        halves.move(dy: 40)
        halves.wait(0.35)
        halves.move(dy: 40)
        halves.scroll(.ended)
        XCTAssertEqual(halves.commits, [.bottomHalf])
    }

    func testDisabledCloseLeavesFullScreen() {
        var driver = Driver { $0.disabledActions = [.close] }
        driver.pinch(to: [-0.05, -0.14])
        driver.wait(0.2)
        XCTAssertEqual(driver.commits, [])
        driver.wait(0.5)
        driver.pinch(to: [0.05, 0.15])
        driver.wait(0.2)
        XCTAssertEqual(driver.commits, [.toggleFullScreen])
    }

    func testDisabledQuitLeavesTheDockAlone() {
        var driver = Driver(blocks: true) { $0.disabledActions = [.quitApp] }
        driver.onTarget = .dockApp
        driver.pinch(to: [-0.03, -0.08, -0.14])
        driver.wait(0.2)
        XCTAssertEqual(driver.commits, [])
        XCTAssertEqual(driver.effects, [], "ni aperçu ni retour haptique")
        XCTAssertEqual(Set(driver.dispositions), [.pass], "le Dock garde son pincement")
    }

    func testAllSwipesDisabledSkipsTheHitTest() {
        let swipes = Set(GestureCatalog.entries.filter { $0.family == .swipe }.map(\.action))
        var driver = Driver { $0.disabledActions = swipes }
        driver.swipe(dx: 40)
        XCTAssertEqual(driver.commits, [])
        XCTAssertEqual(driver.hitTests, 0, "rien à faire : pas même un test de cible")
        XCTAssertEqual(Set(driver.dispositions), [.pass])
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
        XCTAssertEqual(driver.machine.nextDeadline!, driver.now + 0.15, accuracy: 1e-9)
    }

    /// Un hôte réveillé pile à l'échéance, avec une horloge loin de 0 comme
    /// `systemUptime` : l'échéance doit être tenue quel que soit l'arrondi.
    /// Plusieurs ordres de grandeur, parce que l'arrondi en dépend : vers
    /// 100 000 il trahit la pause de 0,2 s, vers 1 000 le délai de 0,8 s.
    func testATickExactlyAtTheDeadlineIsEnoughFarFromZero() {
        let starts = [1_000.0, 10_000.0, 100_000.0, 1_000_000.0].flatMap { base in
            (0 ..< 20).map { base + Double($0) * 0.37 }
        }
        for start in starts {
            var step = Driver()
            step.now = start
            step.scroll(.began)
            step.move(dy: -40)
            step.now = step.machine.nextDeadline!
            step.send(.tick, after: 0)
            XCTAssertEqual(step.haptics, [.step], "pause, départ \(start)")

            var cancel = Driver()
            cancel.now = start
            cancel.scroll(.began)
            cancel.move(dy: -40)
            cancel.wait(0.2)
            cancel.now = cancel.machine.nextDeadline!
            cancel.send(.tick, after: 0)
            XCTAssertEqual(cancel.haptics, [.step, .cancel], "annulation, départ \(start)")

            var pinch = Driver()
            pinch.now = start
            pinch.pinch(to: [0.05, 0.2])
            pinch.now = pinch.machine.nextDeadline!
            pinch.send(.tick, after: 0)
            XCTAssertEqual(pinch.commits, [.toggleFullScreen], "fin de pincement, départ \(start)")
        }
    }

    func testFifteenHundredthsValidateAStep() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dy: -40)
        driver.wait(0.14)
        XCTAssertEqual(driver.haptics, [], "pas encore")
        driver.wait(0.02)
        XCTAssertEqual(driver.haptics, [.step], "0,15 s d'immobilité valident l'étape")
        driver.move(dy: -40)
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [.topHalf])
    }
}

// MARK: - Enchaînement illimité, sans lever les doigts

extension GestureStateMachineTests {

    func testChangingYourMindAcrossThreeStepsLandsOnTheLatestQuarter() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dy: -40)              // ↑
        driver.wait(0.35)
        driver.move(dx: 40)               // →  : quart en haut à droite
        driver.wait(0.35)
        XCTAssertEqual(driver.previews.last, .action(.topRightQuarter))
        driver.move(dy: 40)               // ↓  : on change d'avis
        XCTAssertEqual(driver.previews.last, .action(.bottomRightQuarter))
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [.bottomRightQuarter])
        XCTAssertEqual(driver.haptics, [.step, .step], "deux étapes validées, la troisième part au lever")
    }

    func testFourStepsKeepFollowingTheLatestOfEachAxis() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dx: -40)              // ←
        driver.wait(0.35)
        driver.move(dy: 40)               // ↓
        driver.wait(0.35)
        driver.move(dx: 40)               // →
        driver.wait(0.35)
        driver.move(dy: -40)              // ↑
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [.topRightQuarter])
        XCTAssertEqual(driver.haptics, [.step, .step, .step])
    }

    func testInvertingTheHorizontalOnAQuarterFallsBackToAHalf() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dy: -40)              // ↑
        driver.wait(0.35)
        driver.move(dx: 40)               // →  : quart en haut à droite
        driver.wait(0.35)
        XCTAssertEqual(driver.previews.last, .action(.topRightQuarter))
        driver.move(dx: -40)              // ←  : inversion, la verticale s'efface
        XCTAssertEqual(driver.previews.last, .action(.leftHalf))
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [.leftHalf])
    }

    func testTwoConsecutiveDownStepsAfterAQuarterForceTheBottomHalf() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dx: -40)              // ←
        driver.wait(0.35)
        driver.move(dy: -40)              // ↑  : quart haut-gauche
        driver.wait(0.35)
        driver.move(dy: 40)               // ↓  : quart bas-gauche
        driver.wait(0.35)
        XCTAssertEqual(driver.previews.last, .action(.bottomLeftQuarter))
        driver.move(dy: 40)               // ↓ encore : retour à la moitié basse
        XCTAssertEqual(driver.previews.last, .action(.bottomHalf))
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [.bottomHalf])
        XCTAssertEqual(driver.haptics, [.step, .step, .step])
    }

    func testChangingYourMindOnOneAxisIsPreviewedAsUnrecognizedAndDoesNothing() {
        var driver = Driver()
        driver.scroll(.began)
        driver.move(dy: -40)              // ↑
        driver.wait(0.35)
        driver.move(dy: 40)               // ↓
        XCTAssertEqual(driver.previews.last, .unrecognized)
        driver.scroll(.ended)
        XCTAssertEqual(driver.commits, [])
    }
}
