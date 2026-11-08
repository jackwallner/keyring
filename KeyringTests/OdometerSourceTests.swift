import XCTest
@testable import Keyring

/// The vehicle's reading is the highest one any saved reading or logged entry
/// carries. Fixing or removing the one it came from has to move it.
@MainActor
final class OdometerSourceTests: XCTestCase {
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

    private func service(at reading: Double, daysAgo: Double = 1) -> GarageStore.ServiceDraft {
        var draft = GarageStore.ServiceDraft()
        draft.title = "Oil change"
        draft.date = .now.addingTimeInterval(-daysAgo * day)
        draft.reading = reading
        return draft
    }

    private func fillUp(at reading: Double, daysAgo: Double = 2) -> GarageStore.FuelDraft {
        var fill = GarageStore.FuelDraft()
        fill.date = .now.addingTimeInterval(-daysAgo * day)
        fill.reading = reading
        fill.volume = 10
        fill.total = 35
        return fill
    }

    // MARK: - Entries (SM-2)

    func testEditingTheEntryToFixATypoLowersTheVehicleReading() {
        let store = makeStore()
        let vehicle = car(in: store)
        var draft = service(at: 54_000)
        XCTAssertFalse(store.isSuspiciousJump(54_000, for: vehicle))
        let entry = store.log(draft, for: vehicle)
        XCTAssertEqual(vehicle.reading, 54_000)
        draft.reading = 52_000
        store.log(draft, for: vehicle, editing: entry)
        XCTAssertEqual(entry.reading, 52_000)
        XCTAssertEqual(vehicle.reading, 52_000)
        XCTAssertEqual(vehicle.readingDate, draft.date)
    }

    func testEditingAnEntryUpwardStillRaisesTheVehicleReading() {
        let store = makeStore()
        let vehicle = car(in: store)
        var draft = service(at: 52_000)
        let entry = store.log(draft, for: vehicle)
        draft.reading = 53_000
        store.log(draft, for: vehicle, editing: entry)
        XCTAssertEqual(vehicle.reading, 53_000)
    }

    func testDeletingTheEntryThatSetTheReadingLowersTheVehicleReading() {
        let store = makeStore()
        let vehicle = car(in: store)
        let entry = store.log(service(at: 62_000), for: vehicle)
        XCTAssertEqual(vehicle.reading, 62_000)
        store.delete(entry)
        XCTAssertEqual(vehicle.reading, 50_000)
        XCTAssertNotNil(vehicle.readingDate)
    }

    func testEditingAFillUpToFixATypoLowersTheVehicleReading() {
        let store = makeStore()
        let vehicle = car(in: store)
        var fill = fillUp(at: 54_000)
        let entry = store.logFuel(fill, for: vehicle)
        XCTAssertEqual(vehicle.reading, 54_000)
        fill.reading = 52_000
        store.logFuel(fill, for: vehicle, editing: entry)
        XCTAssertEqual(vehicle.reading, 52_000)
    }

    /// The commonest route: a fill-up logged on the wrong family vehicle, then deleted.
    func testDeletingAFillUpLoggedOnTheWrongVehicleRestoresTheReading() {
        let store = makeStore()
        let vehicle = car(in: store)
        let earlier = store.logFuel(fillUp(at: 51_000, daysAgo: 10), for: vehicle)
        let wrong = store.logFuel(fillUp(at: 53_000, daysAgo: 1), for: vehicle)
        XCTAssertEqual(vehicle.reading, 53_000)
        store.delete(wrong)
        XCTAssertEqual(vehicle.reading, 51_000)
        XCTAssertEqual(vehicle.readingDate, earlier.date)
    }

    func testDeletingAnOlderEntryLeavesTheReading() {
        let store = makeStore()
        let vehicle = car(in: store)
        let older = store.logFuel(fillUp(at: 51_000, daysAgo: 10), for: vehicle)
        store.logFuel(fillUp(at: 53_000, daysAgo: 1), for: vehicle)
        store.delete(older)
        XCTAssertEqual(vehicle.reading, 53_000)
    }

    /// Edit vehicle sets the meter exactly; deleting an entry above that figure must not bring the typo back.
    func testDeletingAnEntryAboveACorrectedReadingKeepsTheCorrection() {
        let store = makeStore()
        let vehicle = car(in: store)
        store.log(service(at: 54_000, daysAgo: 3), for: vehicle)
        let other = store.log(service(at: 53_500, daysAgo: 2), for: vehicle)
        store.correctReading(vehicle, to: 52_000)
        store.delete(other)
        XCTAssertEqual(vehicle.reading, 52_000)
    }

    // MARK: - Saved readings (SM-1)

    func testDeletingATypoReadingFallsBackToTheEarlierReading() throws {
        let store = makeStore()
        let vehicle = car(in: store)
        store.updateReading(vehicle, to: 520_000)
        store.delete(try XCTUnwrap(vehicle.mainReadings.first { $0.value == 520_000 }))
        XCTAssertEqual(vehicle.reading, 50_000)
    }

    func testDeletingATypoReadingKeepsTheNewestFillUpReading() throws {
        let store = makeStore()
        let vehicle = car(in: store)
        let fill = store.logFuel(fillUp(at: 52_000), for: vehicle)
        store.updateReading(vehicle, to: 520_000)
        store.delete(try XCTUnwrap(vehicle.mainReadings.first { $0.value == 520_000 }))
        XCTAssertEqual(vehicle.reading, 52_000)
        XCTAssertEqual(vehicle.readingDate, fill.date)
    }

    func testDeletingAnOldReadingKeepsTheNewerFillUp() throws {
        let store = makeStore()
        let vehicle = car(in: store)
        store.updateReading(vehicle, to: 51_000, at: .now.addingTimeInterval(-20 * day))
        store.logFuel(fillUp(at: 55_000), for: vehicle)
        let readingDate = vehicle.readingDate
        store.delete(try XCTUnwrap(vehicle.mainReadings.first { $0.value == 50_000 }))
        XCTAssertEqual(vehicle.reading, 55_000)
        XCTAssertEqual(vehicle.readingDate, readingDate)
    }

    // MARK: - Fill-ups dated ahead

    /// The fill-up date picker reaches tomorrow; like a service, a fill-up
    /// ahead of today never moves the vehicle's reading into the future.
    func testAFillUpDatedTomorrowLeavesTheVehicleReadingAlone() {
        let store = makeStore()
        let vehicle = car(in: store)
        store.logFuel(fillUp(at: 50_400, daysAgo: -1), for: vehicle)
        XCTAssertEqual(vehicle.reading, 50_000)
        XCTAssertLessThanOrEqual(vehicle.readingDate ?? .distantFuture, .now)
    }

    /// A cost worked out from two huge figures used to be stored, then trap the next import into the vehicle.
    func testACostPastAnyRealFigureIsNotStored() {
        let store = makeStore()
        let vehicle = car(in: store)
        var draft = service(at: 50_100)
        draft.cost = 1e21
        let entry = store.log(draft, for: vehicle)
        XCTAssertEqual(entry.cost, 0)
        XCTAssertEqual(NumberField.display(1e19, allowsDecimal: false, isCurrency: true), "")
        XCTAssertEqual(NumberField.display(1e19, allowsDecimal: false), "")
    }
}
