import XCTest

/// Persona audit: an experienced owner repeating core tasks (log a job, log a
/// fill-up, search the history, tidy the schedule) and looking for accurate,
/// efficient deeper features. The tests observe and record what the app does
/// (observations.txt plus screenshots) rather than assert on opinions; they
/// fail only when a screen the flow needs never appears.
final class ExperiencedAuditUITests: XCTestCase {
    private var app: XCUIApplication!
    private var notes: [String] = []

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        notes = []
    }

    override func tearDown() {
        let text = XCTAttachment(string: notes.joined(separator: "\n"))
        text.name = "observations"
        text.lifetime = .keepAlways
        add(text)
    }

    // MARK: - Helpers

    private func launch(_ route: String? = nil, extra: [String] = []) {
        app.launchArguments = ["-SeedDemo", "-DemoPro"] + extra
        if let route { app.launchArguments += ["-ScreenshotRoute", route] }
        app.launch()
    }

    private func note(_ line: String) { notes.append(line) }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func button(prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func scrollTo(_ element: XCUIElement) {
        for down in [true, false] {
            var swipes = 0
            while !(element.exists && element.isHittable), swipes < 8 {
                if down { app.swipeUp() } else { app.swipeDown() }
                swipes += 1
            }
        }
    }

    private func tapButton(_ prefix: String) {
        let target = button(prefix: prefix)
        scrollTo(target)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "No button starting with \(prefix)")
        target.tap()
    }

    private func expectTitle(_ title: String, timeout: TimeInterval = 8) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: timeout), "Expected screen \(title)")
    }

    private func clear(_ field: XCUIElement) {
        guard let current = field.value as? String, !current.isEmpty else { return }
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
    }

    private func type(_ text: String, into field: XCUIElement) {
        field.tap()
        field.typeText(text)
    }

    private func value(_ field: XCUIElement) -> String { (field.value as? String) ?? "nil" }

    // MARK: - Log a job, again

    /// Back-to-back receipts from the same shop: what carries over to the next form.
    func testRepeatLoggingSameShop() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 15)
        tapButton("Log service")
        expectTitle("Log service")
        attach("01-log-form-default")
        tapButton("Oil and filter")
        let shop = app.textFields["Shop name"]
        scrollTo(shop)
        type("Les Schwab\n", into: shop)
        let another = app.buttons["log.saveAnother"]
        scrollTo(another)
        attach("02-before-save-another")
        another.tap()
        // The form resets in place; look at what it kept.
        sleepBriefly()
        let shopAfter = app.textFields["Shop name"]
        scrollTo(shopAfter)
        note("After Save and add another: shop field value = \(value(shopAfter)) (placeholder text means empty)")
        note("Recent-shop chip 'Les Schwab' present: \(app.buttons["Les Schwab"].exists)")
        note("'Myself' selected: \(app.buttons["Myself"].isSelected), 'A shop' selected: \(app.buttons["A shop"].isSelected)")
        note("Selected job rows after reset: \(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Oil and filter'")).count) oil rows; first isSelected=\(button(containing: "Oil and filter").isSelected)")
        attach("03-after-save-another")
        app.swipeDown()
        attach("04-after-save-another-top")
    }

    private func sleepBriefly() { _ = app.wait(for: .runningForeground, timeout: 1.0) }

    // MARK: - Fill-up figures

    /// Typing all three pump figures as the pump shows them.
    func testFillUpAllThreePumpFigures() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 15)
        tapButton("Fill-up")
        expectTitle("Fill-up")
        let fields = app.textFields
        note("Text fields on fill-up form: \(fields.count)")
        let volume = fields.element(boundBy: 0)
        let price = fields.element(boundBy: 1)
        let total = fields.element(boundBy: 2)
        type("12.5", into: volume)
        type("3.599", into: price)
        sleepBriefly()
        note("Typed gallons 12.5, price 3.599 -> gallons='\(value(volume))' price='\(value(price))' total='\(value(total))'")
        attach("10-fill-two-typed")
        // The pump says the total is 44.98, not the computed 44.99.
        clear(total)
        type("44.98", into: total)
        sleepBriefly()
        note("Then typed total 44.98 -> gallons='\(value(volume))' price='\(value(price))' total='\(value(total))'")
        let footer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'worked out'")).firstMatch
        note("Footer shown: \(footer.exists ? footer.label : "none")")
        attach("11-fill-after-total-typed")
        app.keyboards.buttons["Done"].tap()
        attach("12-fill-form-top")
        app.swipeUp()
        attach("13-fill-form-bottom")
    }

    // MARK: - Odometer typo guard

    /// A reading far below the last one, typed on a job logged today.
    func testLowerReadingOnLoggedJob() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 15)
        tapButton("Log service")
        expectTitle("Log service")
        tapButton("Oil and filter")
        let reading = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Optional'")).firstMatch
        scrollTo(reading)
        note("Reading field found: \(reading.exists)")
        type("4821", into: reading)
        app.keyboards.buttons["Done"].tap()
        attach("20-lower-reading-typed")
        app.navigationBars.buttons["Save"].tap()
        let dialog = button(prefix: "Save at")
        note("Warning dialog for 4,821 (last reading 48,210) appeared: \(dialog.waitForExistence(timeout: 2))")
        note("Back on vehicle screen without any prompt: \(app.navigationBars["The Tacoma"].waitForExistence(timeout: 3))")
        attach("21-after-save-lower-reading")
    }

    // MARK: - Schedule tidy-up

    /// Swipe-delete on the schedule list: a confirmation, or gone at once?
    func testScheduleSwipeDelete() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 15)
        let all = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "All [0-9]+ jobs")).firstMatch
        scrollTo(all)
        all.tap()
        expectTitle("Schedule")
        attach("30-schedule")
        let rows = app.cells
        let before = rows.count
        note("Schedule rows before: \(before)")
        let first = rows.element(boundBy: 0)
        first.swipeLeft()
        attach("31-schedule-swiped")
        let delete = app.buttons["Delete"].firstMatch
        note("Swipe shows Delete: \(delete.waitForExistence(timeout: 2))")
        if delete.exists { delete.tap() }
        sleepBriefly()
        let dialog = app.sheets.firstMatch.exists || app.alerts.firstMatch.exists || app.buttons["Remove"].exists
        note("Confirmation shown after tapping Delete: \(dialog)")
        note("Schedule rows after: \(app.cells.count)")
        attach("32-schedule-after-delete")
        note("Swipe actions offered on a schedule row besides Delete: \(app.buttons.matching(NSPredicate(format: "label == 'Log' OR label == 'Done'")).count)")
    }

    // MARK: - History search

    /// Looking things up the way a long-time owner does: part number, price, odometer.
    func testHistorySearchFields() {
        launch("history")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 15))
        attach("40-history")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let queries = ["Bilstein", "24-285964", "312.40", "Les Schwab", "oil", "45000", "2025"]
        for query in queries {
            search.tap()
            clear(search)
            search.typeText(query)
            sleepBriefly()
            let empty = app.staticTexts["Nothing matches"].exists
            note("Search '\(query)': \(empty ? "Nothing matches" : "\(app.cells.count) rows")")
            attach("41-search-\(query.replacingOccurrences(of: " ", with: "_"))")
        }
        note("Global History toolbar has a log/add button: \(app.navigationBars["History"].buttons["Log service"].exists)")
    }

    // MARK: - Garage shortcuts

    func testGarageLongPressActions() {
        launch()
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'The Tacoma'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        attach("50-garage")
        card.press(forDuration: 1.2)
        sleepBriefly()
        let labels = app.buttons.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }.prefix(30)
        note("Long-press menu buttons: \(labels.joined(separator: " | "))")
        attach("51-garage-long-press")
    }

    // MARK: - Rolled-over odometer, three views of one number

    func testOdometerReplacedShowsConsistentNumbers() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 15)
        let readingBefore = button(prefix: "Odometer").label
        note("Hero odometer before change: \(readingBefore)")
        app.buttons["vehicle.more"].tap()
        let item = button(containing: "Odometer rolled over")
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        expectTitle("Odometer")
        attach("60-odometer-sheet")
        // Defaults: before = current gauge, after = 0. Say the gauge now reads 0.
        app.navigationBars.buttons["Save"].tap()
        expectTitle("The Tacoma")
        note("Hero odometer after rollover: \(button(prefix: "Odometer").label)")
        tapButton("Log service")
        expectTitle("Log service")
        tapButton("Oil and filter")
        let lastReading = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Last reading'")).firstMatch
        scrollTo(lastReading)
        note("Log sheet footer: \(lastReading.exists ? lastReading.label : "none")")
        let reading = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Optional'")).firstMatch
        type("300", into: reading)
        app.keyboards.buttons["Done"].tap()
        attach("61-log-after-rollover")
        app.navigationBars.buttons["Save"].tap()
        expectTitle("The Tacoma")
        sleepBriefly()
        let milesLabels = app.buttons.allElementsBoundByIndex.map(\.label).filter { $0.contains(" mi") }.prefix(12)
        note("Buttons showing miles on vehicle screen: \(milesLabels.joined(separator: " | "))")
        attach("62-vehicle-after-rollover")
    }

    // MARK: - Screens for the report

    func testVehicleScreensForReview() {
        launch("vehicle")
        expectTitle("The Tacoma", timeout: 15)
        attach("70-vehicle-top")
        app.swipeUp()
        attach("71-vehicle-scrolled")
        app.swipeUp()
        attach("72-vehicle-scrolled-2")
    }

    func testServiceRecordPreview() {
        launch("record")
        XCTAssertTrue(app.navigationBars["Service Record"].waitForExistence(timeout: 20))
        attach("80-record")
        app.buttons["record.include"].tap()
        attach("81-record-include-menu")
    }
}
