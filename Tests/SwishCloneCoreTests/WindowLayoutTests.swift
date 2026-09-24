import CoreGraphics
import XCTest
@testable import SwishCloneCore

final class ScreenGeometryTests: XCTestCase {

    /// Écran principal 1440 × 900 : barre de menus de 25 pt en haut, Dock de
    /// 70 pt en bas. En AppKit (origine en bas), la zone utile commence à
    /// y = 70.
    private let primaryHeight: CGFloat = 900

    func testVisibleFrameOfThePrimaryScreen() {
        let cocoa = CGRect(x: 0, y: 70, width: 1440, height: 805)
        XCTAssertEqual(
            ScreenGeometry.axRect(fromCocoa: cocoa, primaryScreenHeight: primaryHeight),
            CGRect(x: 0, y: 25, width: 1440, height: 805)
        )
    }

    func testScreenAboveThePrimaryHasNegativeY() {
        let cocoa = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        XCTAssertEqual(
            ScreenGeometry.axRect(fromCocoa: cocoa, primaryScreenHeight: primaryHeight),
            CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        )
    }

    func testScreenToTheRightAlignedAtTheBottom() {
        let cocoa = CGRect(x: 1440, y: -180, width: 1920, height: 1080)
        XCTAssertEqual(
            ScreenGeometry.axRect(fromCocoa: cocoa, primaryScreenHeight: primaryHeight),
            CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        )
    }

    // MARK: - L'écran de la fenêtre

    private let screens = [
        CGRect(x: 0, y: 0, width: 1440, height: 900),
        CGRect(x: 1440, y: 0, width: 1920, height: 1080),
    ]

    func testWindowBelongsToTheScreenHoldingItsCenter() {
        let window = CGRect(x: 1600, y: 100, width: 800, height: 600)
        XCTAssertEqual(ScreenGeometry.screenIndex(for: window, among: screens), 1)
    }

    func testStraddlingWindowGoesToTheScreenHoldingItsCenter() {
        let window = CGRect(x: 1000, y: 100, width: 600, height: 400) // centre en x = 1300
        XCTAssertEqual(ScreenGeometry.screenIndex(for: window, among: screens), 0)
    }

    func testCenterOffScreenFallsBackOnTheLargestOverlap() {
        // Centre sous le bas du premier écran, là où le second continue.
        let window = CGRect(x: 1300, y: 700, width: 400, height: 400) // centre (1500, 900)
        XCTAssertEqual(ScreenGeometry.screenIndex(for: window, among: screens), 1)
    }

    func testWindowEntirelyOffScreenHasNoScreen() {
        let window = CGRect(x: 5000, y: 5000, width: 100, height: 100)
        XCTAssertNil(ScreenGeometry.screenIndex(for: window, among: screens))
    }
}

final class WindowLayoutTests: XCTestCase {

    /// La zone utile de l'écran principal ci-dessus, en coordonnées AX.
    private let visible = CGRect(x: 0, y: 25, width: 1440, height: 805)

    private func frame(_ action: WindowAction, in rect: CGRect? = nil) -> CGRect? {
        WindowLayout.frame(for: action, in: rect ?? visible)
    }

    func testHalves() {
        XCTAssertEqual(frame(.leftHalf), CGRect(x: 0, y: 25, width: 720, height: 805))
        XCTAssertEqual(frame(.rightHalf), CGRect(x: 720, y: 25, width: 720, height: 805))
        XCTAssertEqual(frame(.topHalf), CGRect(x: 0, y: 25, width: 1440, height: 402.5))
        XCTAssertEqual(frame(.bottomHalf), CGRect(x: 0, y: 427.5, width: 1440, height: 402.5))
    }

    func testQuarters() {
        XCTAssertEqual(frame(.topLeftQuarter), CGRect(x: 0, y: 25, width: 720, height: 402.5))
        XCTAssertEqual(frame(.topRightQuarter), CGRect(x: 720, y: 25, width: 720, height: 402.5))
        XCTAssertEqual(frame(.bottomLeftQuarter), CGRect(x: 0, y: 427.5, width: 720, height: 402.5))
        XCTAssertEqual(frame(.bottomRightQuarter), CGRect(x: 720, y: 427.5, width: 720, height: 402.5))
    }

    func testMaximizeFillsTheUsableAreaNotTheWholeScreen() {
        XCTAssertEqual(frame(.maximize), visible)
    }

    func testCenterReducedIsSixtyPercentCentered() {
        XCTAssertEqual(frame(.centerReduced), CGRect(x: 288, y: 186, width: 864, height: 483))
    }

    func testNonGeometricActionsHaveNoFrame() {
        XCTAssertNil(frame(.minimize))
        XCTAssertNil(frame(.toggleFullScreen))
        XCTAssertNil(frame(.close))
    }

    func testSecondaryScreenAboveKeepsItsOrigin() {
        let above = CGRect(x: 0, y: -1080, width: 1920, height: 1055)
        XCTAssertEqual(frame(.leftHalf, in: above), CGRect(x: 0, y: -1080, width: 960, height: 1055))
        XCTAssertEqual(frame(.bottomRightQuarter, in: above), CGRect(x: 960, y: -552.5, width: 960, height: 527.5))
    }

    func testEveryFrameStaysInsideTheUsableArea() {
        let actions: [WindowAction] = [
            .leftHalf, .rightHalf, .topHalf, .bottomHalf,
            .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter,
            .maximize, .centerReduced,
        ]
        for action in actions {
            let result = frame(action)
            XCTAssertNotNil(result, "\(action)")
            XCTAssertTrue(visible.contains(result!), "\(action) déborde : \(result!)")
        }
    }
}
