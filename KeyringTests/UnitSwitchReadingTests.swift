import XCTest
@testable import Keyring

/// Switching miles and kilometers in Edit vehicle converts the odometer field.
/// That is not a typed reading, so it must not stamp one dated now.
@MainActor
final class UnitSwitchReadingTests: XCTestCase {
    private let day: TimeInterval = 86_400

    private func makeStore() -> GarageStore {
        GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
    }

    private func vehicleWithOldLastReading(in store: GarageStore) -> Vehicle {
        let vehicle = store.addVehicle(
            NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 10_000),
            now: .now.addingTimeInterval(-300 * day)
        )
        store.updateReading(vehicle, to: 12_000, at: .now.addingTimeInterval(-60 * day))
        return vehicle
    }

    /// Replays `EditVehicleView.save()` with the field the form converts and rounds on a unit switch.
    private func saveEditor(_ store: GarageStore, _ vehicle: Vehicle, figure: Double, meter: MeterUnit) {
        let readingTyped = EditVehicleView.readingWasTyped(figure, for: vehicle, meter: meter)
        store.changeMeter(vehicle, to: meter)
        if readingTyped, figure > 0 { store.correctReading(vehicle, to: figure) }
    }

    func testSwitchingUnitsInTheEditorKeepsThePace() {
        let store = makeStore()
        let vehicle = vehicleWithOldLastReading(in: store)
        let before = store.dailyUse(for: vehicle)
        saveEditor(store, vehicle, figure: (vehicle.shownReading * 1.609344).rounded(), meter: .kilometers)
        XCTAssertEqual(vehicle.meter, .kilometers)
        XCTAssertEqual(store.dailyUse(for: vehicle), before * 1.609344, accuracy: 0.3)
    }

    /// 12,000 mi is 19,312.128 km; the field rounds down to 19,312, which read as a correction deleted the real reading.
    func testSwitchingUnitsInTheEditorKeepsTheLastRealReading() {
        let store = makeStore()
        let vehicle = vehicleWithOldLastReading(in: store)
        let lastDate = vehicle.readingDate
        saveEditor(store, vehicle, figure: (vehicle.shownReading * 1.609344).rounded(), meter: .kilometers)
        XCTAssertEqual(vehicle.mainReadings.count, 2)
        XCTAssertTrue(vehicle.mainReadings.contains { abs($0.value - 12_000 * 1.609344) < 0.01 })
        XCTAssertEqual(vehicle.readingDate, lastDate)
    }

    func testATypedFigureInTheNewUnitStillSetsTheMeter() {
        let store = makeStore()
        let vehicle = vehicleWithOldLastReading(in: store)
        saveEditor(store, vehicle, figure: 19_000, meter: .kilometers)
        XCTAssertEqual(vehicle.reading, 19_000)
    }

    func testAnUntouchedFieldWithoutASwitchIsNotTyped() {
        let store = makeStore()
        let vehicle = vehicleWithOldLastReading(in: store)
        XCTAssertFalse(EditVehicleView.readingWasTyped(vehicle.shownReading, for: vehicle, meter: .miles))
        XCTAssertTrue(EditVehicleView.readingWasTyped(12_500, for: vehicle, meter: .miles))
    }
}
