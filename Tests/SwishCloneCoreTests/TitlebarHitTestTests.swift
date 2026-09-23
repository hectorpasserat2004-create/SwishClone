import CoreGraphics
import XCTest
@testable import SwishCloneCore

/// Les chemins AX ci-dessous sont des formes typiques (élément touché en
/// premier, puis ses parents), pas des relevés : ils seront confrontés aux
/// vraies apps au test manuel de l'étape 2.
final class TitlebarHitTestTests: XCTestCase {

    /// Fenêtre de 800 × 600 dont le haut est à y = 50 (coordonnées AX).
    private let frame = CGRect(x: 100, y: 50, width: 800, height: 600)
    private let standard = AXNodeInfo(role: "AXWindow", subrole: "AXStandardWindow")

    private func node(_ role: String, _ subrole: String? = nil) -> AXNodeInfo {
        AXNodeInfo(role: role, subrole: subrole)
    }

    private func verdict(
        _ path: [AXNodeInfo],
        window: AXNodeInfo? = nil,
        y: CGFloat,
        x: CGFloat = 400,
        zone: Double = 40
    ) -> TitlebarHitTest.Verdict {
        TitlebarHitTest.evaluate(
            path: path,
            window: window ?? standard,
            windowFrame: frame,
            point: CGPoint(x: x, y: y),
            zoneHeight: zone
        )
    }

    // MARK: - Barres de titre reconnues

    func testNativeTitlebarIsTheWindowItselfNearItsTop() {
        XCTAssertEqual(verdict([], y: 60), .titlebar)
    }

    func testWindowBackgroundBelowTheZoneIsNotATitlebar() {
        XCTAssertEqual(verdict([], y: 200), .outsideZone)
    }

    func testToolbarCountsEvenBelowTheZone() {
        // Finder, Mail : la barre d'outils unifiée dépasse les 40 points.
        let path = [node("AXButton"), node("AXGroup"), node("AXToolbar")]
        XCTAssertEqual(verdict(path, y: 85), .titlebar)
    }

    func testCustomTabStripFallsBackOnGeometry() {
        // Chrome, Electron : barre dessinée à la main, que AX décrit comme
        // des groupes — c'est la bande du haut qui décide.
        let path = [node("AXRadioButton", "AXTabButton"), node("AXTabGroup"), node("AXGroup")]
        XCTAssertEqual(verdict(path, y: 70), .titlebar)
        XCTAssertEqual(verdict(path, y: 120), .outsideZone)
    }

    func testZoneBoundaryIsInclusiveAndFollowsTheSetting() {
        XCTAssertEqual(verdict([], y: 90), .titlebar) // 50 + 40
        XCTAssertEqual(verdict([], y: 91), .outsideZone)
        XCTAssertEqual(verdict([], y: 140, zone: 100), .titlebar)
    }

    func testPointOutsideTheWindowWidthIsNotATitlebar() {
        XCTAssertEqual(verdict([], y: 60, x: 950), .outsideZone)
    }

    // MARK: - Ce qui reste à l'app

    func testAddressBarInToolbarIsExcluded() {
        // Safari : la barre d'adresse est dans la barre d'outils, mais un
        // swipe dessus appartient au champ.
        let path = [node("AXTextField"), node("AXGroup"), node("AXToolbar")]
        XCTAssertEqual(verdict(path, y: 60), .excludedElement(role: "AXTextField"))
    }

    func testWebContentNearTheTopIsExcluded() {
        let path = [node("AXGroup"), node("AXWebArea"), node("AXScrollArea"), node("AXGroup")]
        XCTAssertEqual(verdict(path, y: 60), .excludedElement(role: "AXWebArea"))
    }

    func testScrollableTabBarIsExcluded() {
        // Firefox : une barre d'onglets qui défile (Swish 1.13.2).
        let path = [node("AXRadioButton"), node("AXTabGroup"), node("AXScrollArea")]
        XCTAssertEqual(verdict(path, y: 60), .excludedElement(role: "AXScrollArea"))
    }

    func testSliderInToolbarIsExcluded() {
        // Music : curseur de volume dans la barre d'outils (Swish 1.11).
        let path = [node("AXSlider"), node("AXToolbar")]
        XCTAssertEqual(verdict(path, y: 60), .excludedElement(role: "AXSlider"))
    }

    func testPopoverIsExcluded() {
        let path = [node("AXButton"), node("AXPopover")]
        XCTAssertEqual(verdict(path, y: 60), .excludedElement(role: "AXPopover"))
    }

    // MARK: - Types de fenêtres

    func testFloatingPanelsAreNotTargets() {
        let floating = AXNodeInfo(role: "AXWindow", subrole: "AXFloatingWindow")
        XCTAssertEqual(verdict([], window: floating, y: 60), .unsupportedWindow(subrole: "AXFloatingWindow"))
    }

    func testDialogsAndWindowsWithoutSubroleAreTargets() {
        XCTAssertEqual(verdict([], window: AXNodeInfo(role: "AXWindow", subrole: "AXDialog"), y: 60), .titlebar)
        XCTAssertEqual(verdict([], window: AXNodeInfo(role: "AXWindow"), y: 60), .titlebar)
    }
}
