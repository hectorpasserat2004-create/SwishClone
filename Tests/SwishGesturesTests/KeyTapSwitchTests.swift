import XCTest
@testable import SwishGestures

final class KeyTapSwitchTests: XCTestCase {

    func testTheKeyTapIsOnlyTouchedWhenTheTrackingStateChanges() {
        var keySwitch = KeyTapSwitch()
        // Un swipe : une centaine d'événements pendant le suivi.
        let tracking = [false, false, true] + Array(repeating: true, count: 100) + [false, false]
        let actions = tracking.compactMap { keySwitch.transition(toTracking: $0) }
        XCTAssertEqual(actions, [true, false], "un allumage au début, une extinction à la fin")
    }

    func testTheTapStartsSwitchedOffSoTheFirstIdleEventsDoNothing() {
        var keySwitch = KeyTapSwitch()
        XCTAssertNil(keySwitch.transition(toTracking: false))
        XCTAssertNil(keySwitch.transition(toTracking: false))
    }

    func testSuccessiveGesturesSwitchOnAndOffEachTime() {
        var keySwitch = KeyTapSwitch()
        let actions = [true, true, false, true, false].compactMap { keySwitch.transition(toTracking: $0) }
        XCTAssertEqual(actions, [true, false, true, false])
    }
}
