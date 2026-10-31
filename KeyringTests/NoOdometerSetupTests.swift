import CoreData
import XCTest
@testable import Keyring

/// The odometer is optional when a vehicle is added. Leaving it empty must
/// not store a reading of zero that the first real reading is then measured against.
@MainActor
final class NoOdometerSetupTests: XCTestCase {
    private func makeStore() -> GarageStore {
        GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
    }

    private var monthAgo: Date { Date.now.addingTimeInterval(-30 * 86_400) }

    func testTheFirstReadingMonthsLaterDoesNotInventAPace() {
        let store = makeStore()
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 0), now: monthAgo)
        store.updateReading(car, to: 52_000)
        XCTAssertEqual(store.dailyUse(for: car), store.typicalDailyUse(for: car), accuracy: 0.001)
    }

    func testAJobAnsweredThisMonthIsNotOverdueOnceTheOdometerIsEntered() {
        let store = makeStore()
        let setup = Date.now.addingTimeInterval(-20 * 86_400)
        var draft = NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 0)
        draft.lastDone = ["oil": setup.addingTimeInterval(-14 * 86_400)]
        let car = store.addVehicle(draft, now: setup)
        store.updateReading(car, to: 52_000)
        let oil = store.dues(for: car).first { $0.catalogKey == "oil" }
        XCTAssertEqual(oil?.result.status, .ok)
    }

    func testAServiceLoggedWithoutAReadingIsNotOverdueOnceTheOdometerIsEntered() {
        let store = makeStore()
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 0), now: monthAgo)
        var draft = GarageStore.ServiceDraft()
        draft.date = .now.addingTimeInterval(-7 * 86_400)
        draft.taskIDs = [car.enabledTasks.first { $0.catalogKey == "oil" }!.id!]
        store.log(draft, for: car)
        store.updateReading(car, to: 52_000)
        let oil = store.dues(for: car).first { $0.catalogKey == "oil" }
        XCTAssertEqual(oil?.result.status, .ok)
    }

    func testDeletingTheOnlySavedReadingLetsTheRightOneIn() {
        let store = makeStore()
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 500_000))
        store.delete(car.mainReadings[0])
        XCTAssertEqual(car.reading, 0)
        XCTAssertNil(car.readingDate)
        store.updateReading(car, to: 50_000)
        XCTAssertEqual(car.reading, 50_000)
    }

    func testDeletingTheOnlyReadingFallsBackToTheLatestLoggedVisit() {
        let store = makeStore()
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 0))
        var draft = GarageStore.ServiceDraft()
        draft.date = .now.addingTimeInterval(-5 * 86_400)
        draft.reading = 51_000
        draft.taskIDs = [car.enabledTasks.first { $0.catalogKey == "oil" }!.id!]
        store.log(draft, for: car)
        store.updateReading(car, to: 520_000)
        store.delete(car.mainReadings[0])
        XCTAssertEqual(car.reading, 51_000)
    }

    func testAnEnteredOdometerStillStartsThePaceAndTheBaseline() {
        let store = makeStore()
        let setup = Date.now.addingTimeInterval(-20 * 86_400)
        var draft = NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 50_000)
        draft.lastDone = ["oil": setup.addingTimeInterval(-14 * 86_400)]
        let car = store.addVehicle(draft, now: setup)
        store.updateReading(car, to: 50_600)
        XCTAssertEqual(store.dailyUse(for: car), 30, accuracy: 0.5)
        let oil = store.dues(for: car).first { $0.catalogKey == "oil" }
        XCTAssertEqual(oil?.lastReading, 50_000)
        XCTAssertEqual(oil?.result.status, .ok)
    }
}
