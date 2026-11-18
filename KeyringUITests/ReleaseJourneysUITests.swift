import XCTest

/// Release gate journeys (see ~/ios/qa/README.md). They assert reachability
/// and the core loop's outcome; `QA.checkpoint` judges every screen.
///
/// Fixtures: `-SeedDemo` is the in-memory demo garage (five vehicles, free
/// tier), `-Onboarding` is a fresh install on an empty in-memory store. The
/// core loop uses neither so the Core Data file really persists across
/// `QA.relaunch`; `-NoCloudKit` keeps it off the network. StoreKit comes from
/// the local Keyring.storekit catalog, never a RevenueCat `appl_` key.
@MainActor
final class ReleaseJourneysUITests: XCTestCase {
    private var app: XCUIApplication!

    private let demo = ["-SeedDemo", "-NoCloudKit"]
    private let nickname = "QA Truck"

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Journeys

    /// A real first install: onboarding pages, the free way in, the add flow
    /// the planned truck opens, and the garage with the new vehicle.
    func testFirstRunOnboardingToGarage() {
        QA.launch(app, arguments: ["-Onboarding", "-NoCloudKit"])
        onboardingNext()
        QA.checkpoint(app, "onboarding-fleet")
        let truck = app.buttons["onboarding.kind.truck"]
        XCTAssertTrue(truck.waitForExistence(timeout: 10), "Onboarding should offer the vehicle kinds")
        truck.tap()
        onboardingNext()
        QA.checkpoint(app, "onboarding-schedule")
        onboardingNext()
        QA.checkpoint(app, "onboarding-family")
        onboardingNext()

        let notNow = app.buttons["onboarding.getStarted"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 20), "The last onboarding page should offer Not now")
        QA.checkpoint(app, "onboarding-offer")
        notNow.tap()

