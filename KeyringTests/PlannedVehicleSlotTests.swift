import XCTest
@testable import Keyring

/// Onboarding picks become "Add your <kind>" cards until a vehicle of that kind is added.
@MainActor
final class PlannedVehicleSlotTests: XCTestCase {
    private func makeStore() -> GarageStore {
        GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
    }

    private func car(in store: GarageStore) -> Vehicle {
        store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 50_000))
    }

    func testAddingThePlannedCarCrossesItOff() {
        let store = makeStore()
        XCTAssertEqual(PlannedVehicles.remaining("car", in: store), [.car])
        _ = car(in: store)
        XCTAssertTrue(PlannedVehicles.remaining("car", in: store).isEmpty)
    }

    func testSellingThePlannedCarDoesNotBringItsSlotBack() {
        let store = makeStore()
        let vehicle = car(in: store)
        store.markSold(vehicle, on: .now, price: 9_000)
        XCTAssertTrue(vehicle.isRetired)
        XCTAssertTrue(PlannedVehicles.remaining("car", in: store).isEmpty)
    }

    func testASoldCarCrossesOffOnlyOneOfTwoPlannedCars() {
        let store = makeStore()
        store.markSold(car(in: store), on: .now, price: 9_000)
        XCTAssertEqual(PlannedVehicles.remaining("car,car", in: store), [.car])
    }
}
