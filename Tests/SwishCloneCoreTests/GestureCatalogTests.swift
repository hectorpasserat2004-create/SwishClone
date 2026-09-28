import XCTest
@testable import SwishCloneCore

final class GestureCatalogTests: XCTestCase {

    /// Le catalogue et la table de `GestureSequence` ne peuvent pas diverger :
    /// chaque déclencheur listé mène à son action, sur sa cible.
    func testEveryTriggerResolvesToItsAction() {
        for entry in GestureCatalog.entries {
            for trigger in entry.triggers {
                let resolved: GestureAction? = switch trigger {
                case let .swipes(steps): GestureSequence.resolve(swipes: steps, on: entry.target)
                case let .pinches(steps): GestureSequence.resolve(pinches: steps, on: entry.target)
                case .doubleTap: GestureSequence.resolveDoubleTap(on: entry.target)
                }
                XCTAssertEqual(resolved, entry.action, "\(trigger) sur \(entry.target)")
            }
        }
    }

    func testEveryActionWithAGestureIsListedOnce() {
        let listed = GestureCatalog.entries.map(\.action)
        XCTAssertEqual(listed.count, Set(listed).count, "une action, une entrée")
        XCTAssertEqual(Set(listed), Set(GestureAction.allCases), "chaque action a son geste")
    }

    func testQuartersListBothOrdersAndTheirDiagonal() {
        let diagonals: [GestureAction: SwipeDirection] = [
            .topLeftQuarter: .upLeft, .topRightQuarter: .upRight,
            .bottomLeftQuarter: .downLeft, .bottomRightQuarter: .downRight,
        ]
        for (action, diagonal) in diagonals {
            let triggers = GestureCatalog.entry(for: action)?.triggers ?? []
            XCTAssertEqual(triggers.count, 3, "\(action)")
            XCTAssertEqual(triggers.first, .swipes([diagonal]), "la diagonale se montre d'abord : \(action)")
        }
    }

    func testRawValuesAreStableIdentifiers() {
        // Écrites dans les préférences de l'hôte : les changer réactiverait
        // en silence un geste coupé.
        XCTAssertEqual(GestureAction.leftHalf.rawValue, "leftHalf")
        XCTAssertEqual(GestureAction.quitApp.rawValue, "quitApp")
        XCTAssertEqual(GestureAction(rawValue: "bottomRightQuarter"), .bottomRightQuarter)
    }

    func testSymbols() {
        XCTAssertEqual(GestureTrigger.swipes([.left]).symbols, "←")
        XCTAssertEqual(GestureTrigger.swipes([.up, .up]).symbols, "↑↑")
        XCTAssertEqual(GestureTrigger.swipes([.down, .right]).symbols, "↓ puis →")
        XCTAssertEqual(GestureTrigger.swipes([.upLeft]).symbols, "↖")
        XCTAssertEqual(GestureTrigger.swipes([.upRight]).symbols, "↗")
        XCTAssertEqual(GestureTrigger.swipes([.downLeft]).symbols, "↙")
        XCTAssertEqual(GestureTrigger.swipes([.downRight]).symbols, "↘")
        XCTAssertEqual(GestureTrigger.pinches([.out]).symbols, "Écarter")
        XCTAssertEqual(GestureTrigger.pinches([.in_]).symbols, "Resserrer")
        XCTAssertEqual(GestureTrigger.pinches([.in_, .in_]).symbols, "Resserrer deux fois")
        XCTAssertEqual(GestureTrigger.pinches([.in_, .out]).symbols, "Resserrer puis Écarter")
        XCTAssertEqual(GestureTrigger.doubleTap.symbols, "Toucher deux fois")
        XCTAssertEqual(GestureTrigger.doubleTap.family, .tap)
    }

    // MARK: - Ce que la machine capture

    func testAcceptsMatchesTheFormerTableWhenNothingIsDisabled() {
        XCTAssertTrue(GestureSequence.accepts(.swipe, on: .titlebar))
        XCTAssertTrue(GestureSequence.accepts(.pinch, on: .titlebar))
        XCTAssertTrue(GestureSequence.accepts(.pinch, on: .dockApp))
        XCTAssertFalse(GestureSequence.accepts(.swipe, on: .dockApp))
    }

    func testDisablingTheOnlyDockGestureReleasesTheDock() {
        XCTAssertFalse(GestureSequence.accepts(.pinch, on: .dockApp, disabled: [.quitApp]))
        XCTAssertTrue(GestureSequence.accepts(.pinch, on: .titlebar, disabled: [.quitApp]))
    }

    func testOneRemainingGestureKeepsTheFamilyCaptured() {
        let allSwipesButOne = Set(GestureCatalog.entries.filter { $0.family == .swipe }.map(\.action))
            .subtracting([.bottomRightQuarter])
        XCTAssertTrue(GestureSequence.accepts(.swipe, on: .titlebar, disabled: allSwipesButOne))
        XCTAssertFalse(GestureSequence.accepts(.swipe, on: .titlebar, disabled: allSwipesButOne.union([.bottomRightQuarter])))
    }

    func testLabels() {
        XCTAssertEqual(GestureAction.minimize.label(), "Réduire dans le Dock")
        XCTAssertEqual(GestureAction.quitApp.label(appName: "Notes"), "Quitter Notes")
        XCTAssertEqual(GestureStateMachine.Preview.action(.leftHalf).label(), "Moitié gauche")
        XCTAssertEqual(GestureStateMachine.Preview.unrecognized.label(), "Aucune action")
    }
}
