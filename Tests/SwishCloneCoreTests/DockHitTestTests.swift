import XCTest
@testable import SwishCloneCore

final class DockHitTestTests: XCTestCase {

    private let ownPID: Int32 = 100
    private let appIcon = AXNodeInfo(role: "AXDockItem", subrole: "AXApplicationDockItem")

    private let textEdit = RunningAppInfo(
        pid: 200,
        bundleURL: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
        bundleIdentifier: "com.apple.TextEdit"
    )
    private let finder = RunningAppInfo(
        pid: 300,
        bundleURL: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
        bundleIdentifier: "com.apple.finder"
    )
    private var host: RunningAppInfo {
        RunningAppInfo(pid: ownPID, bundleURL: URL(fileURLWithPath: "/Applications/bran.app"), bundleIdentifier: "com.opahventures.bran")
    }

    private func verdict(
        item: AXNodeInfo? = nil,
        isRunning: Bool = true,
        url: String?,
        bundleIdentifier: String? = nil,
        apps: [RunningAppInfo]? = nil
    ) -> DockHitTest.Verdict {
        DockHitTest.evaluate(
            item: item ?? appIcon,
            isRunning: isRunning,
            itemURL: url.map { URL(fileURLWithPath: $0) },
            itemBundleIdentifier: bundleIdentifier,
            runningApps: apps ?? [textEdit, finder, host],
            ownPID: ownPID
        )
    }

    // MARK: - Cibles

    func testRunningAppIconIsATarget() {
        XCTAssertEqual(verdict(url: "/System/Applications/TextEdit.app"), .app(textEdit))
    }

    func testTrailingSlashInTheDockURLStillMatches() {
        let url = URL(string: "file:///System/Applications/TextEdit.app/")!
        let result = DockHitTest.runningApp(forItemURL: url, bundleIdentifier: nil, among: [textEdit])
        XCTAssertEqual(result, textEdit)
    }

    func testFallsBackOnTheBundleIdentifierWhenPathsDiffer() {
        // Le Dock peut dire /Applications/…, l'app lancée /System/Applications/….
        XCTAssertEqual(
            verdict(url: "/Applications/TextEdit.app", bundleIdentifier: "com.apple.TextEdit"),
            .app(textEdit)
        )
    }

    // MARK: - Ce qui n'est pas une cible

    func testOtherDockItemsAreNotTargets() {
        for subrole in ["AXFolderDockItem", "AXTrashDockItem", "AXMinimizedWindowDockItem", "AXSeparatorDockItem"] {
            let item = AXNodeInfo(role: "AXDockItem", subrole: subrole)
            XCTAssertEqual(verdict(item: item, url: nil), .notAnAppItem(subrole: subrole), subrole)
        }
    }

    func testPinnedButClosedAppIsNotATarget() {
        XCTAssertEqual(verdict(isRunning: false, url: "/System/Applications/TextEdit.app"), .notRunning)
    }

    func testRunningFlagWithoutAMatchingAppIsNotATarget() {
        XCTAssertEqual(verdict(url: "/Applications/Inconnue.app", bundleIdentifier: "com.example.inconnue"), .notRunning)
    }

    func testOurOwnIconIsNeverATarget() {
        // bran a une icône dans le Dock et embarque cette bibliothèque.
        XCTAssertEqual(verdict(url: "/Applications/bran.app"), .ownApp)
    }

    func testFinderIsProtected() {
        XCTAssertEqual(
            verdict(url: "/System/Library/CoreServices/Finder.app"),
            .protectedApp(bundleIdentifier: "com.apple.finder")
        )
    }

    // MARK: - Jamais au hasard

    func testTwoInstancesAtTheSamePathAreAmbiguous() {
        let first = RunningAppInfo(pid: 400, bundleURL: URL(fileURLWithPath: "/Applications/Outil.app"), bundleIdentifier: "com.example.outil")
        var second = first
        second.pid = 401
        XCTAssertNil(DockHitTest.runningApp(
            forItemURL: URL(fileURLWithPath: "/Applications/Outil.app"),
            bundleIdentifier: "com.example.outil",
            among: [first, second]
        ))
    }

    func testTwoCopiesAtDifferentPathsAreDistinguishedByURL() {
        let stable = RunningAppInfo(pid: 400, bundleURL: URL(fileURLWithPath: "/Applications/Outil.app"), bundleIdentifier: "com.example.outil")
        let beta = RunningAppInfo(pid: 401, bundleURL: URL(fileURLWithPath: "/Applications/Outil Beta.app"), bundleIdentifier: "com.example.outil")
        XCTAssertEqual(
            DockHitTest.runningApp(
                forItemURL: URL(fileURLWithPath: "/Applications/Outil Beta.app"),
                bundleIdentifier: "com.example.outil",
                among: [stable, beta]
            ),
            beta
        )
    }

    func testSameIdentifierTwiceWithoutURLMatchIsAmbiguous() {
        let stable = RunningAppInfo(pid: 400, bundleURL: URL(fileURLWithPath: "/Applications/Outil.app"), bundleIdentifier: "com.example.outil")
        let beta = RunningAppInfo(pid: 401, bundleURL: URL(fileURLWithPath: "/Applications/Outil Beta.app"), bundleIdentifier: "com.example.outil")
        XCTAssertNil(DockHitTest.runningApp(
            forItemURL: URL(fileURLWithPath: "/Ailleurs/Outil.app"),
            bundleIdentifier: "com.example.outil",
            among: [stable, beta]
        ))
    }
}

final class GestureSequenceTargetTests: XCTestCase {

    func testDockIconAcceptsPinchesOnly() {
        XCTAssertTrue(GestureSequence.accepts(.pinch, on: .dockApp))
        XCTAssertFalse(GestureSequence.accepts(.swipe, on: .dockApp))
        XCTAssertTrue(GestureSequence.accepts(.swipe, on: .titlebar))
        XCTAssertTrue(GestureSequence.accepts(.pinch, on: .titlebar))
    }

    func testSamePinchMeansDifferentThingsOnDifferentTargets() {
        XCTAssertEqual(GestureSequence.resolve(pinches: [.in_], on: .titlebar), .close)
        XCTAssertEqual(GestureSequence.resolve(pinches: [.in_], on: .dockApp), .quitApp)
    }

    func testQuitIsNeverAWindowGesture() {
        let swipes: [[SwipeDirection]] = [[.left], [.right], [.up], [.down], [.up, .up], [.down, .right]]
        for steps in swipes {
            XCTAssertNotEqual(GestureSequence.resolve(swipes: steps, on: .titlebar), .quitApp)
            XCTAssertNil(GestureSequence.resolve(swipes: steps, on: .dockApp))
        }
        XCTAssertNotEqual(GestureSequence.resolve(pinches: [.out], on: .titlebar), .quitApp)
    }
}
