import XCTest

/// The release-gate journeys: what a person does in the first minutes, run on
/// iPhone, iPhone Duo and iPad (portrait and landscape) by `qa-gate`. Every
/// element is found by accessibility identifier, never by position.
@MainActor
final class ReleaseJourneysUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // The reminder permission appears right after the first vehicle is saved.
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for label in ["Allow", "OK", "Don\u{2019}t Allow", "Don't Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    // MARK: - Helpers

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func button(_ id: String) -> XCUIElement {
        app.buttons.matching(identifier: id).firstMatch
    }

    /// Any element whose label mentions `text`.
    private func labelled(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Scrolls the list or form that holds `id` until it can be tapped.
    private func reveal(_ id: String) {
        let target = element(id)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Missing \(id)")
        var swipes = 0
        while !target.isHittable, swipes < 8 {
            let holders = [app.collectionViews, app.tables, app.scrollViews]
            guard let holder = holders.map({ $0.containing(.any, identifier: id).firstMatch }).first(where: \.exists) else { break }
            QA.swipe(holder, .up)
            swipes += 1
        }
    }

    private func tap(_ id: String, timeout: TimeInterval = 10) {
        let target = button(id)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "Missing button \(id)")
        if !target.isHittable { reveal(id) }
        target.tap()
    }

    private func type(_ text: String, into id: String) {
        let field = app.textFields.matching(identifier: id).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Missing field \(id)")
        if !field.isHittable { reveal(id) }
        field.tap()
        field.typeText(text)
    }

    private func openTab(_ id: String) {
        let tab = button(id)
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Missing tab \(id)")
        tab.tap()
    }

    private func checkpoint(_ name: String, journey: String = #function) {
        QA.checkpoint(app, name, journey: journey)
    }

    /// Onboarding pages in order; each is checkpointed once it is on screen.
    private func walkOnboarding(journey: String = #function) {
        let next = button("onboarding.continue")
        XCTAssertTrue(next.waitForExistence(timeout: 15), "Onboarding did not appear")
        checkpoint("onboarding-welcome", journey: journey)
        next.tap()

        XCTAssertTrue(button("onboarding.kind.car").waitForExistence(timeout: 5))
        button("onboarding.kind.car").tap()
        checkpoint("onboarding-garage-picked", journey: journey)
        next.tap()

        // The schedule page has no control of its own; wait for the page change.
        XCTAssertTrue(labelled("It knows").waitForExistence(timeout: 5), "No schedule page")
        checkpoint("onboarding-schedule", journey: journey)
        next.tap()

        type("Sam\n", into: "onboarding.name")
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        checkpoint("onboarding-family", journey: journey)
        next.tap()

        // The last page sells Pro; the journey takes the free way in.
        XCTAssertTrue(button("onboarding.getStarted").waitForExistence(timeout: 5))
        checkpoint("onboarding-pro", journey: journey)
        button("onboarding.getStarted").tap()
    }

    // MARK: - Journeys

    func testFirstRunOnboarding() {
        QA.launch(app, arguments: ["-ResetData", "-NoCloudKit"])
        walkOnboarding()

        // The garage opens straight into adding the first vehicle.
        XCTAssertTrue(button("vehicle.continue").waitForExistence(timeout: 15), "The first vehicle form did not open")
        checkpoint("add-first-vehicle")
        tap("vehicle.back")
        tap("vehicle.cancel")

        XCTAssertTrue(button("garage.add").waitForExistence(timeout: 10), "No garage after onboarding")
        checkpoint("garage-after-onboarding")
    }

    func testCoreLoopLogRepairSurvivesRelaunch() {
        QA.launch(app, arguments: ["-ResetData", "-NoCloudKit"])
        walkOnboarding()

        // Add the vehicle the person picked.
        XCTAssertTrue(button("vehicle.continue").waitForExistence(timeout: 15), "The first vehicle form did not open")
        type("Toyota", into: "add.make")
        type("Tacoma", into: "add.model")
        type("QA Truck\n", into: "add.nickname")
        checkpoint("vehicle-details-filled")
        tap("vehicle.continue")
        tap("vehicle.finish")

        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "QA Truck")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "The new vehicle is not in the garage")
        checkpoint("garage-with-vehicle")

        // Log a repair with a typed title.
        card.tap()
        tap("vehicle.log")
        let repair = app.segmentedControls.buttons["Repair"].firstMatch
        XCTAssertTrue(repair.waitForExistence(timeout: 10), "No Repair choice in the log form")
        repair.tap()
        type("Alternator swap", into: "log.repairTitle")
        checkpoint("log-repair-filled")
        tap("log.save")

        XCTAssertTrue(labelled("Alternator swap").waitForExistence(timeout: 10), "The repair is not on the vehicle after saving")
        checkpoint("vehicle-after-log")

        openTab("tab.history")
        XCTAssertTrue(labelled("Alternator swap").waitForExistence(timeout: 10), "The repair is not in History")
        checkpoint("history-with-repair")

        // The log must outlive the app. The reset flag goes first, or the relaunch would wipe it.
        app.launchArguments.removeAll { $0 == "-ResetData" }
        QA.relaunch(app)
        openTab("tab.history")
        XCTAssertTrue(labelled("Alternator swap").waitForExistence(timeout: 15), "The repair is gone after relaunch")
        checkpoint("history-after-relaunch")
    }

    func testMainTabs() {
        QA.launch(app, arguments: ["-SeedDemo", "-NoCloudKit"])
        XCTAssertTrue(button("garage.add").waitForExistence(timeout: 20), "No garage")
        checkpoint("garage")

        openTab("tab.history")
        XCTAssertTrue(labelled("Tacoma").waitForExistence(timeout: 10), "History shows no demo entries")
        checkpoint("history")

        openTab("tab.settings")
        XCTAssertTrue(button("settings.pro").waitForExistence(timeout: 10), "Settings did not open")
        checkpoint("settings")

        openTab("tab.garage")
        XCTAssertTrue(button("garage.add").waitForExistence(timeout: 10))
    }

    func testPaywallOpensAndCloses() {
        QA.launch(app, arguments: ["-SeedDemo", "-NoCloudKit"])
        XCTAssertTrue(button("garage.add").waitForExistence(timeout: 20), "No garage")

        openTab("tab.settings")
        tap("settings.pro")
        XCTAssertTrue(button("paywall.close").waitForExistence(timeout: 10), "The paywall did not open")
        checkpoint("paywall")

        button("paywall.close").tap()
        XCTAssertTrue(button("settings.pro").waitForExistence(timeout: 10), "Settings did not return after closing the paywall")
        checkpoint("settings-after-paywall")
    }
}
