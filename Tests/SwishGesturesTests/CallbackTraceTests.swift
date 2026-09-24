import XCTest
@testable import SwishGestures

final class CallbackTraceTests: XCTestCase {

    func testBreakdownListsOnlyNonZeroStepsAndTheUnattributedRest() {
        var trace = CallbackTrace()
        trace.begin(kind: "scroll")
        trace.add(.decode, nanoseconds: 12_000)
        trace.add(.engine, nanoseconds: 100_000)
        trace.add(.tapEnable, nanoseconds: 40_000)

        let text = trace.breakdown(total: 200_000)
        XCTAssertTrue(text.hasPrefix("[scroll] "))
        XCTAssertTrue(text.contains("décodage 12 µs"))
        XCTAssertTrue(text.contains("machine 100 µs"))
        XCTAssertTrue(text.contains("tapEnable 40 µs"))
        XCTAssertFalse(text.contains("timer"), "une étape à zéro n'est pas listée")
        XCTAssertTrue(text.contains("reste 48 µs"), "200 − (12 + 100 + 40)")
    }

    func testNestedStepsAreShownButNotSubtractedTwice() {
        var trace = CallbackTrace()
        trace.begin(kind: "scroll")
        trace.add(.engine, nanoseconds: 100_000)
        trace.add(.hitTest, nanoseconds: 90_000) // dans `engine`
        trace.add(.deliver, nanoseconds: 5_000)  // dans `engine`

        let text = trace.breakdown(total: 110_000)
        XCTAssertTrue(text.contains("cible 90 µs (dans machine)"))
        XCTAssertTrue(text.contains("envoi 5 µs (dans machine)"))
        XCTAssertTrue(text.contains("reste 10 µs"), "110 − 100, pas 110 − 195")
    }

    func testBeginStartsFromZeroAndFinishKeepsTheWorstOfEachStep() {
        var trace = CallbackTrace()
        trace.begin(kind: "a")
        trace.add(.timer, nanoseconds: 30_000)
        trace.finish()
        trace.begin(kind: "b")
        trace.add(.timer, nanoseconds: 10_000)
        trace.finish()

        XCTAssertFalse(trace.breakdown(total: 10_000).contains("30 µs"), "le détail est celui du callback en cours")
        XCTAssertTrue(trace.summary.contains("timer 30 µs"), "le pire est retenu")
    }

    func testTapEnableCallsAreCountedAgainstCallbacks() {
        var trace = CallbackTrace()
        for _ in 0 ..< 4 {
            trace.begin(kind: "scroll")
            trace.add(.tapEnable, nanoseconds: 1_000)
            trace.finish()
        }
        XCTAssertTrue(trace.summary.hasSuffix("4 appels tapEnable pour 4 callbacks"))
    }
}
