import CoreData
import XCTest
@testable import Keyring

/// The spreadsheet export is the backup, so reading it back has to give the log back.
@MainActor
final class BackupRestoreTests: XCTestCase {
    private let us = Locale(identifier: "en_US")

    private func makeStore() -> GarageStore {
        GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
    }

    private func task(_ key: String, on vehicle: Vehicle) -> UUID {
        vehicle.enabledTasks.first { $0.catalogKey == key }!.id!
    }

    /// An oil change, a wash, a repair and a fill-up: every kind the export writes in one table.
    private func loggedCar(in store: GarageStore) -> Vehicle {
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2019, make: "Honda", model: "Civic", reading: 50_000))
        var oil = GarageStore.ServiceDraft()
        oil.date = .now.addingTimeInterval(-40 * 86_400)
        oil.reading = 49_800
        oil.taskIDs = [task("oil", on: car)]
        oil.cost = 59.99
        store.log(oil, for: car)
        var wash = GarageStore.ServiceDraft()
        wash.date = .now.addingTimeInterval(-10 * 86_400)
        wash.taskIDs = [task("wash", on: car)]
        store.log(wash, for: car)
        var repair = GarageStore.ServiceDraft()
        repair.kind = .repair
        repair.title = "Water pump"
        repair.cost = 420
        repair.date = .now.addingTimeInterval(-20 * 86_400)
        store.log(repair, for: car)
        var fill = GarageStore.FuelDraft()
        fill.unit = .gallons
        fill.reading = 50_300
        fill.volume = 10.5
        fill.unitPrice = 3.659
        store.logFuel(fill, for: car)
        return car
    }

    func testABackupReadsBackAsServicesRepairsAndFillUps() {
        let result = ServiceImport.parse(CSVExport.csv(for: [loggedCar(in: makeStore())]), locale: us)
        XCTAssertEqual(result.services.map(\.work).sorted(), ["Oil and filter", "Wash", "Water pump"])
        XCTAssertEqual(result.services.first { $0.work == "Water pump" }?.kind, .repair)
        XCTAssertEqual(result.fillUps.count, 1)
        XCTAssertEqual(result.skippedExpenses, 0, "a logged wash is the owner's own entry, not an expense")
    }

    func testRestoringABackupKeepsServicesAsServicesAndRestartsTheSchedule() {
        let csv = CSVExport.csv(for: [loggedCar(in: makeStore())])
        let fresh = makeStore()
        let car = fresh.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2019, make: "Honda", model: "Civic", reading: 50_300))
        let result = ServiceImport.parse(csv, locale: us)
        let outcome = fresh.importHistory(result.services + result.fillUps, into: car)
        XCTAssertEqual(outcome.added, 3)
        XCTAssertEqual(outcome.fillUps, 1)
        XCTAssertEqual(Set(car.serviceEntries.compactMap(\.title)), ["Oil and filter", "Wash", "Water pump"])
        XCTAssertEqual(car.fuelEntries.count, 1)
        XCTAssertEqual(fresh.dues(for: car).first { $0.catalogKey == "oil" }?.lastReading, 49_800)
    }

    func testAnotherAppsInsuranceAndTollsAreStillSkipped() {
        let file = """
        Date,Odometer,Service,Cost
        2025-01-10,28000,Oil change,59.99
        2025-01-12,28010,Insurance,600.00
        2025-01-13,28020,Wash,12.00
        """
        let result = ServiceImport.parse(file, locale: us)
        XCTAssertEqual(result.services.map(\.work), ["Oil change"])
        XCTAssertEqual(result.skippedExpenses, 2)
    }
}
