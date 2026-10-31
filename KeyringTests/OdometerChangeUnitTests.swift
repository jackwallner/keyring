import CoreData
import XCTest
@testable import Keyring

/// A rolled-over or replaced odometer keeps its offset in the unit it was
/// recorded in, so switching the vehicle's unit has to carry the offset along.
@MainActor
final class OdometerChangeUnitTests: XCTestCase {
    private func makeStore() -> GarageStore {
        GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
    }

    private func rolledOverCar(in store: GarageStore) -> Vehicle {
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 99_000))
        store.recordOdometerChange(car, on: .now.addingTimeInterval(-86_400), lastShown: 99_999, newShown: 0, replaced: false)
        store.updateReading(car, to: 1_000)
        return car
    }

    func testTheOdometerShowsTheSameDistanceAfterSwitchingUnits() {
        let store = makeStore()
        let car = rolledOverCar(in: store)
        XCTAssertEqual(car.shownReading, 1_000, accuracy: 0.001)
        store.changeMeter(car, to: .kilometers)
        XCTAssertEqual(car.shownReading, 1_609.344, accuracy: 1)
    }

    func testSwitchingToHoursDropsTheOffsetWithTheReadings() {
        let store = makeStore()
        let car = rolledOverCar(in: store)
        store.changeMeter(car, to: .hours)
        XCTAssertEqual(car.reading, 0)
        XCTAssertEqual(car.shownReading, 0)
        XCTAssertTrue(car.profile.odometerChanges.isEmpty)
    }
}
