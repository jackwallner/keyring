import CoreData
import XCTest
@testable import Keyring

/// The backup says which jobs each visit covered. Reading it back has to restart
/// those countdowns, and only those, whatever the visit was titled.
@MainActor
final class BackupCoverageTests: XCTestCase {
    private let us = Locale(identifier: "en_US")

    private func makeStore() -> GarageStore {
        GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
    }

    private func civic(in store: GarageStore, reading: Double = 50_000) -> Vehicle {
        store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2019, make: "Honda", model: "Civic", reading: reading))
    }

    private func task(_ key: String, on vehicle: Vehicle) throws -> UUID {
        try XCTUnwrap(vehicle.enabledTasks.first { $0.catalogKey == key }?.id, key)
    }

    /// `source`'s backup, restored into a new Civic in a new store.
    private func restored(from source: Vehicle) -> (store: GarageStore, car: Vehicle) {
        let store = makeStore()
        let car = civic(in: store, reading: 50_300)
        let result = ServiceImport.parse(CSVExport.csv(for: [source]), locale: us)
        store.importHistory(result.services + result.fillUps, into: car)
        return (store, car)
    }

    private func due(_ key: String, in restored: (store: GarageStore, car: Vehicle)) -> TaskDue? {
        restored.store.dues(for: restored.car).first { $0.catalogKey == key }
    }

    func testAVisitThatCoveredThreeJobsRestartsAllThree() throws {
        let store = makeStore()
        let car = civic(in: store)
        var visit = GarageStore.ServiceDraft()
        visit.date = .now.addingTimeInterval(-40 * 86_400)
        visit.reading = 49_800
        visit.taskIDs = [try task("oil", on: car), try task("rotate", on: car), try task("cabinFilter", on: car)]
        store.log(visit, for: car)
        let back = restored(from: car)
        for key in ["oil", "rotate", "cabinFilter"] {
            XCTAssertEqual(due(key, in: back)?.lastReading, 49_800, "\(key) was done on that visit")
        }
    }

    func testAVisitWithItsOwnTitleRestartsTheJobsItCovered() throws {
        let store = makeStore()
        let car = civic(in: store)
        var visit = GarageStore.ServiceDraft()
        visit.date = .now.addingTimeInterval(-40 * 86_400)
        visit.reading = 49_800
        visit.title = "Dealer 30k service"
        visit.taskIDs = [try task("oil", on: car), try task("rotate", on: car)]
        store.log(visit, for: car)
        let back = restored(from: car)
        XCTAssertEqual(back.car.serviceEntries.first?.title, "Dealer 30k service")
        for key in ["oil", "rotate"] {
            XCTAssertEqual(due(key, in: back)?.lastReading, 49_800, "\(key) was done on that visit")
        }
    }

    func testARecallOrRepairThatNamesBrakesDoesNotCountAsTheBrakeInspection() throws {
        let store = makeStore()
        let car = civic(in: store)
        var recall = GarageStore.ServiceDraft()
        recall.kind = .recall
        recall.recallCampaign = "24V123000"
        recall.title = "Recall: service brakes, hydraulic"
        recall.date = .now.addingTimeInterval(-30 * 86_400)
        store.log(recall, for: car)
        var repair = GarageStore.ServiceDraft()
        repair.kind = .repair
        repair.title = "Brake line replacement"
        repair.date = .now.addingTimeInterval(-20 * 86_400)
        repair.reading = 49_900
        store.log(repair, for: car)
        XCTAssertNil(store.dues(for: car).first { $0.catalogKey == "brakes" }?.lastDate, "nothing in the log covered the inspection")
        let back = restored(from: car)
        XCTAssertNil(due("brakes", in: back)?.lastDate, "the restored log says the same")
    }

    func testAnOldBackupWithoutAJobsColumnStillMatchesByTitle() throws {
        let file = """
        Vehicle,Year,Make,Model,Date,Odometer,Unit,Type,Work,Cost,Shop,DIY,Notes
        Civic,2019,Honda,Civic,2026-01-10,49800,mi,Maintenance,Oil and filter,59.99,,,
        """
        let store = makeStore()
        let car = civic(in: store, reading: 50_300)
        let result = ServiceImport.parse(file, locale: us)
        store.importHistory(result.services, into: car)
        XCTAssertEqual(store.dues(for: car).first { $0.catalogKey == "oil" }?.lastReading, 49_800)
    }
}
