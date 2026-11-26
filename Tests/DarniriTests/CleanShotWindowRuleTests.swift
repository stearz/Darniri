import AppKit
@testable import Darniri
import XCTest

final class CleanShotWindowRuleTests: XCTestCase {
    @MainActor
    func testCaptureDialogsAreIgnoredEvenWithExplicitUserLayoutAndFullscreenFallback() {
        let engine = WindowRuleEngine()
        engine.rebuild(rules: [AppRule(bundleId: WindowRuleEngine.cleanShotBundleId, layout: .tile)])

        for subrole in ["AXDialog", "AXSystemDialog"] {
            for level: Int32 in [-2_147_483_600, 2_147_483_628] {
                let decision = engine.decision(
                    for: facts(subrole: subrole, level: level), token: nil, appFullscreen: true
                )
                XCTAssertEqual(decision.disposition, .unmanaged)
                XCTAssertEqual(decision.source, .builtInRule("cleanShotCaptureOverlay"))
                XCTAssertNil(decision.trackedMode)
            }
        }
    }

    @MainActor
    func testNormalCleanShotWindowsAndOtherAppsRemainManaged() {
        let engine = WindowRuleEngine()
        XCTAssertEqual(engine.decision(
            for: facts(subrole: "AXStandardWindow", level: 0), token: nil, appFullscreen: false
        ).disposition, .managed)
        XCTAssertEqual(engine.decision(
            for: facts(subrole: "AXDialog", level: 0), token: nil, appFullscreen: false
        ).disposition, .floating)
        XCTAssertEqual(engine.decision(
            for: facts(subrole: "AXDialog", level: 100, bundleId: "com.example.other"),
            token: nil, appFullscreen: false
        ).source, .heuristic)
    }

    @MainActor
    func testRecordingOverlayKeepsExistingFloatingRule() {
        let decision = WindowRuleEngine().decision(
            for: facts(subrole: "AXStandardWindow", level: 103), token: nil, appFullscreen: false
        )
        XCTAssertEqual(decision.disposition, .floating)
        XCTAssertEqual(decision.source, .builtInRule("cleanShotRecordingOverlay"))
    }

    private func facts(
        subrole: String,
        level: Int32,
        bundleId: String = "pl.maketheweb.cleanshotx"
    ) -> WindowRuleFacts {
        WindowRuleFacts(
            appName: "CleanShot X",
            ax: AXWindowFacts(
                role: "AXWindow", subrole: subrole, title: nil,
                hasCloseButton: true, hasFullscreenButton: true, fullscreenButtonEnabled: true,
                hasZoomButton: true, hasMinimizeButton: true,
                appPolicy: .regular, bundleId: bundleId, attributeFetchSucceeded: true
            ),
            sizeConstraints: nil,
            windowServer: WindowServerInfo(
                id: 1, pid: 1, level: level,
                frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                tags: 0, attributes: 0, parentId: 0, title: nil
            )
        )
    }
}
