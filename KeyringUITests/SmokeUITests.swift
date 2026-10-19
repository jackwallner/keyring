import XCTest

/// Walks every main screen on the demo garage so a broken flow or a missing
/// link shows up before TestFlight. Runs on the in-memory `-SeedDemo` store.
final class SmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ route: String? = nil) {
        app.launchArguments = ["-SeedDemo", "-DemoPro"]
        if let route { app.launchArguments += ["-ScreenshotRoute", route] }
        app.launch()
    }

    private func tapButton(_ prefix: String, timeout: TimeInterval = 5) {
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        scrollTo(button)
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "No button starting with \(prefix)")
        button.tap()
    }

    private func scrollTo(_ element: XCUIElement) {
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
    }

    private func expectTitle(_ title: String, timeout: TimeInterval = 5) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: timeout), "Expected screen \(title)")
    }

    private func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Taps a link row and checks Safari came forward, then returns.
    private func expectOpensSafari(_ element: XCUIElement) {
        scrollTo(element)
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing link \(element)")
        element.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10), "Safari did not open")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    func testExploreScreensOpen() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 10)
        let tiles: [(String, String)] = [
            ("What it's worth", "What it's worth"),
            ("Parts and tools", "Parts and tools"),
            ("Upgrades", "Upgrades"),
            ("Clubs", "Clubs and forums"),
            ("Service nearby", "Service nearby"),
            ("Insights", "Insights"),
        ]
        for (tile, title) in tiles {
            tapButton(tile)
            expectTitle(title)
            goBack()
            expectTitle("The Tacoma")
        }
    }

    func testValueSourcesListed() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 10)
        tapButton("What it's worth")
        for source in ["Kelley Blue Book", "Edmunds", "eBay sold listings"] {
            expectOpensSafari(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", source)).firstMatch)
        }
    }

    func testClubsAndGearHaveLinks() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 10)
        tapButton("Clubs")
        expectOpensSafari(button(containing: "Tacoma World"))
        expectOpensSafari(button(containing: "r/Tacoma"))
        goBack()
        tapButton("Parts and tools")
        expectOpensSafari(button(containing: "Toyota Tacoma"))
        goBack()
        tapButton("Upgrades")
        expectTitle("Upgrades")
        for header in ["Performance", "Handling"] {
            XCTAssertTrue(app.staticTexts[header].waitForExistence(timeout: 5), "No \(header) section")
        }
        expectOpensSafari(button(containing: "Leveling kit"))
        expectOpensSafari(button(containing: "Clay bar kit"))
    }

    func testServiceNearbyLinks() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 10)
        tapButton("Service nearby")
        expectTitle("Service nearby")
        expectOpensSafari(button(containing: "YourMechanic"))
        let mobile = button(containing: "Mobile car detailing")
        scrollTo(mobile)
        XCTAssertTrue(mobile.waitForExistence(timeout: 5))
        mobile.tap()
        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        XCTAssertTrue(maps.wait(for: .runningForeground, timeout: 10), "Maps did not open")
        app.activate()
    }

    func testRecallsOpen() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 10)
        tapButton("4 safety recalls")
        expectTitle("Safety recalls", timeout: 10)
        tapButton("See which are still open")
        XCTAssertTrue(app.navigationBars["Check the VIN"].waitForExistence(timeout: 5), "VIN check sheet did not open")
        let done = app.navigationBars.buttons["Cancel"]
        XCTAssertTrue(done.exists)
        done.tap()
        tapButton("Fuel System")
        let nhtsa = app.links["Read it at NHTSA"].firstMatch
        XCTAssertTrue(nhtsa.waitForExistence(timeout: 5))
        expectOpensSafari(nhtsa)
    }

    func testLogServiceSaves() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 10)
        tapButton("Log service")
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        tapButton("Oil and filter")
        app.navigationBars.buttons["Save"].tap()
        expectTitle("The Tacoma")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Oil and filter, Due in 7 weeks")).firstMatch.exists)
    }

    func testFillUpSaves() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 10)
        tapButton("Fill-up")
        expectTitle("Fill-up")
        let fields = app.textFields
        XCTAssertGreaterThan(fields.count, 0)
        fields.element(boundBy: 0).tap()
        fields.element(boundBy: 0).typeText("15.2")
        app.navigationBars.buttons["Save"].tap()
        if app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save at")).firstMatch.waitForExistence(timeout: 2) {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save at")).firstMatch.tap()
        }
        expectTitle("The Tacoma")
    }

    func testCancelCleanFormClosesSilently() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 10)
        tapButton("Fill-up")
        expectTitle("Fill-up")
        app.navigationBars.buttons["Cancel"].tap()
        expectTitle("The Tacoma")
    }

    func testScheduleAndJobDetail() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 10)
        tapButton("Brake inspection")
        expectTitle("Brake inspection")
        app.navigationBars.buttons["Edit"].tap()
        expectTitle("Edit job")
        app.navigationBars.buttons["Cancel"].tap()
        expectTitle("Brake inspection")
        goBack()
        let all = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "All [0-9]+ jobs")).firstMatch
        scrollTo(all)
        XCTAssertTrue(all.waitForExistence(timeout: 5), "No All jobs button")
        all.tap()
        expectTitle("Schedule")
    }

    func testOdometerUpdate() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 10)
        tapButton("Odometer")
        XCTAssertTrue(app.buttons["Save"].firstMatch.waitForExistence(timeout: 5) || app.navigationBars.buttons["Save"].exists)
    }

    func testHistorySearchAndEdit() {
        launch("history")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 10))
        let first = button(containing: "Fill-up, $")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.swipeLeft()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Delete"].exists)
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars.buttons["Cancel"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    }

    func testSettingsRowsPresent() {
        launch("settings")
        expectTitle("Settings", timeout: 10)
        for label in ["Family sharing", "Export everything (CSV)", "Import from another app", "Rate the app", "Send feedback", "Tell a friend", "Help", "Privacy Policy", "Terms of Use"] {
            let element = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            scrollTo(element)
            XCTAssertTrue(element.exists, "Missing \(label)")
        }
        expectOpensSafari(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Privacy Policy")).firstMatch)
        expectOpensSafari(app.buttons["Help"].firstMatch)
    }

    func testAddVehicleOpens() {
        launch("add")
        XCTAssertTrue(app.navigationBars.buttons["Cancel"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Cancel"].tap()
    }

    func testFamilyOpens() {
        launch("family")
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
    }

    func testWhiteColorSaves() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 10)
        app.navigationBars.buttons["Edit"].tap()
        let white = app.buttons["White"]
        let first = app.buttons["Racing green"]
        scrollTo(first)
        let row = app.scrollViews.containing(.button, identifier: "Racing green").firstMatch
        for _ in 0..<3 where !white.isHittable { row.swipeLeft() }
        XCTAssertTrue(white.waitForExistence(timeout: 5), "No White swatch")
        white.tap()
        XCTAssertTrue(white.isSelected)
        attach("white-swatch")
        tapButton("Save")
        expectTitle("The Tacoma")
        XCTAssertTrue(app.navigationBars.buttons["Edit"].waitForExistence(timeout: 5))
        attach("white-detail")
        goBack()
        attach("white-garage")
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testGarageListsDemoVehicles() {
        launch()
        for name in ["The Tacoma", "Sam's RAV4", "Rebel", "Lake boat", "N734CP"] {
            let element = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
            scrollTo(element)
            XCTAssertTrue(element.exists, "Missing \(name)")
        }
    }
}
