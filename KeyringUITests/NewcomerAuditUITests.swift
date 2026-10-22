import XCTest

/// Persona audit: a first-time user on a fresh install (`-EmptyLog`, no demo
/// data). Every step attaches a screenshot so the walk can be reviewed by eye.
final class NewcomerAuditUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-EmptyLog"]
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func note(_ text: String) {
        print("AUDIT-NOTE: \(text)")
    }

    private func tapContinue(times: Int) {
        for _ in 0..<times {
            let next = app.buttons["onboarding.continue"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
            sleep(1)
        }
    }

    func testOnboardingPages() {
        app.launch()
        let next = app.buttons["onboarding.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 15), "No onboarding on a fresh install")
        shot("01-welcome")
        note("welcome continue frame \(next.frame)")
        tapContinue(times: 1)
        shot("02-schedule")
        tapContinue(times: 1)
        shot("03-family")
        tapContinue(times: 1)
        shot("04-trial")
        let started = app.buttons["onboarding.getStarted"]
        note("getStarted exists \(started.exists) hittable \(started.isHittable) frame \(started.frame)")
        let restore = app.buttons["Restore"]
        note("restore exists \(restore.exists) hittable \(restore.isHittable) frame \(restore.frame)")
        let terms = app.links["Terms"]
        note("terms exists \(terms.exists) frame \(terms.frame)")
    }

    func testTrialButtonOnSimulator() {
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 15))
        tapContinue(times: 4)
        sleep(2)
        shot("05-after-trial-tap")
    }

    func testJoinFromWelcome() {
        app.launch()
        let join = app.buttons["onboarding.join"]
        XCTAssertTrue(join.waitForExistence(timeout: 15))
        note("join frame \(join.frame)")
        join.tap()
        sleep(1)
        shot("06-join-sheet")
    }

    func testFirstVehicleAndFirstLog() {
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 15))
        tapContinue(times: 3)
        let started = app.buttons["onboarding.getStarted"]
        XCTAssertTrue(started.waitForExistence(timeout: 5))
        started.tap()
        // The garage should open straight into adding a vehicle.
        let car = app.buttons["kind.car"]
        XCTAssertTrue(car.waitForExistence(timeout: 10), "Add flow did not open after Get Started")
        shot("10-kind-picker")
        car.tap()
        sleep(1)
        shot("11-details-empty")
        let make = app.textFields["Make"]
        XCTAssertTrue(make.waitForExistence(timeout: 5))
        let cont = app.buttons["vehicle.continue"]
        note("continue enabled before typing: \(cont.isEnabled)")
        make.tap()
        make.typeText("Toyota")
        sleep(1)
        shot("12-details-make-typed")
        let model = app.textFields["Model"]
        model.tap()
        model.typeText("Camry")
        sleep(1)
        shot("13-details-model-typed-keyboard")
        app.swipeUp()
        shot("14-details-scrolled")
        note("continue enabled after typing: \(cont.isEnabled) hittable \(cont.isHittable)")
        var swipes = 0
        while !cont.isHittable, swipes < 8 { app.swipeUp(); swipes += 1 }
        shot("15-details-bottom")
        cont.tap()
        sleep(1)
        shot("16-last-done")
        let finish = app.buttons["vehicle.finish"]
        var more = 0
        while !finish.isHittable, more < 8 { app.swipeUp(); more += 1 }
        shot("17-last-done-bottom")
        finish.tap()
        sleep(2)
        shot("18-after-add")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 4) {
            shot("19-notification-alert")
            note("alert: \(alert.label)")
            let allow = alert.buttons["Allow"]
            if allow.exists { allow.tap() }
        }
        sleep(1)
        shot("20-garage-first-vehicle")
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Camry")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "No vehicle card")
        card.tap()
        sleep(2)
        shot("21-vehicle-detail-top")
        app.swipeUp()
        shot("22-vehicle-detail-scroll1")
        app.swipeUp()
        shot("23-vehicle-detail-scroll2")
        app.swipeDown(); app.swipeDown()
        let log = app.buttons["vehicle.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        log.tap()
        sleep(1)
        shot("24-log-service-sheet")
        let oil = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Oil and filter")).firstMatch
        if oil.waitForExistence(timeout: 3) {
            oil.tap()
            shot("25-log-oil-selected")
        }
        let save = app.navigationBars.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        note("save enabled \(save.isEnabled)")
        save.tap()
        sleep(2)
        shot("26-after-first-log")
    }

    func testEmptyGarageAfterCancel() {
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 15))
        tapContinue(times: 3)
        app.buttons["onboarding.getStarted"].tap()
        XCTAssertTrue(app.buttons["kind.car"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Cancel"].tap()
        sleep(1)
        shot("30-empty-garage")
        app.buttons["Add a vehicle"].firstMatch.tap()
        sleep(1)
        shot("31-add-again")
    }

    func testPickerKindsAllReachable() {
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 15))
        tapContinue(times: 3)
        app.buttons["onboarding.getStarted"].tap()
        XCTAssertTrue(app.buttons["kind.car"].waitForExistence(timeout: 10))
        app.swipeUp()
        shot("32-kind-picker-scrolled")
        app.swipeUp()
        shot("33-kind-picker-bottom")
    }
}
