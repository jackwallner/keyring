import CoreData
import XCTest
@testable import Keyring

/// Second meters, events, mods, odometer changes and the trait catalog.
@MainActor
final class EnthusiastTests: XCTestCase {
    private func makeStore() -> GarageStore {
        GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
    }

    private func due(_ store: GarageStore, _ vehicle: Vehicle, _ key: String) -> TaskDue? {
        store.dues(for: vehicle).first { $0.catalogKey == key }
    }

    // MARK: - DueEngine

    func testCombineTakesTheMostUrgentAndEarliest() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let ok = DueResult(status: .ok, dueDate: now.addingTimeInterval(90 * 86_400), dueReading: 50_000, progress: 0.2, dateIsEstimated: true)
        let soon = DueResult(status: .dueSoon, dueDate: now.addingTimeInterval(10 * 86_400), dueReading: nil, progress: 0.9, dateIsEstimated: false)
        let unknown = DueResult(status: .noRecord, dueDate: nil, dueReading: nil, progress: 0, dateIsEstimated: false)
        let combined = DueEngine.combine([ok, soon, unknown])
        XCTAssertEqual(combined.status, .dueSoon)
        XCTAssertEqual(combined.dueDate, soon.dueDate)
        XCTAssertEqual(combined.dueReading, 50_000)
        XCTAssertEqual(combined.progress, 0.9)
        XCTAssertEqual(DueEngine.combine([unknown, ok]).status, .ok)
    }

    func testEventInThePastIsOwedAndInTheFutureIsComing() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(DueEngine.triggered(by: now.addingTimeInterval(-86_400), now: now).status, .overdue)
        XCTAssertEqual(DueEngine.triggered(by: now.addingTimeInterval(5 * 86_400), now: now).status, .dueSoon)
        XCTAssertEqual(DueEngine.triggered(by: now.addingTimeInterval(90 * 86_400), now: now).status, .ok)
    }

    // MARK: - Events

    func testTrackDayBringsBrakeFluidDueUntilItsDone() {
        let store = makeStore()
        var draft = NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2003, make: "BMW", model: "M3", reading: 90_000)
        draft.traits = [.track]
        draft.lastDone = ["brakeFluid": .now.addingTimeInterval(-20 * 86_400)]
        let car = store.addVehicle(draft)
        XCTAssertEqual(due(store, car, "brakeFluid")?.trigger, .trackDay)
        XCTAssertNotEqual(due(store, car, "brakeFluid")?.result.status, .overdue)

        store.logEvent(.trackDay, on: .now.addingTimeInterval(-86_400), for: car)
        let owed = due(store, car, "brakeFluid")
        XCTAssertEqual(owed?.result.status, .overdue)
        XCTAssertEqual(owed?.dueLine().hasPrefix("Due after the track day"), true)
        XCTAssertTrue(store.jobs(triggeredBy: .trackDay, on: car).contains { $0.catalogKey == "trackPrep" })

        var service = GarageStore.ServiceDraft()
        service.taskIDs = [owed!.taskID]
        store.log(service, for: car)
        XCTAssertNotEqual(due(store, car, "brakeFluid")?.result.status, .overdue)
    }

    func testAPlannedEventBringsJobsDueByThatDate() {
        let store = makeStore()
        var draft = NewVehicle(kind: .truck, powertrain: .gasoline, meter: .miles, year: 2021, make: "Toyota", model: "4Runner", reading: 30_000)
        draft.traits = [.fourByFour]
        let rig = store.addVehicle(draft)
        let trip = Date.now.addingTimeInterval(10 * 86_400)
        store.logEvent(.waterCrossing, on: trip, for: rig)
        let diff = due(store, rig, "frontDiff")
        XCTAssertEqual(diff?.pendingEvent.map { Calendar.current.isDate($0, inSameDayAs: trip) }, true)
        XCTAssertEqual(diff?.result.status, .dueSoon)
        // A future event never moves the odometer.
        XCTAssertEqual(rig.reading, 30_000)
    }

    // MARK: - Second meter

    func testUTVCountsHoursAndMilesWhicheverFirst() {
        let store = makeStore()
        var draft = NewVehicle(kind: .atv, powertrain: .gasoline, meter: .hours, year: 2022, make: "Polaris", model: "RZR", reading: 120)
        draft.auxMeterName = "Odometer"
        draft.auxMeter = .miles
        draft.lastDone = ["oil": .now.addingTimeInterval(-5 * 86_400)]
        let rzr = store.addVehicle(draft)
        let oil = (rzr.tasks ?? []).first { $0.catalogKey == "oil" }!
        XCTAssertEqual(oil.intervalDistance, 100)
        XCTAssertEqual(oil.auxInterval, 1_000)
        XCTAssertEqual(oil.intervalText, "Every 100 hrs, 1,000 mi or 1 year")

        // Logged at 120 hrs and 2,000 mi; then 1,100 trail miles but few hours.
        var service = GarageStore.ServiceDraft()
        service.taskIDs = [oil.id!]
        service.reading = 120
        service.auxReading = 2_000
        service.date = .now.addingTimeInterval(-86_400)
        store.log(service, for: rzr)
        XCTAssertNotEqual(due(store, rzr, "oil")?.result.status, .overdue)
        store.updateAuxReading(rzr, to: 3_100)
        XCTAssertEqual(due(store, rzr, "oil")?.result.status, .overdue)
    }

    func testAnyVehicleCanAddTrackHours() {
        let store = makeStore()
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2016, make: "Mazda", model: "MX-5", reading: 40_000))
        store.setAuxMeter(car, name: "Track", unit: .hours)
        XCTAssertTrue(car.hasAuxMeter)
        XCTAssertEqual(car.auxMeterLabel, "Track hours")
        let task = store.addCustomTask(name: "Rod bearings", distance: 40, months: 0, onAuxMeter: true, to: car)
        XCTAssertEqual(task.countingMeter, .hours)
        XCTAssertEqual(task.intervalText, "Every 40 track hrs")
    }

    // MARK: - Catalog traits

    func testTraitsShapeTheCatalog() {
        let plain = MaintenanceCatalog.items(for: .truck, powertrain: .gasoline, region: "US").map(\.key)
        XCTAssertFalse(plain.contains("transferCase"))
        XCTAssertTrue(plain.contains("rearDiff"))

        let rig = MaintenanceCatalog.items(for: .truck, powertrain: .gasoline, traits: [.fourByFour], region: "US")
        XCTAssertTrue(rig.contains { $0.key == "transferCase" && $0.isCore })
        XCTAssertEqual(rig.first { $0.key == "airFilter" }?.trigger, .dust)

        let belt = MaintenanceCatalog.items(for: .motorcycle, powertrain: .gasoline, drive: .belt).map(\.key)
        XCTAssertFalse(belt.contains("chain"))
        XCTAssertTrue(belt.contains("driveBelt"))
        XCTAssertTrue(MaintenanceCatalog.items(for: .motorcycle, powertrain: .gasoline).contains { $0.key == "chain" })

        let track = MaintenanceCatalog.items(for: .car, powertrain: .gasoline, traits: [.track], region: "US")
        let fluid = track.first { $0.key == "brakeFluid" }
        XCTAssertEqual(fluid?.months, 6)
        XCTAssertEqual(fluid?.trigger, .trackDay)

        let collector = MaintenanceCatalog.items(for: .car, powertrain: .gasoline, year: 1967, traits: [.collector], region: "US")
        XCTAssertTrue(collector.contains { $0.key == "exercise" && $0.isCore })
        XCTAssertEqual(collector.first { $0.key == "tires" }?.isCore, true)

        let boat = MaintenanceCatalog.items(for: .boat, powertrain: .outboard)
        XCTAssertTrue(boat.contains { $0.key == "commission" && $0.isCore })
    }

    func testChangingSetupAddsJobsAndKeepsEditedIntervals() {
        let store = makeStore()
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2012, make: "VW", model: "GTI", reading: 80_000))
        let oil = (car.tasks ?? []).first { $0.catalogKey == "oil" }!
        store.update(oil, name: "Oil and filter", distance: 5_000, months: 6, notes: "LiquiMoly 5W-40, 4.6 qt")
        store.setProfile(car, traits: [.track], drive: nil)
        XCTAssertTrue(car.enabledTasks.contains { $0.catalogKey == "trackPrep" })
        XCTAssertEqual(oil.intervalDistance, 5_000)
        let fluid = (car.tasks ?? []).first { $0.catalogKey == "brakeFluid" }
        XCTAssertEqual(fluid?.isEnabled, true)
        XCTAssertEqual(fluid?.intervalMonths, 6)
        XCTAssertEqual(fluid?.trigger, .trackDay)
    }

    // MARK: - Odometer

    func testRolloverKeepsTheTrueTotal() {
        let store = makeStore()
        var draft = NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 1967, make: "Ford", model: "Mustang", reading: 99_000)
        draft.lastDone = ["oil": .now.addingTimeInterval(-3 * 86_400)]
        let car = store.addVehicle(draft)
        store.recordOdometerChange(car, on: .now.addingTimeInterval(-86_400), lastShown: 99_999, newShown: 0, replaced: false)
        XCTAssertEqual(car.reading, 99_999, accuracy: 0.5)
        store.updateReading(car, to: 400)
        XCTAssertEqual(car.reading, 100_399, accuracy: 0.5)
        XCTAssertEqual(car.shownReading, 400, accuracy: 0.5)
        XCTAssertNotEqual(due(store, car, "oil")?.result.status, .overdue)
        XCTAssertFalse(store.isSuspiciousJump(450, for: car))
    }

    // MARK: - Mods and details

    func testModsStayOutOfRunningCosts() {
        let store = makeStore()
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2014, make: "Subaru", model: "WRX", reading: 60_000))
        var mod = GarageStore.ServiceDraft()
        mod.kind = .mod
        mod.details.parts = [EntryPart(name: "Coilovers", brand: "BC Racing", number: "F-15-BR", quantity: 1, price: 1_100), EntryPart()]
        mod.cost = 1_100
        mod.isDIY = true
        let entry = store.log(mod, for: car)
        XCTAssertEqual(entry.title, "BC Racing Coilovers · F-15-BR")
        XCTAssertEqual(entry.details.parts.count, 1)
        XCTAssertTrue(entry.coveredTaskIDs.isEmpty)

        var oil = GarageStore.ServiceDraft()
        oil.title = "Oil change"
        oil.cost = 80
        oil.details.specs = [EntrySpec(name: "Iron (oil analysis)", value: "12", unit: "ppm")]
        store.log(oil, for: car)

        let insights = CostInsights.compute(vehicles: [car])
        XCTAssertEqual(insights.mods, 1_100)
        XCTAssertEqual(insights.diyShare, 0)
        XCTAssertTrue(insights.byJob.contains { $0.name == "Mods" })
        XCTAssertEqual(MeasurementsView.series(for: car).first?.points.first?.value, 12)

        store.setRemoved(entry, on: .now)
        XCTAssertNotNil(entry.details.removedOn)
        let record = RecordBuilder.record(for: car, store: store, showCosts: true, includeReceipts: false)
        XCTAssertTrue(record.rows.contains { $0.detail.contains("Modification, removed") && $0.detail.contains("F-15-BR") })
    }

    func testEventsStayOffTheServiceRecord() {
        let store = makeStore()
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2014, make: "Porsche", model: "Cayman", reading: 30_000))
        store.logEvent(.trackDay, on: .now, for: car)
        let record = RecordBuilder.record(for: car, store: store, showCosts: true, includeReceipts: false)
        XCTAssertTrue(record.rows.isEmpty)
        XCTAssertTrue(CSVExport.csv(for: [car]).contains("Track day"))
    }

    func testProfileKeepsTraitsFromANewerBuild() {
        let json = #"{"traitsRaw":["track","rallycross"],"odometerChanges":[]}"#
        var profile = VehicleProfile.decode(json)!
        XCTAssertEqual(profile.traits, [.track])
        profile.traits = [.track, .collector]
        XCTAssertTrue(profile.traitsRaw.contains("rallycross"))
        XCTAssertTrue(profile.traitsRaw.contains("collector"))
    }

    // MARK: - Import

    func testExtraColumnsLandInNotesAndSameDayJobsAtDifferentPricesStay() {
        let file = """
        Date,Odometer,Work,Cost,Part #,Oil weight
        2024-03-02,41200,Brake pads,180,HB453G,
        2024-03-02,41200,Brake pads,160,HB454F,
        2024-04-10,42100,Oil change,60,,5W-30
        """
        let result = ServiceImport.parse(file, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(result.foldedHeaders, ["Part #", "Oil weight"])
        XCTAssertEqual(result.services.first?.notes, "Part #: HB453G")
        XCTAssertEqual(result.services.last?.notes, "Oil weight: 5W-30")

        let store = makeStore()
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2014, make: "Mazda", model: "3", reading: 40_000))
        XCTAssertEqual(store.importHistory(result.services, into: car).added, 3)
        XCTAssertEqual(store.importHistory(result.services, into: car).duplicates, 3)
    }

    // MARK: - Trip check

    func testTripCheckFindsWhatComesDueOnTheWay() {
        let store = makeStore()
        var draft = NewVehicle(kind: .truck, powertrain: .gasoline, meter: .miles, year: 2020, make: "Toyota", model: "Tacoma", reading: 40_000)
        draft.lastDone = ["oil": .now.addingTimeInterval(-10 * 86_400), "rotate": .now.addingTimeInterval(-10 * 86_400)]
        let truck = store.addVehicle(draft)
        let dues = store.dues(for: truck)
        XCTAssertFalse(TripCheckView.owed(dues, distance: 100, days: 3, current: truck.reading).contains { $0.catalogKey == "oil" })
        XCTAssertTrue(TripCheckView.owed(dues, distance: 8_000, days: 14, current: truck.reading).contains { $0.catalogKey == "oil" })
    }

    // MARK: - Formatting

    func testIntervalText() {
        XCTAssertEqual(Format.interval(distance: 7_500, months: 12, meter: .miles), "Every 7,500 mi or 1 year")
        XCTAssertEqual(Format.interval(distance: 0, months: 0, meter: .miles, trigger: .trackDay), "Every track day")
        XCTAssertEqual(Format.interval(distance: 0, months: 6, meter: .miles, trigger: .trackDay), "Every 6 months and every track day")
        XCTAssertEqual(Format.interval(distance: 150, months: 12, meter: .hours, auxName: "Generator"), "Every 150 generator hrs or 1 year")
    }
}
