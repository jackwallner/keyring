import XCTest

/// Persona audit: larger text, imperfect vision, one-handed reach. Walks every
/// routed screen at the default size and at the largest accessibility size,
/// attaches screenshots, the system accessibility audit findings and a list of
/// controls smaller than 44 pt. Findings are attached, never asserted, so one
/// bad screen does not hide the rest.
final class AccessibilityAuditUITests: XCTestCase {
    private var app: XCUIApplication!
    private var report: [String] = []

    private let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUp() {
        continueAfterFailure = true
        report = []
    }

    override func tearDown() {
        let text = XCTAttachment(string: report.joined(separator: "\n"))
        text.name = "report"
        text.lifetime = .keepAlways
        add(text)
    }

    private func launch(route: String?, size: String?, extra: [String] = ["-SeedDemo", "-DemoPro"]) {
        app = XCUIApplication()
        var args = extra
        if let route { args += ["-ScreenshotRoute", route] }
        if let size { args += ["-UIPreferredContentSizeCategoryName", size] }
        app.launchArguments = args
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func audit(_ label: String) {
        var lines: [String] = []
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                let element = issue.element?.label ?? "?"
                lines.append("AUDIT \(label) type=\(issue.auditType.rawValue) element=[\(element)] \(issue.compactDescription) | \(issue.detailedDescription)")
                return true
            }
        } catch {
            lines.append("AUDIT \(label) threw \(error)")
        }
        report += lines
    }

    private func smallTargets(_ label: String) {
        let window = app.windows.firstMatch.frame
        let kinds: [XCUIElement.ElementType] = [.button, .link, .switch, .textField, .secureTextField, .segmentedControl, .slider, .stepper, .cell]
        for kind in kinds {
            let found = app.descendants(matching: kind).allElementsBoundByIndex.prefix(60)
            for element in found where element.exists && element.isHittable {
                let frame = element.frame
                guard frame.width > 0, frame.intersects(window) else { continue }
                if frame.width < 44 || frame.height < 44 {
                    report.append("SMALL \(label) \(kind.rawValue) [\(element.label)] \(Int(frame.width))x\(Int(frame.height)) at (\(Int(frame.minX)),\(Int(frame.minY)))")
                }
            }
        }
    }

    private func walk(_ name: String, route: String?, scrolls: Int = 2, extra: [String] = ["-SeedDemo", "-DemoPro"]) {
        for (size, tag) in [(nil, "default"), (largest, "ax5")] as [(String?, String)] {
            launch(route: route, size: size, extra: extra)
            sleep(3)
            shot("\(name)-\(tag)-0")
            audit("\(name)-\(tag)-0")
            smallTargets("\(name)-\(tag)-0")
            for index in 1...max(scrolls, 1) where scrolls > 0 {
                app.swipeUp()
                sleep(1)
                shot("\(name)-\(tag)-\(index)")
                if tag == "ax5" { audit("\(name)-\(tag)-\(index)") }
            }
            app.terminate()
        }
    }

    func testGarage() { walk("garage", route: nil, scrolls: 3) }
    func testVehicle() { walk("vehicle", route: "vehicle", scrolls: 5) }
    func testExplore() { walk("explore", route: "explore", scrolls: 3) }
    func testRecord() { walk("record", route: "record", scrolls: 1) }
    func testLogService() { walk("log", route: "log", scrolls: 3) }
    func testFuel() { walk("fuel", route: "fuel", scrolls: 2) }
    func testFuelCard() { walk("fuelcard", route: "fuelcard", scrolls: 1) }
    func testBuild() { walk("build", route: "build", scrolls: 2) }
    func testPace() { walk("pace", route: "pace", scrolls: 2) }
    func testRecalls() { walk("recalls", route: "recalls", scrolls: 2) }
    func testFamily() { walk("family", route: "family", scrolls: 2) }
    func testAdd() { walk("add", route: "add", scrolls: 2) }
    func testHistory() { walk("history", route: "history", scrolls: 2) }
    func testSettings() { walk("settings", route: "settings", scrolls: 3) }
    func testOnboarding() { walk("onboarding", route: nil, scrolls: 1, extra: ["-EmptyLog"]) }
    func testPaywall() { walk("paywall", route: nil, scrolls: 2, extra: ["-PaywallSnapshot", "yearly"]) }
}
