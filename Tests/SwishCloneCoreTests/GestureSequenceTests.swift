import XCTest
@testable import SwishCloneCore

/// La table des enchaînements : sans machine, sans horloge.
final class GestureSequenceTests: XCTestCase {

    func testVerticalAlwaysCombinesAndTheLatestDirectionWins() {
        let cases: [(steps: [SwipeDirection], action: GestureAction)] = [
            ([.up, .right, .down], .bottomRightQuarter), // haut-droite, puis on descend
            ([.right, .up, .down], .bottomRightQuarter),
            ([.left, .up, .down, .up], .topLeftQuarter),
            ([.up, .up, .right], .topRightQuarter),
            ([.right, .left, .down], .bottomLeftQuarter), // inversion avant tout quart : rien à effacer
        ]
        for (steps, action) in cases {
            XCTAssertEqual(GestureSequence.resolve(swipes: steps), action, "\(steps)")
        }
    }

    // MARK: - Inversion de l'horizontale

    func testInvertingTheHorizontalOnAQuarterErasesTheVertical() {
        let cases: [(steps: [SwipeDirection], action: GestureAction)] = [
            ([.up, .right, .left], .leftHalf),            // l'exemple de référence
            ([.right, .up, .left], .leftHalf),
            ([.down, .left, .right], .rightHalf),
            ([.up, .right, .left, .left], .leftHalf),     // même direction : pas une inversion
        ]
        for (steps, action) in cases {
            XCTAssertEqual(GestureSequence.resolve(swipes: steps), action, "\(steps)")
        }
    }

    func testTheVerticalCanComeBackAfterTheErasure() {
        XCTAssertEqual(GestureSequence.resolve(swipes: [.up, .right, .left, .up]), .topLeftQuarter)
        XCTAssertEqual(GestureSequence.resolve(swipes: [.left, .down, .right, .up]), .topRightQuarter)
        XCTAssertEqual(GestureSequence.resolve(swipes: [.up, .right, .left, .down]), .bottomLeftQuarter)
    }

    func testAnOscillatingHorizontalAfterErasureKeepsFlipping() {
        XCTAssertEqual(GestureSequence.resolve(swipes: [.up, .right, .left, .right]), .rightHalf)
    }

    /// Le cas de la demande : le vertical ne réinitialise JAMAIS l'horizontale.
    func testInvertingTheVerticalNeverErasesTheHorizontal() {
        XCTAssertEqual(GestureSequence.resolve(swipes: [.left, .up, .down]), .bottomLeftQuarter)
        XCTAssertEqual(GestureSequence.resolve(swipes: [.right, .down, .up]), .topRightQuarter)
    }

    // MARK: - Double vertical : retour à la moitié

    func testTwoIdenticalConsecutiveVerticalStepsForceTheHalf() {
        let cases: [(steps: [SwipeDirection], action: GestureAction)] = [
            ([.left, .up, .down, .down], .bottomHalf),         // l'exemple de la demande
            ([.right, .up, .up], .topHalf),                    // même sur un quart construit
            ([.left, .up, .down, .down, .down], .bottomHalf),  // un triple retombe pareil
            ([.up, .right, .left, .down, .down], .bottomHalf), // après une inversion horizontale
        ]
        for (steps, action) in cases {
            XCTAssertEqual(GestureSequence.resolve(swipes: steps), action, "\(steps)")
        }
    }

    func testTheHorizontalRecombinesOverAForcedHalf() {
        XCTAssertEqual(GestureSequence.resolve(swipes: [.up, .up, .right]), .topRightQuarter) // le contre-exemple
        XCTAssertEqual(GestureSequence.resolve(swipes: [.left, .up, .up, .right]), .topRightQuarter)
        XCTAssertEqual(GestureSequence.resolve(swipes: [.left, .down, .down, .right]), .bottomRightQuarter)
        // L'inversion horizontale marche encore après un double.
        XCTAssertEqual(GestureSequence.resolve(swipes: [.left, .down, .down, .right, .left]), .leftHalf)
    }

    func testTheDoubleMustBeConsecutive() {
        // Une étape horizontale entre les deux ↑ : aucun forçage.
        XCTAssertEqual(GestureSequence.resolve(swipes: [.up, .left, .up]), .topLeftQuarter)
        XCTAssertEqual(GestureSequence.resolve(swipes: [.up, .right, .up]), .topRightQuarter)
    }

    func testDoubleHorizontalHasNoSpecialMeaning() {
        XCTAssertEqual(GestureSequence.resolve(swipes: [.up, .right, .right]), .topRightQuarter)
        XCTAssertEqual(GestureSequence.resolve(swipes: [.up, .left, .left]), .topLeftQuarter)
    }

    /// Une fois combiné, le dernier de chaque axe l'emporte, y compris sur
    /// une moitié forcée par un double.
    func testChangingYourMindAfterAForcedHalfLetsTheLatestWin() {
        XCTAssertEqual(GestureSequence.resolve(swipes: [.left, .up, .up, .down]), .bottomHalf)
    }

    func testTwoStepQuartersAreUnchanged() {
        XCTAssertEqual(GestureSequence.resolve(swipes: [.down, .right]), .bottomRightQuarter)
        XCTAssertEqual(GestureSequence.resolve(swipes: [.right, .down]), .bottomRightQuarter)
        XCTAssertEqual(GestureSequence.resolve(swipes: [.left, .up]), .topLeftQuarter)
    }

    func testDoubleVerticalStillMeansHalves() {
        XCTAssertEqual(GestureSequence.resolve(swipes: [.up, .up]), .topHalf)
        XCTAssertEqual(GestureSequence.resolve(swipes: [.down, .down]), .bottomHalf)
    }

    func testChangingYourMindOnASingleAxisStaysUnrecognized() {
        let cases: [[SwipeDirection]] = [
            [.up, .down], [.down, .up], [.left, .right], [.right, .left],
            [.left, .left], [.up, .up, .up], [.up, .down, .up],
        ]
        for steps in cases {
            XCTAssertNil(GestureSequence.resolve(swipes: steps), "\(steps)")
        }
    }

    func testLongChainsDoNothingOnADockIcon() {
        XCTAssertNil(GestureSequence.resolve(swipes: [.up, .right, .down], on: .dockApp))
    }
}