        XCTAssertTrue(app.textFields["Make"].waitForExistence(timeout: 20), "Not now should open the add flow for the planned truck")
        QA.checkpoint(app, "add-details")
        addDetails(make: "Toyota", nickname: nickname)
        finishAdding()
        XCTAssertTrue(garageCard(nickname).waitForExistence(timeout: 20), "The garage should list the new vehicle")
        QA.checkpoint(app, "garage-first-vehicle")
    }

    /// Core loop: add a vehicle, log a service on it, and still have both
    /// after the app is killed and reopened on the same install.
    func testCoreLoopVehicleAndServiceSurviveRelaunch() {
        QA.launch(app, arguments: ["-NoCloudKit"])
        addQAVehicleIfNeeded()
        QA.checkpoint(app, "garage")

        garageCard(nickname).tap()
        let log = app.buttons["vehicle.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 20), "The vehicle page should offer Log service")
        QA.checkpoint(app, "vehicle")
        log.tap()

        let jobs = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Oil and filter"))
        XCTAssertTrue(jobs.firstMatch.waitForExistence(timeout: 20), "Log service should list the oil change")
        QA.checkpoint(app, "log-service")
        // The unfolded Duo keeps the vehicle page's own oil change row beside the sheet, under its dimming.
        press(reachable(jobs), "The oil change row")
        let save = app.buttons["log.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "Log service should offer Save")
        press(save, "Save")
        XCTAssertTrue(app.buttons["vehicle.log"].waitForExistence(timeout: 20), "Saving should return to the vehicle page")
        QA.checkpoint(app, "vehicle-after-log")

        QA.relaunch(app)
        XCTAssertTrue(garageCard(nickname).waitForExistence(timeout: 30), "The vehicle should survive a relaunch")
        QA.checkpoint(app, "garage-after-relaunch")

        openTab("History")
        let entry = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Oil and filter")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 20), "The logged service should still be in History after a relaunch")
        QA.checkpoint(app, "history-after-relaunch")
    }

    func testInterruptionDuringLogService() {
        QA.launch(app, arguments: demo + ["-ScreenshotRoute", "log"])
        let save = app.buttons["log.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 30), "Log service should open")
        QA.checkpoint(app, "log-before-interrupt")

        QA.interrupt(app)
        XCTAssertEqual(app.state, .runningForeground, "The app should come back to the foreground")
        XCTAssertTrue(save.waitForExistence(timeout: 20), "The open form should survive the interruption")
        QA.checkpoint(app, "log-after-interrupt")

        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["garage.add"].waitForExistence(timeout: 20), "Cancel should return to the garage")
        QA.checkpoint(app, "garage-after-cancel")
    }

    func testReturnVisitAcrossTabs() {
        QA.launch(app, arguments: demo)
        XCTAssertTrue(garageCard("The Tacoma").waitForExistence(timeout: 30), "The garage should open on the demo vehicles")
        QA.checkpoint(app, "garage")

        QA.relaunch(app)
        XCTAssertTrue(garageCard("The Tacoma").waitForExistence(timeout: 30), "The garage should reopen without onboarding")
        QA.checkpoint(app, "garage-after-relaunch")

        openTab("History")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 20), "History should open")
        QA.checkpoint(app, "history")
        openTab("Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 20), "Settings should open")
        QA.checkpoint(app, "settings")
        openTab("Garage")
        XCTAssertTrue(garageCard("The Tacoma").waitForExistence(timeout: 20), "Garage should open again")
        QA.checkpoint(app, "garage-return")
    }

    /// Settings: the owner name saves and is still there after a relaunch.
    func testSettingsNameSurvivesRelaunch() {
        QA.launch(app, arguments: demo + ["-ScreenshotRoute", "settings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 30), "Settings should open")
        QA.checkpoint(app, "settings")

        let name = "QA Tester"
        let field = app.textFields["settings.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Settings should offer the name field")
        QA.type(name, into: field, in: app)
        let saveName = app.buttons["settings.save"]
        XCTAssertTrue(saveName.waitForExistence(timeout: 5), "Save should appear while the name is edited")
        QA.checkpoint(app, "settings-editing-name")
        saveName.tap()
        XCTAssertTrue(saveName.waitForNonExistence(timeout: 10), "Save should go once the name is saved")
        QA.checkpoint(app, "settings-name-saved")

        QA.relaunch(app)
        openTab("Settings")
        let again = app.textFields["settings.name"]
        XCTAssertTrue(again.waitForExistence(timeout: 30), "Settings should reopen")
        XCTAssertEqual(again.value as? String, name, "The saved name should survive a relaunch")
        QA.checkpoint(app, "settings-after-relaunch")
    }

    /// Upgrade entry from Settings: Pro row opens the paywall, Close returns.
    func testPaywallFromSettingsShownAndDismissed() {
        QA.launch(app, arguments: demo + ["-ScreenshotRoute", "settings"])
        let pro = app.buttons["settings.pro"]
        XCTAssertTrue(pro.waitForExistence(timeout: 30), "A free user should see the Pro row in Settings")
        QA.checkpoint(app, "settings-free")
        pro.tap()
        expectPaywallThenClose(name: "paywall-settings")
        XCTAssertTrue(pro.waitForExistence(timeout: 10), "Closing the paywall should return to Settings")
        QA.checkpoint(app, "settings-after-paywall")
    }

    /// Upgrade entry from the garage: a third vehicle is Pro, so Add opens the paywall.
    func testPaywallFromAddingPastFreeLimit() {
        QA.launch(app, arguments: demo)
        let add = app.buttons["garage.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 30), "The garage should offer Add a vehicle")
        QA.checkpoint(app, "garage-over-limit")
        add.tap()
        expectPaywallThenClose(name: "paywall-vehicle-limit")
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Closing the paywall should return to the garage")
        QA.checkpoint(app, "garage-after-paywall")
    }

    // MARK: - Helpers

    private func openTab(_ title: String) {
        QA.openTab(app, title)
    }

    private func garageCard(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    /// Taps once the element can take it: a sheet or relaunch still settling answers a query late.
    private func press(_ element: XCUIElement, _ what: String) {
        let ready = NSPredicate(format: "exists == true AND hittable == true")
        let wait = XCTNSPredicateExpectation(predicate: ready, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 20), .completed, "\(what) should be tappable")
        element.tap()
    }

    /// The match a user could tap, once one is: a sheet can cover a twin of its row.
    private func reachable(_ query: XCUIElementQuery) -> XCUIElement {
        let deadline = Date().addingTimeInterval(20)
        repeat {
            if let hit = query.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) { return hit }
            usleep(300_000)
        } while Date() < deadline
        return query.firstMatch
    }

    private func onboardingNext() {
        let next = app.buttons["onboarding.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 20), "Onboarding should offer Continue")
        next.tap()
    }

    private func expectPaywallThenClose(name: String, journey: String = #function) {
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), "The paywall should open with a Close button")
        QA.checkpoint(app, name, paywall: true, journey: journey)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10), "The paywall should dismiss")
    }

    /// The add flow's details step: make and nickname, then on to the last-done step.
    private func addDetails(make: String, nickname: String) {
        let makeField = app.textFields["Make"]
        XCTAssertTrue(makeField.waitForExistence(timeout: 20), "The details step should offer Make")
        QA.type(make, into: makeField, in: app)
        // Return walks the fields (Make, Model, Trim, Nickname) and scrolls each into view.
        for _ in 0..<3 { app.typeText("\n") }
        app.typeText(nickname)
        app.typeText("\n")
        let next = app.buttons["vehicle.continue"]
        scrollTo(next)
        XCTAssertTrue(next.waitForExistence(timeout: 10), "The details step should offer Continue")
        next.tap()
    }

    /// The last-done step, then the reminders prompt that follows the first vehicle.
    private func finishAdding() {
        let finish = app.buttons["vehicle.finish"]
        scrollTo(finish)
        XCTAssertTrue(finish.waitForExistence(timeout: 20), "The last step should offer Add to garage")
        QA.checkpoint(app, "add-last-done")
        finish.tap()
        let prompt = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don")).firstMatch
        if prompt.waitForExistence(timeout: 4) { prompt.tap() }
    }

    /// Walks a fresh install through onboarding, or adds from the garage on a
    /// reused one. Nothing to do when the vehicle is already there.
    private func addQAVehicleIfNeeded() {
        let notNow = app.buttons["onboarding.getStarted"]
        let add = app.buttons["garage.add"]
        let continueButton = app.buttons["onboarding.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 30) || add.waitForExistence(timeout: 5), "The app should open on onboarding or the garage")

        if continueButton.exists {
            onboardingNext()
            app.buttons["onboarding.kind.truck"].tap()
            for _ in 0..<3 { onboardingNext() }
            XCTAssertTrue(notNow.waitForExistence(timeout: 20), "The last onboarding page should offer Not now")
            notNow.tap()
        } else if !garageCard(nickname).waitForExistence(timeout: 3) {
            add.tap()
            XCTAssertFalse(app.buttons["Close"].waitForExistence(timeout: 3), "The install already holds the free limit of vehicles")
            let truck = app.buttons["kind.truck"]
            XCTAssertTrue(truck.waitForExistence(timeout: 10), "Add a vehicle should list the kinds")
            truck.tap()
        } else {
            return
        }
        addDetails(make: "Toyota", nickname: nickname)
        finishAdding()
        XCTAssertTrue(garageCard(nickname).waitForExistence(timeout: 20), "The garage should list the new vehicle")
    }

    private func scrollTo(_ element: XCUIElement) {
        QA.reveal(element, in: app, swipes: 6)
    }
}
