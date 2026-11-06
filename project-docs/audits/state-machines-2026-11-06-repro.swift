import CoreData
import XCTest
@testable import Keyring

/// Repro suite for the 2026-11-06 state machine audit. Failing tests are the findings.
@MainActor
final class StateMachineAuditRepro: XCTestCase {
    private let day: TimeInterval = 86_400

    private func makeStore() -> GarageStore {
        GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
    }

    private func car(in store: GarageStore, reading: Double = 50_000, startedDaysAgo: Double = 30) -> Vehicle {
        store.addVehicle(
            NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: reading),
            now: .now.addingTimeInterval(-startedDaysAgo * day)
        )
    }

    // MARK: - SM-1: deleting a saved reading falls back past logged fill-ups

    /// Control: with nothing but meter readings, deleting the typo falls back to the older reading.
    func testControlDeletingATypoReadingFallsBackToTheEarlierReading() throws {
        let store = makeStore()
        let vehicle = car(in: store)
        XCTAssertEqual(vehicle.reading, 50_000)
        XCTAssertEqual(vehicle.mainReadings.count, 1)
        store.updateReading(vehicle, to: 520_000)
        XCTAssertEqual(vehicle.reading, 520_000)
        let typo = try XCTUnwrap(vehicle.mainReadings.first { $0.value == 520_000 })
        store.delete(typo)
        XCTAssertEqual(vehicle.reading, 50_000)
    }

    /// A fill-up at 52,000 is in the log. The footer on the Update odometer sheet says
    /// "To fix a typo, delete the wrong reading below."
    func testDeletingATypoReadingKeepsTheNewestFillUpReading() throws {
        let store = makeStore()
        let vehicle = car(in: store)
        var fill = GarageStore.FuelDraft()
        fill.date = .now.addingTimeInterval(-2 * day)
        fill.reading = 52_000
        fill.volume = 10
        fill.total = 35
        store.logFuel(fill, for: vehicle)
        XCTAssertEqual(vehicle.reading, 52_000)
        XCTAssertEqual(vehicle.mainReadings.count, 1)
        store.updateReading(vehicle, to: 520_000)
        XCTAssertEqual(vehicle.reading, 520_000)
        let typo = try XCTUnwrap(vehicle.mainReadings.first { $0.value == 520_000 })
        store.delete(typo)
        XCTAssertTrue((vehicle.entries ?? []).contains { $0.hasReading && $0.reading == 52_000 })
        XCTAssertEqual(vehicle.reading, 52_000, "the odometer fell below a fill-up already in the log")
    }

    // MARK: - SM-2: editing or deleting the entry that set the reading

    /// Control: raising an entry's reading raises the vehicle's.
    func testControlEditingAnEntryUpwardRaisesTheVehicleReading() {
        let store = makeStore()
        let vehicle = car(in: store)
        var draft = GarageStore.ServiceDraft()
        draft.title = "Oil change"
        draft.date = .now.addingTimeInterval(-day)
        draft.reading = 52_000
        let entry = store.log(draft, for: vehicle)
        XCTAssertEqual(vehicle.reading, 52_000)
        draft.reading = 53_000
        store.log(draft, for: vehicle, editing: entry)
        XCTAssertEqual(entry.reading, 53_000)
        XCTAssertEqual(vehicle.reading, 53_000)
    }

    /// 54,000 typed for 52,000 is under the "extra digit" threshold, so it saves without a prompt.
    func testEditingTheEntryToFixATypoLowersTheVehicleReading() {
        let store = makeStore()
        let vehicle = car(in: store)
        var draft = GarageStore.ServiceDraft()
        draft.title = "Oil change"
        draft.date = .now.addingTimeInterval(-day)
        draft.reading = 54_000
        XCTAssertFalse(store.isSuspiciousJump(54_000, for: vehicle))
        let entry = store.log(draft, for: vehicle)
        XCTAssertEqual(vehicle.reading, 54_000)
        draft.reading = 52_000
        store.log(draft, for: vehicle, editing: entry)
        XCTAssertEqual(entry.reading, 52_000)
        XCTAssertEqual(vehicle.reading, 52_000, "the garage card still shows the typo")
    }

    func testDeletingTheEntryThatSetTheReadingLowersTheVehicleReading() {
        let store = makeStore()
        let vehicle = car(in: store)
        var draft = GarageStore.ServiceDraft()
        draft.title = "Oil change"
        draft.date = .now.addingTimeInterval(-day)
        draft.reading = 62_000
        let entry = store.log(draft, for: vehicle)
        XCTAssertEqual(vehicle.reading, 62_000)
        store.delete(entry)
        XCTAssertTrue((vehicle.entries ?? []).filter { !$0.isDeleted }.isEmpty)
        XCTAssertEqual(vehicle.reading, 50_000)
    }

    // MARK: - SM-3: unit switch in Edit vehicle stamps a reading "today"

    private func paceInKilometers(_ store: GarageStore, _ vehicle: Vehicle) -> Double { store.dailyUse(for: vehicle) }

    private func vehicleWithOldLastReading(in store: GarageStore) -> Vehicle {
        let vehicle = car(in: store, reading: 10_000, startedDaysAgo: 300)
        store.updateReading(vehicle, to: 12_000, at: .now.addingTimeInterval(-60 * day))
        return vehicle
    }

    /// Control: the unit switch alone keeps the pace, converted.
    func testControlSwitchingUnitsConvertsThePace() {
        let store = makeStore()
        let vehicle = vehicleWithOldLastReading(in: store)
        let before = store.dailyUse(for: vehicle)
        XCTAssertEqual(before, 2_000.0 / 240.0, accuracy: 0.2)
        store.changeMeter(vehicle, to: .kilometers)
        XCTAssertEqual(store.dailyUse(for: vehicle), before * 1.609344, accuracy: 0.3)
    }

    /// Replays `EditVehicleView.save()`: the form converts and rounds the odometer field when the
    /// unit changes, so `readingTyped` is true even though nobody typed anything.
    func testSwitchingUnitsInTheEditorKeepsThePace() {
        let store = makeStore()
        let vehicle = vehicleWithOldLastReading(in: store)
        let before = store.dailyUse(for: vehicle)
        let draftReading = (vehicle.shownReading * 1.609344).rounded()
        let readingTyped = draftReading != vehicle.shownReading
        XCTAssertTrue(readingTyped)
        store.changeMeter(vehicle, to: .kilometers)
        if readingTyped, draftReading > 0 { store.correctReading(vehicle, to: draftReading) }
        XCTAssertEqual(vehicle.meter, .kilometers)
        XCTAssertEqual(store.dailyUse(for: vehicle), before * 1.609344, accuracy: 0.3, "a reading dated today flattened the pace")
    }

    // MARK: - SM-4: planned vehicle slot comes back when the vehicle is sold

    /// Control: adding the planned car crosses its slot off.
    func testControlAddingThePlannedCarCrossesItOff() {
        let store = makeStore()
        _ = car(in: store)
        XCTAssertTrue(plannedSlots(store, planned: "car").isEmpty)
    }

    /// `GarageView.plannedSlots` reads `garage.vehicles`, which hides retired vehicles.
    func testSellingThePlannedCarDoesNotBringItsSlotBack() {
        let store = makeStore()
        let vehicle = car(in: store)
        XCTAssertTrue(plannedSlots(store, planned: "car").isEmpty)
        store.markSold(vehicle, on: .now, price: 9_000)
        XCTAssertTrue(vehicle.isRetired)
        XCTAssertTrue(plannedSlots(store, planned: "car").isEmpty, "the garage offers 'Add your car' again")
    }

    /// The same expression as GarageView.plannedSlots.
    private func plannedSlots(_ garage: GarageStore, planned: String) -> [VehicleKind] {
        PlannedVehicles.remaining(planned, owned: garage.vehicles.filter { !garage.isShared($0) }.map(\.kind))
    }
}
