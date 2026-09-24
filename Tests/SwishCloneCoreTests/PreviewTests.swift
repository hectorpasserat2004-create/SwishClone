import CoreGraphics
import XCTest
@testable import SwishCloneCore

final class PreviewContentTests: XCTestCase {

    private func content(_ action: GestureAction) -> PreviewContent {
        PreviewContent(.action(action))
    }

    func testZonesAreTheRealLayoutOnAUnitScreen() {
        XCTAssertEqual(content(.leftHalf), .zone(CGRect(x: 0, y: 0, width: 0.5, height: 1)))
        XCTAssertEqual(content(.bottomRightQuarter), .zone(CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)))
        XCTAssertEqual(content(.topHalf), .zone(CGRect(x: 0, y: 0, width: 1, height: 0.5)))
        XCTAssertEqual(content(.maximize), .zone(CGRect(x: 0, y: 0, width: 1, height: 1)))
    }

    func testEveryZoneMatchesWindowLayout() {
        // L'aperçu ne doit jamais montrer autre chose que ce que fera le lever.
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let actions: [GestureAction] = [
            .leftHalf, .rightHalf, .topHalf, .bottomHalf,
            .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter,
            .maximize, .centerReduced,
        ]
        for action in actions {
            XCTAssertEqual(content(action), .zone(WindowLayout.frame(for: action, in: unit)!), "\(action)")
        }
    }

    func testNonGeometricActionsAreSymbols() {
        XCTAssertEqual(content(.minimize), .symbol(.minimize))
        XCTAssertEqual(content(.toggleFullScreen), .symbol(.fullScreen))
        XCTAssertEqual(content(.close), .symbol(.close))
    }

    func testQuitAndUnrecognized() {
        XCTAssertEqual(content(.quitApp), .quitApp)
        XCTAssertEqual(PreviewContent(.unrecognized), .unrecognized)
    }

    func testLabels() {
        XCTAssertEqual(GestureStateMachine.Preview.action(.bottomRightQuarter).label(), "Quart en bas à droite")
        XCTAssertEqual(GestureStateMachine.Preview.action(.close).label(), "Fermer la fenêtre")
        XCTAssertEqual(GestureStateMachine.Preview.action(.quitApp).label(appName: "TextEdit"), "Quitter TextEdit")
        XCTAssertEqual(GestureStateMachine.Preview.action(.quitApp).label(), "Quitter l'app")
        XCTAssertEqual(GestureStateMachine.Preview.unrecognized.label(), "Aucune action")
    }
}

final class PreviewPlacementTests: XCTestCase {

    /// Écran 1440 × 900 en coordonnées AX (origine en haut à gauche).
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 64, height: 48)

    private func frame(cursor: CGPoint, screen: CGRect? = nil) -> CGRect {
        PreviewPlacement.frame(size: size, cursor: cursor, screen: screen ?? self.screen)
    }

    func testOnATitlebarNearTheTopThePanelIsBelowTheCursor() {
        let cursor = CGPoint(x: 720, y: 40)
        let panel = frame(cursor: cursor)
        XCTAssertGreaterThan(panel.minY, cursor.y, "sous le curseur")
        XCTAssertEqual(panel.midX, cursor.x, accuracy: 1)
    }

    func testOnTheBottomDockThePanelIsAboveTheIcon() {
        let cursor = CGPoint(x: 600, y: 880)
        let panel = frame(cursor: cursor)
        XCTAssertLessThan(panel.maxY, cursor.y, "au-dessus du curseur")
    }

    func testOnALeftDockThePanelIsToTheRight() {
        let cursor = CGPoint(x: 20, y: 450)
        let panel = frame(cursor: cursor)
        XCTAssertGreaterThan(panel.minX, cursor.x, "à droite du curseur")
    }

    func testThePanelNeverCoversTheCursor() {
        let cursors = [
            CGPoint(x: 720, y: 40), CGPoint(x: 600, y: 880), CGPoint(x: 20, y: 450),
            CGPoint(x: 1400, y: 30), CGPoint(x: 300, y: 600),
        ]
        for cursor in cursors {
            XCTAssertFalse(frame(cursor: cursor).contains(cursor), "\(cursor)")
        }
    }

    func testThePanelStaysOnScreen() {
        let corners = [CGPoint(x: 1, y: 1), CGPoint(x: 1439, y: 1), CGPoint(x: 1, y: 899), CGPoint(x: 1439, y: 899)]
        let bounds = screen.insetBy(dx: PreviewPlacement.margin, dy: PreviewPlacement.margin)
        for cursor in corners {
            XCTAssertTrue(bounds.contains(frame(cursor: cursor)), "\(cursor)")
        }
    }

    func testTinyScreenStillHoldsThePanel() {
        // Le décalage seul sortirait du cadre : c'est le maintien dans
        // l'écran qui le rattrape (écran à peine plus grand que le panneau,
        // ou écran mal identifié).
        let tiny = CGRect(x: 0, y: 0, width: 90, height: 70)
        let bounds = tiny.insetBy(dx: PreviewPlacement.margin, dy: PreviewPlacement.margin)
        for cursor in [CGPoint(x: 5, y: 5), CGPoint(x: 85, y: 65), CGPoint(x: 45, y: 2)] {
            XCTAssertTrue(bounds.contains(frame(cursor: cursor, screen: tiny)), "\(cursor)")
        }
    }

    func testCursorAtTheCenterPutsThePanelBelow() {
        let panel = frame(cursor: CGPoint(x: 720, y: 450))
        XCTAssertGreaterThan(panel.minY, 450)
    }

    func testSecondaryScreenAboveThePrimary() {
        let above = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let cursor = CGPoint(x: 960, y: -1060)
        let panel = frame(cursor: cursor, screen: above)
        XCTAssertTrue(above.contains(panel))
        XCTAssertGreaterThan(panel.minY, cursor.y)
    }

    func testCocoaConversionIsTheInverseOfAX() {
        let ax = CGRect(x: 100, y: 60, width: 64, height: 48)
        let cocoa = ScreenGeometry.cocoaRect(fromAX: ax, primaryScreenHeight: 900)
        XCTAssertEqual(cocoa, CGRect(x: 100, y: 792, width: 64, height: 48))
        XCTAssertEqual(ScreenGeometry.axRect(fromCocoa: cocoa, primaryScreenHeight: 900), ax)
    }
}
