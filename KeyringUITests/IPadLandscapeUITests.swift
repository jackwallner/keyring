import XCTest

/// Rotates an iPad to landscape and keeps a screenshot of each main screen, so
/// the wide layouts get looked at, not just the portrait ones. Skips on iPhone.
final class IPadLandscapeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    private func capture(_ name: String, arguments: [String], orientation: UIDeviceOrientation = .landscapeRight, settle: UInt32 = 6) {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        XCUIDevice.shared.orientation = orientation
        sleep(settle)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }

    func testLandscapeScreens() {
        let demo = ["-SeedDemo", "-DemoPro"]
        capture("landscape-garage", arguments: demo, settle: 10)
        for route in ["explore", "record", "history", "settings", "log", "fuel"] {
            capture("landscape-\(route)", arguments: demo + ["-ScreenshotRoute", route])
        }
        capture("landscape-paywall", arguments: ["-SeedDemo", "-PaywallSnapshot", "yearly"])
        capture("portrait-paywall", arguments: ["-SeedDemo", "-PaywallSnapshot", "yearly"], orientation: .portrait)
        capture("landscape-onboarding", arguments: ["-Onboarding"])
    }
}
