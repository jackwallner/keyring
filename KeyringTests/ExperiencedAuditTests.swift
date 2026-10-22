import XCTest
@testable import Keyring

/// Persona audit probes: an experienced owner's data on the export and
/// display paths. Each test records what the app produces (attached as text)
/// so the audit report can quote it.
@MainActor
final class ExperiencedAuditTests: XCTestCase {
    private func makeStore() -> GarageStore {
        GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
    }

    private func record(_ name: String, _ lines: [String]) {
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHourMeterReadingsInCSV() {
        let store = makeStore()
        let plane = store.addVehicle(NewVehicle(kind: .aircraft, powertrain: .piston, meter: .hours, year: 1978, make: "Cessna", model: "172N", reading: 3_874.6))
        var draft = GarageStore.ServiceDraft()
        draft.title = "Oil change"
        draft.reading = 3_874.6
        let entry = store.log(draft, for: plane)
        let row = CSVExport.csv(for: [plane]).split(separator: "\n").last.map(String.init) ?? ""
        record("hours-csv", [
            "Entry reading stored: \(entry.reading)",
            "UI formats it as: \(Format.reading(entry.reading, .hours))",
            "CSV row: \(row)",
        ])
        XCTAssertGreaterThan(entry.reading, 3_874)
    }

    func testRolloverShowsTrueTotalInHistoryButGaugeInEditor() {
        let store = makeStore()
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 1967, make: "Ford", model: "Mustang", reading: 99_000))
        store.recordOdometerChange(car, on: .now.addingTimeInterval(-86_400), lastShown: 99_999, newShown: 0, replaced: false)
        var draft = GarageStore.ServiceDraft()
        draft.title = "Oil change"
        draft.reading = 400
        let entry = store.log(draft, for: car)
        let date = entry.date ?? .now
        record("rollover-numbers", [
            "Gauge said 400 when logged.",
            "History row and entry page show: \(Format.reading(entry.reading, .miles))",
            "Edit sheet opens with: \(Format.reading(car.shownReading(true: entry.reading, on: date), .miles))",
            "Vehicle screen odometer button shows: \(Format.reading(car.reading, .miles))",
            "Log sheet 'Last reading' footer and update sheet show: \(Format.reading(car.shownReading, .miles))",
            "CSV odometer column: \(CSVExport.csv(for: [car]).split(separator: "\n").last.map(String.init) ?? "")",
        ])
        XCTAssertEqual(entry.reading, 100_399, accuracy: 0.5)
    }

    func testLowerReadingIsNotFlaggedOnLog() {
        let store = makeStore()
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2019, make: "Toyota", model: "Tacoma", reading: 48_210))
        let lowerFlagged = store.isSuspiciousJump(4_821, for: car)
        let higherFlagged = store.isSuspiciousJump(482_100, for: car)
        var draft = GarageStore.ServiceDraft()
        draft.title = "Oil change"
        draft.reading = 4_821
        let entry = store.log(draft, for: car)
        record("reading-typo-guard", [
            "isSuspiciousJump(4,821 vs last 48,210) = \(lowerFlagged)",
            "isSuspiciousJump(482,100 vs last 48,210) = \(higherFlagged)",
            "Saved entry reading: \(entry.reading); vehicle reading stays: \(car.reading)",
        ])
        XCTAssertTrue(higherFlagged)
    }

    func testCSVOmitsCostHidingPreferenceAndNamesFileGenerically() throws {
        let store = makeStore()
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2019, make: "Toyota", model: "Tacoma", reading: 48_210))
        var draft = GarageStore.ServiceDraft()
        draft.title = "- tightened lug nuts"
        draft.notes = "+1 spare"
        draft.cost = 99
        _ = store.log(draft, for: car)
        let url = try CSVExport.url(for: [car])
        let text = try String(contentsOf: url, encoding: .utf8)
        record("csv-file", [
            "File name: \(url.lastPathComponent)",
            "Row: \(text.split(separator: "\n").last.map(String.init) ?? "")",
        ])
        XCTAssertTrue(text.contains("99.00"))
    }
}
