import CoreData
import XCTest
@testable import Keyring

/// The spreadsheet is the backup, so what it says has to match the app.
@MainActor
final class CSVExportDateTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!

    /// The device is in Los Angeles for the test, then put back.
    private func useLosAngeles() {
        let saved = NSTimeZone.default
        NSTimeZone.default = zone
        addTeardownBlock { NSTimeZone.default = saved }
    }

    private func makeStore() -> GarageStore {
        GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
    }

    /// 8:30 pm on March 1 in Los Angeles, which is already March 2 in UTC.
    private var evening: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 20, minute: 30))!
    }

    private func loggedVehicle(in store: GarageStore) -> Vehicle {
        let vehicle = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 40_000))
        var draft = GarageStore.ServiceDraft()
        draft.title = "Oil change"
        draft.date = evening
        store.log(draft, for: vehicle)
        return vehicle
    }

    /// `TimeZone.current` stays on the system zone here, so the app's own idea
    /// of a day is `Calendar.current`'s, which is what the export has to use.
    func testTheCalendarFollowsTheDeviceTimeZone() {
        useLosAngeles()
        XCTAssertEqual(Calendar.current.timeZone.identifier, zone.identifier)
    }

    func testCSVDateIsTheDayItWasLoggedOnInTheDevicesTimeZone() throws {
        useLosAngeles()
        let vehicle = loggedVehicle(in: makeStore())
        let rows = ServiceImport.rows(from: CSVExport.csv(for: [vehicle]))
        XCTAssertEqual(rows.count, 2)
        let column = try XCTUnwrap(CSVExport.header.firstIndex(of: "Date"))
        XCTAssertEqual(rows[1][column], "2026-03-01")
    }

    func testAnExportedEntryImportsBackAsADuplicate() {
        useLosAngeles()
        let store = makeStore()
        let vehicle = loggedVehicle(in: store)
        let rows = ServiceImport.parse(CSVExport.csv(for: [vehicle]), locale: Locale(identifier: "en_US")).services
        XCTAssertEqual(rows.count, 1)
        let outcome = store.importHistory(rows, into: vehicle)
        XCTAssertEqual(outcome.added, 0)
        XCTAssertEqual(outcome.duplicates, 1)
    }

    func testCSVKeepsTheTenthsOfAnHourOnAnHourMeter() throws {
        let store = makeStore()
        let boat = store.addVehicle(NewVehicle(kind: .boat, powertrain: .outboard, meter: .hours, make: "Yamaha", model: "F150", reading: 120))
        var draft = GarageStore.ServiceDraft()
        draft.title = "Impeller"
        draft.reading = 123.4
        store.log(draft, for: boat)
        let rows = ServiceImport.rows(from: CSVExport.csv(for: [boat]))
        let column = try XCTUnwrap(CSVExport.header.firstIndex(of: "Odometer"))
        XCTAssertEqual(rows[1][column], "123.4")
    }
}
