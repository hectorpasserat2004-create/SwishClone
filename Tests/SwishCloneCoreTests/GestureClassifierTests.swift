import XCTest
@testable import SwishCloneCore

final class GestureClassifierTests: XCTestCase {

    func testSwipeRight() {
        let gesture = GestureClassifier.classify(
            startPositions: [FingerPosition(x: 0.2, y: 0.5)],
            endPositions: [FingerPosition(x: 0.8, y: 0.5)],
            fingerCount: 3
        )
        XCTAssertEqual(gesture, .swipe(direction: .right, fingers: 3))
    }

    func testSwipeLeft() {
        let gesture = GestureClassifier.classify(
            startPositions: [FingerPosition(x: 0.8, y: 0.5)],
            endPositions: [FingerPosition(x: 0.2, y: 0.5)],
            fingerCount: 3
        )
        XCTAssertEqual(gesture, .swipe(direction: .left, fingers: 3))
    }

    func testSwipeUp() {
        let gesture = GestureClassifier.classify(
            startPositions: [FingerPosition(x: 0.5, y: 0.2)],
            endPositions: [FingerPosition(x: 0.5, y: 0.8)],
            fingerCount: 4
        )
        XCTAssertEqual(gesture, .swipe(direction: .up, fingers: 4))
    }

    func testSwipeDown() {
        let gesture = GestureClassifier.classify(
            startPositions: [FingerPosition(x: 0.5, y: 0.8)],
            endPositions: [FingerPosition(x: 0.5, y: 0.2)],
            fingerCount: 4
        )
        XCTAssertEqual(gesture, .swipe(direction: .down, fingers: 4))
    }

    func testTapWhenMovementBelowThreshold() {
        let gesture = GestureClassifier.classify(
            startPositions: [FingerPosition(x: 0.5, y: 0.5)],
            endPositions: [FingerPosition(x: 0.51, y: 0.49)],
            fingerCount: 2
        )
        XCTAssertEqual(gesture, .tap(fingers: 2))
    }

    func testTapWithNoMovement() {
        let gesture = GestureClassifier.classify(
            startPositions: [FingerPosition(x: 0.3, y: 0.3)],
            endPositions: [FingerPosition(x: 0.3, y: 0.3)],
            fingerCount: 1
        )
        XCTAssertEqual(gesture, .tap(fingers: 1))
    }

    func testPinchOut() {
        // Écartement net (0.2 -> 0.32, +60% relatif : pinchScore = 4.0)
        // avec un peu de dérive du centre (0.02, swipeScore = 0.4 < 1) —
        // comme une vraie main pas parfaitement immobile. Le signal pinch
        // domine largement : pinch out.
        let gesture = GestureClassifier.classify(
            startPositions: [
                FingerPosition(x: 0.3, y: 0.5),
                FingerPosition(x: 0.5, y: 0.5)
            ],
            endPositions: [
                FingerPosition(x: 0.26, y: 0.5),
                FingerPosition(x: 0.58, y: 0.5)
            ],
            fingerCount: 2
        )
        XCTAssertEqual(gesture, .pinch(direction: .out, fingers: 2))
    }

    func testPinchIn() {
        // Même idée en sens inverse : écartement 0.32 -> 0.2 (-37.5%
        // relatif, pinchScore = 2.5) avec la même petite dérive de centre
        // (swipeScore = 0.4 < 1). Le pinch domine.
        let gesture = GestureClassifier.classify(
            startPositions: [
                FingerPosition(x: 0.26, y: 0.5),
                FingerPosition(x: 0.58, y: 0.5)
            ],
            endPositions: [
                FingerPosition(x: 0.3, y: 0.5),
                FingerPosition(x: 0.5, y: 0.5)
            ],
            fingerCount: 2
        )
        XCTAssertEqual(gesture, .pinch(direction: .in_, fingers: 2))
    }

    func testSwipeWithSlightSpreadDriftIsNotConfusedWithPinch() {
        // Le cas réel qui posait problème : un vrai swipe fait toujours un
        // peu varier l'écartement des doigts. Ici l'écartement passe de
        // 0.2 à 0.24 (+20% relatif, donc pinchScore = 1.33 — au-dessus du
        // seuil pinch pris isolément !) pendant un swipe net de 0.5
        // (swipeScore = 10.0). Le swipe doit rester dominant.
        let gesture = GestureClassifier.classify(
            startPositions: [
                FingerPosition(x: 0.1, y: 0.5),
                FingerPosition(x: 0.3, y: 0.5)
            ],
            endPositions: [
                FingerPosition(x: 0.58, y: 0.5),
                FingerPosition(x: 0.82, y: 0.5)
            ],
            fingerCount: 2
        )
        XCTAssertEqual(gesture, .swipe(direction: .right, fingers: 2))
    }
}
