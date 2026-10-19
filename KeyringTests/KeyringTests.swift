import CoreData
import UIKit
import XCTest
@testable import Keyring

final class DueEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func input(distance: Double = 7_500, months: Int = 12, lastDaysAgo: Double? = 100, lastReading: Double? = 40_000, current: Double = 43_000, pace: Double = 33) -> DueInput {
        DueInput(
            intervalDistance: distance,
            intervalMonths: months,
            lastDate: lastDaysAgo.map { now.addingTimeInterval(-$0 * 86_400) },
            lastReading: lastReading,
            currentReading: current,
            dailyUse: pace,
            meter: .miles
        )
    }

    func testDistanceComesFirstWhenDrivingALot() {
        let result = DueEngine.evaluate(input(), now: now, calendar: calendar)
        // 4,500 miles left at 33 a day is ~136 days, before the 12-month date.
        XCTAssertEqual(result.status, .ok)
        XCTAssertTrue(result.dateIsEstimated)
        XCTAssertEqual(result.dueReading, 47_500)
        let days = result.dueDate!.timeIntervalSince(now) / 86_400
        XCTAssertEqual(days, 4_500 / 33, accuracy: 1)
    }

    func testCalendarComesFirstWhenParked() {
        let result = DueEngine.evaluate(input(pace: 1), now: now, calendar: calendar)
        XCTAssertFalse(result.dateIsEstimated)
    }

    func testOverdueByDistance() {
        let result = DueEngine.evaluate(input(current: 48_000), now: now, calendar: calendar)
        XCTAssertEqual(result.status, .overdue)
        XCTAssertGreaterThan(result.progress, 1)
    }

    func testOverdueByTime() {
        let result = DueEngine.evaluate(input(lastDaysAgo: 400, current: 40_100, pace: 0.2), now: now, calendar: calendar)
        XCTAssertEqual(result.status, .overdue)
    }

    func testDueSoonWithinThirtyDays() {
        let result = DueEngine.evaluate(input(lastDaysAgo: 350, current: 40_100, pace: 0.2), now: now, calendar: calendar)
        XCTAssertEqual(result.status, .dueSoon)
    }

    func testNoRecordWhenNothingKnown() {
        let result = DueEngine.evaluate(input(lastDaysAgo: nil, lastReading: nil), now: now, calendar: calendar)
        XCTAssertEqual(result.status, .noRecord)
    }

    func testTimeOnlyJobOnHourMeterIgnoresDistanceWhenNoMeter() {
        var value = input(distance: 100, months: 12, lastReading: nil)
        value.meter = .none
        let result = DueEngine.evaluate(value, now: now, calendar: calendar)
        XCTAssertFalse(result.dateIsEstimated)
        XCTAssertNil(result.dueReading)
    }

    func testFAACalendarMonthsRunToTheEndOfTheMonth() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let signed = utc.date(from: DateComponents(year: 2026, month: 3, day: 3))!
        let april = utc.date(from: DateComponents(year: 2027, month: 3, day: 20))!
        let value = DueInput(intervalDistance: 0, intervalMonths: 12, lastDate: signed, lastReading: nil,
                             currentReading: 0, dailyUse: 0, meter: .hours, calendarMonths: true)
        let result = DueEngine.evaluate(value, now: april, calendar: utc)
        let due = utc.dateComponents([.year, .month, .day], from: result.dueDate!)
        XCTAssertEqual([due.year, due.month, due.day], [2027, 3, 31])
        XCTAssertEqual(result.status, .dueSoon)
        XCTAssertEqual(DueEngine.evaluate(value, now: utc.date(from: DateComponents(year: 2027, month: 4, day: 1))!, calendar: utc).status, .overdue)
        XCTAssertTrue(MaintenanceCatalog.usesCalendarMonths(key: "annual", kind: .aircraft))
        XCTAssertFalse(MaintenanceCatalog.usesCalendarMonths(key: "annual", kind: .golfCart))
    }

    func testDailyUseNeedsTwoWeeksOfSpread() {
        let points = [(now.addingTimeInterval(-5 * 86_400), 100.0), (now, 400.0)]
        XCTAssertEqual(DueEngine.dailyUse(readings: points, fallback: 33, now: now), 33)
        let longer = [(now.addingTimeInterval(-30 * 86_400), 100.0), (now, 400.0)]
        XCTAssertEqual(DueEngine.dailyUse(readings: longer, fallback: 33, now: now), 10, accuracy: 0.01)
    }
}

final class CatalogTests: XCTestCase {
    func testEveryKindHasACoreSchedule() {
        for kind in VehicleKind.allCases {
            for powertrain in kind.powertrainChoices {
                let items = MaintenanceCatalog.items(for: kind, powertrain: powertrain)
                XCTAssertFalse(items.filter(\.isCore).isEmpty, "\(kind) \(powertrain) has no core jobs")
                XCTAssertEqual(Set(items.map(\.key)).count, items.count, "\(kind) \(powertrain) repeats a key")
                for item in items where item.key != "wash" {
                    XCTAssertTrue(item.miles != nil || item.hours != nil || item.months != nil, "\(item.key) has no interval")
                }
            }
        }
    }

    func testWashIsOnTheRoadScheduleWithoutAnInterval() {
        let car = MaintenanceCatalog.items(for: .car, powertrain: .gasoline)
        let wash = car.first { $0.key == "wash" }
        XCTAssertEqual(wash?.isCore, true)
        XCTAssertNil(wash?.months)
        XCTAssertTrue(MaintenanceCatalog.items(for: .motorcycle, powertrain: .electric).contains { $0.key == "wash" })
        XCTAssertFalse(MaintenanceCatalog.items(for: .aircraft, powertrain: .piston).contains { $0.key == "wash" })
        let status = DueEngine.evaluate(DueInput(intervalDistance: 0, intervalMonths: 0, lastDate: nil, lastReading: nil,
                                                 currentReading: 0, dailyUse: 0, meter: .miles, calendarMonths: false)).status
        XCTAssertEqual(status, .ok)
    }

    func testHourMeterKindsGetHourIntervals() {
        let boat = MaintenanceCatalog.items(for: .boat, powertrain: .outboard)
        XCTAssertTrue(boat.contains { $0.hours != nil })
        let plane = MaintenanceCatalog.items(for: .aircraft, powertrain: .piston)
        XCTAssertTrue(plane.contains { $0.key == "annual" })
    }

    func testKilometersRoundToSensibleFigures() {
        XCTAssertEqual(MeterUnit.kilometers.fromCatalogMiles(7_500), 12_000)
        XCTAssertEqual(MeterUnit.kilometers.fromCatalogMiles(5_000), 8_000)
        XCTAssertEqual(MeterUnit.hours.fromCatalogMiles(100), 100)
    }

    /// A missing SF Symbol renders as nothing, silently. Every symbol the
    /// catalogs name must exist on iOS 17.
    func testEverySymbolExists() {
        var symbols = Set(VehicleKind.allCases.map(\.symbol))
        for kind in VehicleKind.allCases {
            for powertrain in kind.powertrainChoices {
                symbols.formUnion(MaintenanceCatalog.items(for: kind, powertrain: powertrain).map(\.symbol))
                symbols.formUnion(UpgradeCatalog.upgrades(for: kind, powertrain: powertrain).map(\.symbol))
            }
        }
        symbols.formUnion(VehicleKind.allCases.flatMap { ServiceFinder.services(kind: $0, make: "Ford", us: true).map(\.symbol) })
        symbols.formUnion(ProFeature.allCases.map(\.symbol))
        symbols.formUnion([Club.Kind.club, .forum, .subreddit, .organization].map(\.symbol))
        let missing = symbols.filter { UIImage(systemName: $0) == nil }.sorted()
        XCTAssertEqual(missing, [], "Missing SF Symbols: \(missing)")
    }

    func testClubsResolveForCommonVehicles() {
        let tacoma = ClubDirectory.clubs(kind: .truck, make: "Toyota", model: "Tacoma")
        XCTAssertEqual(tacoma.first?.name, "Tacoma World")
        XCTAssertTrue(ClubDirectory.clubs(kind: .aircraft, make: "Cessna", model: "172").contains { $0.name == "AOPA" })
        XCTAssertTrue(ClubDirectory.clubs(kind: .car, make: "Mercedes-Benz", model: nil).contains { $0.name == "MBWorld" })
        for kind in VehicleKind.allCases {
            XCTAssertFalse(ClubDirectory.byKind(kind).isEmpty, "\(kind) has no clubs")
        }
    }

    func testUpgradesForEveryKind() {
        for kind in VehicleKind.allCases {
            XCTAssertFalse(UpgradeCatalog.upgrades(for: kind, powertrain: kind.defaultPowertrain).isEmpty, "\(kind) has no upgrades")
        }
    }
}

final class ModelTests: XCTestCase {
    /// CloudKit mirroring rejects a model with a required attribute, a
    /// relationship without an inverse, or a unique constraint.
    func testModelIsCloudKitCompatible() {
        for entity in KeyringModel.model.entities {
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty, "\(entity.name!) has a uniqueness constraint")
            for (name, attribute) in entity.attributesByName {
                XCTAssertTrue(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name!).\(name) is required with no default")
            }
            for (name, relationship) in entity.relationshipsByName {
                XCTAssertTrue(relationship.isOptional, "\(entity.name!).\(name) is required")
                XCTAssertNotNil(relationship.inverseRelationship, "\(entity.name!).\(name) has no inverse")
            }
        }
    }
}

@MainActor
final class GarageStoreTests: XCTestCase {
    private func makeStore() -> GarageStore {
        GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
    }

    func testAddingAVehicleBuildsItsSchedule() {
        let store = makeStore()
        var draft = NewVehicle(kind: .truck, powertrain: .gasoline, meter: .miles, year: 2019, make: "Toyota", model: "Tacoma", reading: 40_000)
        draft.lastDone = ["oil": Date.now.addingTimeInterval(-10 * 86_400)]
        let vehicle = store.addVehicle(draft)
        XCTAssertFalse(vehicle.enabledTasks.isEmpty)
        let oil = store.dues(for: vehicle).first { $0.catalogKey == "oil" }
        XCTAssertEqual(oil?.lastReading, 40_000)
        XCTAssertNotEqual(oil?.result.status, .noRecord)
        XCTAssertEqual(store.ownedVehicleCount, 1)
    }

    func testWashIsAddedOnceToVehiclesSetUpBeforeIt() {
        let store = makeStore()
        let vehicle = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2020, make: "Ford", model: "Escape", reading: 30_000))
        let washes = { Array(vehicle.tasks ?? []).filter { $0.catalogKey == "wash" && !$0.isDeleted } }
        // A vehicle from an older build has no wash task.
        washes().forEach { store.context.delete($0) }
        store.save()
        XCTAssertTrue(washes().isEmpty)

        store.backfillCatalogJobs()
        XCTAssertEqual(washes().count, 1)
        store.backfillCatalogJobs()
        XCTAssertEqual(washes().count, 1)

        // A copy from the owner's second device: the newer, unlogged one goes.
        let original = washes()[0]
        store.makeTask(from: MaintenanceCatalog.wash, for: vehicle, createdAt: .now.addingTimeInterval(60))
        store.save()
        XCTAssertEqual(washes().count, 2)
        store.backfillCatalogJobs()
        XCTAssertEqual(washes().map(\.objectID), [original.objectID])

        // Switched off stays off.
        store.remove(original)
        store.backfillCatalogJobs()
        XCTAssertEqual(washes().count, 1)
        XCTAssertFalse(washes()[0].isEnabled)

        // Planes don't get one.
        let plane = store.addVehicle(NewVehicle(kind: .aircraft, powertrain: .piston, meter: .hours, year: 1978, make: "Cessna", model: "172", reading: 4_000))
        store.backfillCatalogJobs()
        XCTAssertFalse((plane.tasks ?? []).contains { $0.catalogKey == "wash" })
    }

    func testLoggingRestartsTheCountdown() {
        let store = makeStore()
        let vehicle = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 50_000))
        let oil = vehicle.enabledTasks.first { $0.catalogKey == "oil" }!
        XCTAssertEqual(store.dues(for: vehicle).first { $0.catalogKey == "oil" }?.result.status, .noRecord)
        var draft = GarageStore.ServiceDraft()
        draft.reading = 50_200
        draft.taskIDs = [oil.id!]
        draft.cost = 59.99
        let entry = store.log(draft, for: vehicle)
        XCTAssertEqual(entry.title, "Oil and filter")
        XCTAssertEqual(vehicle.reading, 50_200)
        let due = store.dues(for: vehicle).first { $0.catalogKey == "oil" }!
        XCTAssertEqual(due.result.status, .ok)
        XCTAssertEqual(due.result.dueReading, 57_700)
    }

    /// The 1.0 builds on TestFlight wrote stores without entry kinds. Those
    /// logs have to open with the current model, untouched.
    func testAStoreFromTheFirstModelOpensWithTheCurrentOne() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = KeyringModel.firstRelease
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: old)
        let url = directory.appendingPathComponent("private.sqlite")
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let vehicle = NSManagedObject(entity: old.entitiesByName["Vehicle"]!, insertInto: context)
        vehicle.setValue(UUID(), forKey: "id")
        vehicle.setValue("Civic", forKey: "model")
        let entry = NSManagedObject(entity: old.entitiesByName["ServiceEntry"]!, insertInto: context)
        entry.setValue(UUID(), forKey: "id")
        entry.setValue("Oil and filter", forKey: "title")
        entry.setValue(vehicle, forKey: "vehicle")
        try context.save()
        try coordinator.remove(coordinator.persistentStores[0])

        let persistence = Persistence(cloudKit: false, directory: directory)
        XCTAssertFalse(persistence.isStandingIn)
        let entries = try persistence.container.viewContext.fetch(NSFetchRequest<ServiceEntry>(entityName: "ServiceEntry"))
        XCTAssertEqual(entries.map(\.title), ["Oil and filter"])
        XCTAssertEqual(entries.first?.kind, .service)
        XCTAssertEqual(entries.first?.vehicle?.model, "Civic")
    }

    func testStoresMoveOutOfTheAppGroupIntact() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("group")
        let here = root.appendingPathComponent("support")
        let old = Persistence(cloudKit: false, directory: legacy)
        GarageStore(persistence: old).addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2019, make: "Honda", model: "Civic", reading: 50_000))
        let coordinator = old.container.persistentStoreCoordinator
        for store in coordinator.persistentStores { try coordinator.remove(store) }

        XCTAssertEqual(Persistence.adoptStores(from: legacy, into: here), here)
        for name in Persistence.storeNames {
            XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.appendingPathComponent(name).path))
        }
        let moved = Persistence(cloudKit: false, directory: here)
        XCTAssertFalse(moved.isStandingIn)
        let vehicles = try moved.container.viewContext.fetch(NSFetchRequest<Vehicle>(entityName: "Vehicle"))
        XCTAssertEqual(vehicles.map(\.model), ["Civic"])
        XCTAssertEqual(Persistence.adoptStores(from: legacy, into: here), here, "Nothing left to move")
    }

    func testRepairsAndRecallFixesAreKeptApart() {
        let store = makeStore()
        let vehicle = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2019, make: "Honda", model: "Civic", reading: 50_000))
        var repair = GarageStore.ServiceDraft()
        repair.kind = .repair
        repair.cost = 640
        let entry = store.log(repair, for: vehicle)
        XCTAssertEqual(entry.kind, .repair)
        XCTAssertEqual(entry.title, "Repair")
        XCTAssertNil(entry.recallCampaign)

        var oil = GarageStore.ServiceDraft()
        oil.taskIDs = [vehicle.enabledTasks.first { $0.catalogKey == "oil" }!.id!]
        oil.cost = 90
        store.log(oil, for: vehicle)
        let insights = CostInsights.compute(vehicles: [vehicle])
        XCTAssertEqual(insights.repairs, 640)
        XCTAssertEqual(insights.lastTwelveMonths, 730)

        let airbag = Recall(campaign: "24V001000", component: "AIR BAGS", summary: "", consequence: "", remedy: "", reported: nil, parkIt: true, parkOutside: false)
        let pump = Recall(campaign: "24V002000", component: "FUEL PUMP", summary: "", consequence: "", remedy: "", reported: nil, parkIt: false, parkOutside: false)
        XCTAssertEqual(store.openRecalls([airbag, pump], for: vehicle).count, 2)
        var fix = GarageStore.ServiceDraft()
        fix.kind = .recall
        fix.recallCampaign = airbag.campaign
        fix.title = "Recall: air bags"
        store.log(fix, for: vehicle)
        XCTAssertEqual(store.openRecalls([airbag, pump], for: vehicle).map(\.campaign), [pump.campaign])
        XCTAssertTrue(CSVExport.csv(for: [vehicle]).contains(",Recall,Recall: air bags,"))
    }

    func testOnlyRecallsMissingFromTheLastCheckAreNew() {
        let a = Recall(campaign: "A", component: "X", summary: "", consequence: "", remedy: "", reported: nil, parkIt: false, parkOutside: false)
        let b = Recall(campaign: "B", component: "Y", summary: "", consequence: "", remedy: "", reported: nil, parkIt: false, parkOutside: false)
        XCTAssertTrue(RecallWatcher.newRecalls([a, b], since: nil).isEmpty, "the first look sets a baseline")
        XCTAssertEqual(RecallWatcher.newRecalls([a, b], since: [a]).map(\.campaign), ["B"])
        XCTAssertTrue(RecallWatcher.newRecalls([a], since: [a, b]).isEmpty)
    }

    func testLoggingWithoutAReadingUsesTodaysMeter() {
        let store = makeStore()
        let vehicle = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 50_000))
        let oil = vehicle.enabledTasks.first { $0.catalogKey == "oil" }!
        var old = GarageStore.ServiceDraft()
        old.date = .now.addingTimeInterval(-400 * 86_400)
        old.reading = 30_000
        old.taskIDs = [oil.id!]
        store.log(old, for: vehicle)
        XCTAssertEqual(store.dues(for: vehicle).first { $0.catalogKey == "oil" }?.result.status, .overdue)
        var today = GarageStore.ServiceDraft()
        today.taskIDs = [oil.id!]
        store.log(today, for: vehicle)
        let due = store.dues(for: vehicle).first { $0.catalogKey == "oil" }!
        XCTAssertEqual(due.lastReading, 50_000)
        XCTAssertEqual(due.result.status, .ok)
    }

    func testGeneratorCountsOnItsOwnMeter() {
        let store = makeStore()
        var draft = NewVehicle()
        draft.kind = .rv
        draft.reading = 20_000
        draft.auxMeterName = "Generator"
        let rv = store.addVehicle(draft)
        let generator = rv.enabledTasks.first { $0.catalogKey == "generator" }!
        XCTAssertTrue(generator.usesAuxMeter)
        XCTAssertEqual(generator.intervalDistance, 150)
        var log = GarageStore.ServiceDraft()
        log.taskIDs = [generator.id!]
        log.auxReading = 100
        store.log(log, for: rv)
        store.updateAuxReading(rv, to: 260)
        let due = store.dues(for: rv).first { $0.catalogKey == "generator" }!
        XCTAssertEqual(due.meter, .hours)
        XCTAssertEqual(due.result.status, .overdue)
        XCTAssertEqual(due.dueLine(), "Overdue by 10 hrs")
        XCTAssertEqual(rv.reading, 20_000)
        store.setAuxMeter(rv, name: nil)
        XCTAssertFalse(rv.enabledTasks.first { $0.catalogKey == "generator" }!.usesAuxMeter)
    }

    func testSellingKeepsTheDateAndPriceUntilRestored() {
        let store = makeStore()
        let car = store.addVehicle(NewVehicle())
        store.markSold(car, on: .now, price: 12_500)
        XCTAssertTrue(car.isRetired)
        XCTAssertEqual(car.soldPrice, 12_500)
        XCTAssertEqual(store.ownedVehicleCount, 0)
        store.retire(car, false)
        XCTAssertNil(car.soldDate)
        XCTAssertEqual(car.soldPrice, 0)
    }

    func testCorrectingATypoLowersTheMeter() {
        let store = makeStore()
        let vehicle = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 52_000))
        XCTAssertTrue(store.isSuspiciousJump(520_000, for: vehicle))
        XCTAssertFalse(store.isSuspiciousJump(52_300, for: vehicle))
        store.updateReading(vehicle, to: 520_000)
        XCTAssertEqual(vehicle.reading, 520_000)
        store.correctReading(vehicle, to: 52_100)
        XCTAssertEqual(vehicle.reading, 52_100)
        XCTAssertFalse((vehicle.readings ?? []).contains { $0.value > 52_100 })
    }

    func testSwitchingToKilometersConvertsEverything() {
        let store = makeStore()
        let vehicle = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 10_000))
        let oil = vehicle.enabledTasks.first { $0.catalogKey == "oil" }!
        let miles = oil.intervalDistance
        store.changeMeter(vehicle, to: .kilometers)
        XCTAssertEqual(vehicle.meter, .kilometers)
        XCTAssertEqual(vehicle.reading, 16_093.44, accuracy: 0.01)
        XCTAssertEqual(oil.intervalDistance, (miles * 1.609344 / 100).rounded() * 100, accuracy: 500)
        store.changeMeter(vehicle, to: .hours)
        XCTAssertEqual(vehicle.reading, 0)
    }

    func testIntervalWording() {
        XCTAssertEqual(Format.interval(distance: 7_500, months: 12, meter: .miles), "Every 7,500 mi or 1 year")
        XCTAssertEqual(Format.interval(distance: 0, months: 12, meter: .miles), "Every year")
        XCTAssertEqual(Format.interval(distance: 0, months: 6, meter: .miles), "Every 6 months")
        XCTAssertEqual(Format.interval(distance: 0, months: 0, meter: .miles), "As needed")
        XCTAssertEqual(Format.reading(1_234.5, .hours), "1,234.5 hrs")
        XCTAssertEqual(Format.reading(1_234, .hours), "1,234 hrs")
    }

    func testAsNeededJobShowsWhenItWasLastDone() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func wash(lastDate: Date?) -> TaskDue {
            TaskDue(
                id: NSManagedObjectID(), taskID: UUID(), name: "Wash", symbol: "bubbles.and.sparkles", catalogKey: "wash",
                result: DueResult(status: .ok, dueDate: nil, dueReading: nil, progress: 0, dateIsEstimated: false),
                lastDate: lastDate, lastReading: nil, intervalDistance: 0, intervalMonths: 0
            )
        }
        XCTAssertFalse(wash(lastDate: nil).hasInterval)
        XCTAssertEqual(wash(lastDate: nil).dueLine(now: now), "Not logged yet")
        XCTAssertEqual(wash(lastDate: now.addingTimeInterval(-5 * 86_400)).dueLine(now: now), "Last done 5 days ago")
    }

    func testCSVExportEscapesAndBlocksFormulas() {
        XCTAssertEqual(CSVExport.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExport.escape("=SUM(A1)"), "'=SUM(A1)")
        XCTAssertEqual(CSVExport.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        let store = makeStore()
        let vehicle = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Ford", model: "F-150", reading: 1_000))
        var draft = GarageStore.ServiceDraft()
        draft.title = "Brakes, front"
        draft.cost = 300
        store.log(draft, for: vehicle)
        let csv = CSVExport.csv(for: [vehicle])
        XCTAssertTrue(csv.contains("\"Brakes, front\""))
        XCTAssertTrue(csv.contains("300.00"))
    }

    func testServiceRecordRenders() {
        let store = makeStore()
        DemoSeed.seed(into: store)
        let truck = store.vehicles.first!
        let record = RecordBuilder.record(for: truck, store: store, showCosts: true, includeReceipts: true)
        XCTAssertFalse(record.rows.isEmpty)
        let pdf = ServiceRecordPDF.render(record)
        XCTAssertGreaterThan(pdf.count, 2_000)
        XCTAssertTrue(String(decoding: pdf.prefix(5), as: UTF8.self).hasPrefix("%PDF"))
    }

    func testDemoSeedCoversEveryCardKind() {
        let store = makeStore()
        DemoSeed.seed(into: store)
        XCTAssertEqual(store.vehicles.count, 5)
        XCTAssertTrue(store.vehicles.allSatisfy { !$0.sortedEntries.isEmpty })
    }
}

@MainActor
final class ReminderPlanTests: XCTestCase {
    func testWeekAheadDayOfAndOneOverdueRoundup() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func due(_ status: DueStatus, days: Double, name: String) -> TaskDue {
            TaskDue(
                id: NSManagedObjectID(), taskID: UUID(), name: name, symbol: "drop.fill", catalogKey: nil,
                result: DueResult(status: status, dueDate: now.addingTimeInterval(days * 86_400), dueReading: nil, progress: 0.5, dateIsEstimated: false),
                lastDate: nil, lastReading: nil, intervalDistance: 0, intervalMonths: 12
            )
        }
        let plan = ReminderScheduler.plan(dues: [
            ("Tacoma", "1", due(.ok, days: 30, name: "Oil and filter")),
            ("Boat", "2", due(.overdue, days: -3, name: "Impeller")),
            ("RAV4", "3", due(.overdue, days: -10, name: "Tire rotation")),
        ], now: now, hour: 9)
        XCTAssertEqual(plan.filter { $0.id.hasPrefix("week-") }.count, 1)
        XCTAssertEqual(plan.filter { $0.id.hasPrefix("day-") }.count, 1)
        XCTAssertEqual(plan.filter { $0.id == "weekend-overdue" }.count, 1)
        XCTAssertEqual(plan.first { $0.id == "weekend-overdue" }?.title, "2 jobs are overdue")
    }
}

final class ImportTests: XCTestCase {
    private let us = Locale(identifier: "en_US")

    func testFuellyStyleSplitsFillUpsFromServices() {
        let fuel = """
        car_name,model,mpg,odometer,miles,gallons,price,city_percentage,fuelup_date,date_added,tags,notes,missed_fuelup,partial_fuelup
        Tacoma,Tacoma,19.2,41200,288,15,3.49,50,2024-03-02,2024-03-02 10:00,,,0,0
        Tacoma,Tacoma,18.7,41510,310,16.6,3.59,50,2024-03-15,2024-03-15 09:00,,,0,0
        """
        let result = ServiceImport.parse(fuel, locale: us)
        XCTAssertEqual(result.source, .fuelly)
        XCTAssertEqual(result.fillUps.count, 2)
        XCTAssertTrue(result.services.isEmpty)
        XCTAssertEqual(result.fillUps.last?.reading, 41_510)
    }

    func testStackedSectionsSkipExpensesAndReadEuropeanFigures() {
        let file = """
        ##Refuelling
        Date;Odometer;Liters;Total
        12/03/2024;45.120;40,2;71,50
        ##Service
        Date;Odometer;Service;Total cost;Place;Notes
        01/02/2024;44.900;Oil change, tire rotation;89,90;Midas;synthetic
        05/01/2024;44.100;Brake pads;240,00;;
        ##Expense
        Date;Odometer;Expense;Total
        06/01/2024;44.200;Insurance;600,00
        """
        let result = ServiceImport.parse(file, locale: Locale(identifier: "en_GB"))
        XCTAssertEqual(result.fillUps.count, 1)
        XCTAssertEqual(result.services.count, 2)
        XCTAssertEqual(result.skippedExpenses, 1)
        let oil = result.services.last!
        XCTAssertEqual(oil.reading, 44_900)
        XCTAssertEqual(oil.cost, 89.90, accuracy: 0.001)
        XCTAssertEqual(oil.shop, "Midas")
        // Day first: 1 February, not January 2.
        XCTAssertEqual(Calendar.current.component(.month, from: oil.date), 2)
        XCTAssertEqual(ServiceImport.catalogKeys(for: oil.work), ["rotate", "oil"])
    }

    func testOwnExportRoundTrips() {
        let file = """
        Vehicle,Year,Make,Model,Date,Odometer,Unit,Type,Work,Covered jobs,Cost,Shop,DIY,Notes,Logged by
        Tacoma,2019,Toyota,Tacoma,2025-06-01,52000,mi,Repair,Water pump,,420.00,Dave's,,"Leaking, replaced",Dana
        """
        let row = ServiceImport.parse(file, locale: us).services[0]
        XCTAssertEqual(row.kind, .repair)
        XCTAssertEqual(row.unit, .miles)
        XCTAssertEqual(row.notes, "Leaking, replaced")
        XCTAssertEqual(row.loggedBy, "Dana")
        XCTAssertEqual(row.make, "Toyota")
    }

    func testSpecificJobsWinOverEngineOil() {
        XCTAssertEqual(ServiceImport.catalogKeys(for: "Lower unit gear oil"), ["gearOil", "diffs"])
        XCTAssertEqual(ServiceImport.catalogKeys(for: "Transmission oil"), ["transmission", "transmissionFluid", "hydraulic"])
        XCTAssertEqual(ServiceImport.catalogKeys(for: "Fixed oil leak"), [])
        XCTAssertEqual(ServiceImport.catalogKeys(for: "LOF"), ["oil"])
    }

    @MainActor
    func testWidgetLinksOpenTheVehicle() {
        let id = UUID()
        let router = NotificationRouter()
        router.open(WidgetSnapshot.url(forVehicle: id.uuidString)!)
        XCTAssertEqual(router.destination, .init(vehicleID: id, showsRecalls: false))
        router.open(URL(fileURLWithPath: "/tmp/log.csv"))
        XCTAssertEqual(router.importFile?.lastPathComponent, "log.csv")
    }

    func testNumbers() {
        XCTAssertEqual(ServiceImport.number("$1,234.50"), 1_234.5)
        XCTAssertEqual(ServiceImport.number("1.234,50 €"), 1_234.5)
        XCTAssertEqual(ServiceImport.number("45,000"), 45_000)
        XCTAssertEqual(ServiceImport.number("12,5"), 12.5)
        XCTAssertNil(ServiceImport.number("n/a"))
    }

    @MainActor
    func testImportingTwiceAddsNothingAndRestartsTheSchedule() {
        let store = GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
        var draft = NewVehicle()
        draft.reading = 30_000
        let vehicle = store.addVehicle(draft)
        let file = """
        Date,Odometer,Service,Cost
        2025-01-10,28000,Oil change,59.99
        """
        let rows = ServiceImport.parse(file, locale: us).services
        let first = store.importHistory(rows, into: vehicle)
        XCTAssertEqual(first.added, 1)
        XCTAssertEqual(first.jobsUpdated, 1)
        XCTAssertEqual(store.importHistory(rows, into: vehicle).duplicates, 1)
        let oil = store.dues(for: vehicle).first { $0.catalogKey == "oil" }!
        XCTAssertEqual(oil.lastReading, 28_000)
    }
}

final class ParserTests: XCTestCase {
    func testReceiptParsing() {
        let lines = [
            "LES SCHWAB TIRE CENTER",
            "1234 NE 136th Ave",
            "(360) 555-0101",
            "Invoice 88123   10/02/2026",
            "Mileage In: 48,210",
            "Brake pads front     189.00",
            "Labor                 98.40",
            "Subtotal             287.40",
            "Tax                   25.00",
            "TOTAL               $312.40",
        ]
        let fields = ReceiptReader.parse(lines: lines, now: Date(timeIntervalSince1970: 1_792_000_000))
        XCTAssertEqual(fields.total, 312.40)
        XCTAssertEqual(fields.reading, 48_210)
        XCTAssertEqual(fields.shop, "Les Schwab Tire Center")
        XCTAssertNotNil(fields.date)
    }

    func testVINValidation() {
        XCTAssertEqual(NHTSAClient.normalizedVIN("3tmcz5an2km198431"), "3TMCZ5AN2KM198431")
        XCTAssertNil(NHTSAClient.normalizedVIN("3TMCZ5AN2KM19843"))
        XCTAssertNil(NHTSAClient.normalizedVIN("3TMCZ5AN2KMO98431"))
    }

    func testVINDecodeParsing() {
        let json = #"{"Results":[{"ModelYear":"2019","Make":"TOYOTA","Model":"Tacoma","Trim":"SR5","VehicleType":"TRUCK","BodyClass":"Pickup","FuelTypePrimary":"Gasoline","ElectrificationLevel":"","DisplacementL":"3.5","EngineCylinders":"6","DriveType":"4WD/4-Wheel Drive/4x4"}]}"#
        let decoded = NHTSAClient.parseDecode(Data(json.utf8))
        XCTAssertEqual(decoded?.year, 2019)
        XCTAssertEqual(decoded?.make, "Toyota")
        XCTAssertEqual(decoded?.kind, .truck)
        XCTAssertEqual(decoded?.powertrain, .gasoline)
        XCTAssertEqual(decoded?.summary, "3.5L V6 · 4WD · Pickup")
    }

    func testRecallParsing() {
        let json = #"{"Count":1,"results":[{"NHTSACampaignNumber":"20V682000","Component":"FUEL SYSTEM, GASOLINE:DELIVERY:FUEL PUMP","Summary":"Pump may fail.","Consequence":"Stall.","Remedy":"Replace.","ReportReceivedDate":"04/11/2020","parkIt":false,"parkOutSide":false}]}"#
        let recalls = NHTSAClient.parseRecalls(Data(json.utf8))
        XCTAssertEqual(recalls.count, 1)
        XCTAssertEqual(recalls[0].componentTitle, "Fuel System, Gasoline")
        let month = Calendar(identifier: .gregorian).component(.month, from: recalls[0].reported!)
        XCTAssertEqual(month, 11)
    }

    func testValueLinksCarryTheVehicle() {
        XCTAssertEqual(ValueSource.slug("Mercedes-Benz"), "mercedes-benz")
        XCTAssertEqual(ValueSource.slug("F-150"), "f-150")
        XCTAssertEqual(ValueSource.slug("  "), nil)
    }

    func testAmazonLinks() {
        let url = AmazonLinks.search("2019 Toyota Tacoma oil filter", region: "US")
        XCTAssertEqual(url.host(), "www.amazon.com")
        XCTAssertEqual(AmazonLinks.search("wipers", region: "CA").host(), "www.amazon.ca")
        XCTAssertTrue(url.absoluteString.contains("k=2019%20Toyota%20Tacoma%20oil%20filter"))
    }
}

@MainActor
final class AuditRoundThreeTests: XCTestCase {
    private func makeStore() -> GarageStore {
        GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
    }

    func testStorageFreezesThePaceAndPausesReminders() {
        let store = makeStore()
        var draft = NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2018, make: "Mazda", model: "MX-5", reading: 30_000)
        draft.yearlyUse = 12_000
        draft.lastDone = ["oil": Date.now.addingTimeInterval(-30 * 86_400)]
        let car = store.addVehicle(draft)
        XCTAssertEqual(store.typicalDailyUse(for: car), 12_000 / 365, accuracy: 0.01)
        let before = store.dues(for: car).first { $0.catalogKey == "oil" }!
        XCTAssertTrue(before.result.dateIsEstimated)

        let back = Calendar.current.date(byAdding: .month, value: 5, to: .now)!
        store.store(car, until: back)
        XCTAssertNotNil(car.storedSince)
        let stored = store.dues(for: car).first { $0.catalogKey == "oil" }!
        // Only the calendar runs while it's stored: a year from the last change.
        XCTAssertFalse(stored.result.dateIsEstimated)

        let plan = ReminderScheduler.plan(dues: [], now: .now, hour: 9, returns: [(car.displayName, car.id!.uuidString, back)])
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].id, "storage-\(car.id!.uuidString)")

        store.returnFromStorage(car, reading: 30_400)
        XCTAssertNil(car.storedSince)
        XCTAssertNil(car.storedUntil)
        XCTAssertEqual(car.reading, 30_400)
    }

    func testPowertrainFromMakeAndModel() {
        XCTAssertEqual(Makes.inferredPowertrain(make: "Tesla", model: "Model 3"), .electric)
        XCTAssertEqual(Makes.inferredPowertrain(make: "Toyota", model: "RAV4 Prime"), .plugInHybrid)
        XCTAssertEqual(Makes.inferredPowertrain(make: "Jeep", model: "Wrangler 4xe"), .plugInHybrid)
        XCTAssertEqual(Makes.inferredPowertrain(make: "Ford", model: "F-150 Lightning"), .electric)
        XCTAssertEqual(Makes.inferredPowertrain(make: "Ford", model: "Mustang Mach-E"), .electric)
        XCTAssertEqual(Makes.inferredPowertrain(make: "Volkswagen", model: "ID.4"), .electric)
        XCTAssertEqual(Makes.inferredPowertrain(make: "Toyota", model: "Camry", trim: "Hybrid XLE"), .hybrid)
        XCTAssertNil(Makes.inferredPowertrain(make: "Toyota", model: "Tacoma"))
        XCTAssertNil(Makes.inferredPowertrain(make: "Chevrolet", model: "Silverado"))
    }

    func testMakesFollowTheRegion() {
        XCTAssertEqual(Makes.common(for: .car, region: "GB").first, "Ford")
        XCTAssertTrue(Makes.common(for: .car, region: "GB").contains("Vauxhall"))
        XCTAssertFalse(Makes.common(for: .car, region: "US").contains("Vauxhall"))
        XCTAssertEqual(Makes.common(for: .boat, region: "CA"), Makes.common(for: .boat, region: "US"))
    }

    func testWinterTiresAndClassicSchedule() {
        let canada = MaintenanceCatalog.items(for: .car, powertrain: .gasoline, year: 2020, region: "CA")
        XCTAssertEqual(canada.first { $0.key == "winterTires" }?.isCore, true)
        let us = MaintenanceCatalog.items(for: .car, powertrain: .gasoline, year: 2020, region: "US")
        XCTAssertEqual(us.first { $0.key == "winterTires" }?.isCore, false)

        let classic = MaintenanceCatalog.items(for: .car, powertrain: .gasoline, year: 1967, region: "US")
        XCTAssertEqual(classic.first { $0.key == "oil" }?.miles, 3_000)
        XCTAssertEqual(classic.first { $0.key == "oil" }?.months, 6)
        XCTAssertNotNil(classic.first { $0.key == "chassisLube" })
        XCTAssertNil(us.first { $0.key == "chassisLube" })
        XCTAssertEqual(us.first { $0.key == "oil" }?.miles, 7_500)
    }

    func testPlugInHybridGetsElectricJobs() {
        let keys = Set(MaintenanceCatalog.items(for: .suv, powertrain: .plugInHybrid).map(\.key))
        XCTAssertTrue(keys.isSuperset(of: ["oil", "brakes", "charger", "plugs"]))
    }

    func testPowertrainChangeSwitchesOffUntouchedJobs() {
        let store = makeStore()
        var draft = NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2022, make: "Hyundai", model: "Kona", reading: 10_000)
        draft.lastDone = ["oil": .now.addingTimeInterval(-60 * 86_400)]
        let car = store.addVehicle(draft)
        store.addCatalogItems(MaintenanceCatalog.items(for: .car, powertrain: .gasoline).filter { $0.key == "plugs" }, to: car)
        car.powertrain = .electric
        store.addCatalogItems(MaintenanceCatalog.items(for: .car, powertrain: .electric).filter(\.isCore), to: car)
        store.switchOffInapplicableTasks(on: car)
        let enabled = Set(car.enabledTasks.compactMap(\.catalogKey))
        XCTAssertFalse(enabled.contains("plugs"), "never done, doesn't apply")
        XCTAssertTrue(enabled.contains("oil"), "has history, stays")
        XCTAssertTrue(enabled.contains("rotate"))
    }

    func testMetricDetailText() {
        XCTAssertEqual(CatalogItem.metric("Most call for 3,000 to 6,000 miles."), "Most call for 5,000 to 10,000 km.")
        XCTAssertEqual(CatalogItem.metric("Around 100,000 miles."), "Around 161,000 km.")
        XCTAssertEqual(CatalogItem.metric("Every 300 to 600 miles and after rain."), "Every 500 to 950 km and after rain.")
        XCTAssertEqual(CatalogItem.metric("No units here."), "No units here.")
    }

    func testRegionalValueSources() {
        let store = makeStore()
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .kilometers, year: 2019, make: "Honda", model: "Civic"))
        let canada = ValueSource.sources(for: car, region: "CA").map(\.name)
        XCTAssertEqual(canada.first, "Canadian Black Book")
        XCTAssertFalse(canada.contains("Kelley Blue Book"))
        XCTAssertEqual(ValueSource.sources(for: car, region: "CA").last?.url.host(), "www.ebay.ca")
        XCTAssertEqual(ValueSource.sources(for: car, region: "US").first?.name, "Kelley Blue Book")
    }

    /// White is the only tint with an outline, carries ink, and survives the
    /// widget's hex round trip.
    func testWhiteTintIsOutlined() {
        XCTAssertTrue(VehicleTint.white.isLight)
        XCTAssertNotNil(VehicleTint.white.outline)
        XCTAssertEqual(VehicleTint.allCases.filter { $0.outline != nil }, [.white])
        XCTAssertEqual(VehicleTint.matching(hex: VehicleTint.white.hex), .white)
        XCTAssertEqual(Set(VehicleTint.allCases.map(\.hex)).count, VehicleTint.allCases.count)
    }

    /// Paths checked live against each site on 2026-10-17. Edmunds 404s on
    /// its old `appraisal.html` path.
    func testUSValueSourceURLs() {
        let store = makeStore()
        let truck = store.addVehicle(NewVehicle(kind: .truck, powertrain: .gasoline, meter: .miles, year: 2018, make: "Ford", model: "F-150"))
        let urls = Dictionary(uniqueKeysWithValues: ValueSource.sources(for: truck, region: "US").map { ($0.name, $0.url.absoluteString) })
        XCTAssertEqual(urls["Edmunds"], "https://www.edmunds.com/ford/f-150/2018/appraisal-value/")
        XCTAssertEqual(urls["Kelley Blue Book"], "https://www.kbb.com/ford/f-150/2018/?intent=trade-in-sell")
        let bare = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 0, make: "Ford", model: ""))
        let bareURLs = Dictionary(uniqueKeysWithValues: ValueSource.sources(for: bare, region: "US").map { ($0.name, $0.url.absoluteString) })
        XCTAssertEqual(bareURLs["Edmunds"], "https://www.edmunds.com/appraisal/")
    }

    /// Map searches are worded per kind; booking sites are US road only.
    func testServiceNearbyFitsTheVehicle() {
        let truck = ServiceFinder.services(kind: .truck, make: "Toyota", us: true)
        XCTAssertEqual(Set(truck.map(\.group)), [.shops, .mobile, .detailing])
        XCTAssertTrue(truck.contains { $0.title == "Toyota dealer service" })
        XCTAssertEqual(truck.first { $0.title == "Mobile mechanics" }?.url.absoluteString, "https://maps.apple.com/?q=mobile%20mechanic")
        XCTAssertFalse(ServiceFinder.services(kind: .truck, make: "Toyota", us: false).contains { $0.title == "YourMechanic" })
        let boat = ServiceFinder.services(kind: .boat, make: nil, us: true)
        XCTAssertTrue(boat.contains { $0.url.absoluteString.contains("marine%20mechanic") })
        XCTAssertFalse(boat.contains { $0.title == "Wrench" })
        for kind in VehicleKind.allCases {
            XCTAssertFalse(ServiceFinder.services(kind: kind, make: nil, us: true).isEmpty, "\(kind) has no services")
        }
    }

    /// Road vehicles get the three enthusiast sections; EVs skip engine
    /// mods, and lowering is for cars, leveling for trucks.
    func testRoadUpgradesFitTheVehicle() {
        func titles(_ kind: VehicleKind, _ powertrain: Powertrain) -> Set<String> {
            Set(UpgradeCatalog.upgrades(for: kind, powertrain: powertrain).map(\.title))
        }
        let sections = Set(UpgradeCatalog.upgrades(for: .car, powertrain: .gasoline).map(\.category))
        XCTAssertEqual(sections, [.performance, .handling, .detailing])
        XCTAssertTrue(titles(.car, .gasoline).isSuperset(of: ["Cold air intake", "Lowering springs", "Performance tires", "Clay bar kit"]))
        XCTAssertFalse(titles(.car, .electric).contains("Cold air intake"))
        XCTAssertFalse(titles(.car, .electric).contains("Brake pads and rotors"))
        XCTAssertTrue(titles(.car, .electric).contains("Shocks and struts"))
        XCTAssertTrue(titles(.truck, .gasoline).isSuperset(of: ["Leveling kit", "All-terrain tires"]))
        XCTAssertFalse(titles(.truck, .gasoline).contains("Lowering springs"))
    }

    func testMixedUnitsInsights() {
        let store = makeStore()
        let miles = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Ford", model: "Focus", reading: 10_000))
        let km = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .kilometers, make: "Kia", model: "Soul", reading: 10_000))
        for (vehicle, first, second) in [(miles, 10_000.0, 11_000.0), (km, 10_000.0, 11_609.344)] {
            var a = GarageStore.ServiceDraft(); a.date = .now.addingTimeInterval(-90 * 86_400); a.reading = first; a.title = "Oil"; a.cost = 50
            store.log(a, for: vehicle)
            var b = GarageStore.ServiceDraft(); b.reading = second; b.title = "Oil"; b.cost = 50
            store.log(b, for: vehicle)
        }
        let insights = CostInsights.compute(vehicles: [miles, km])
        let perUnit = try! XCTUnwrap(insights.costPerDistance)
        if insights.distanceUnit == "mi" {
            XCTAssertEqual(perUnit, 200.0 / 2_000, accuracy: 0.001)
        } else {
            XCTAssertEqual(perUnit, 200.0 / 3_218.688, accuracy: 0.001)
        }
    }
}

@MainActor
final class FuelTests: XCTestCase {
    private func makeStore() -> GarageStore {
        GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
    }

    func testPumpDisplayWithLabels() {
        let lines = ["Shell", "TOTAL SALE", "$ 45.17", "GALLONS", "12.345", "PRICE PER GALLON", "3.659", "REGULAR"]
        let fields = PumpReader.parse(lines: lines, unit: .gallons)
        XCTAssertEqual(fields.total, 45.17)
        XCTAssertEqual(fields.volume, 12.345)
        XCTAssertEqual(fields.unitPrice, 3.659)
        XCTAssertEqual(fields.grade, .regular)
        XCTAssertEqual(fields.station, "Shell")
    }

    func testPumpFiguresFoundByMultiplyingOut() {
        // An unlabeled display read in an odd order, with a pump number and a clock.
        let lines = ["PUMP 7", "10:42", "3.899", "52.64", "13.501"]
        let fields = PumpReader.parse(lines: lines, unit: .gallons)
        XCTAssertEqual(fields.total, 52.64)
        XCTAssertEqual(fields.volume, 13.501)
        XCTAssertEqual(fields.unitPrice, 3.899)
    }

    func testPumpReceipt() {
        let lines = ["COSTCO GASOLINE", "1234 MAIN ST", "10/12/2026 07:31", "PUMP 04", "UNLEADED", "GALLONS 11.204", "PRICE/GAL $3.459", "FUEL SALE $38.75", "VISA ****1234", "THANK YOU"]
        let now = DateComponents(calendar: .current, year: 2026, month: 10, day: 17).date!
        let fields = PumpReader.parse(lines: lines, unit: .gallons, now: now)
        XCTAssertEqual(fields.volume, 11.204)
        XCTAssertEqual(fields.unitPrice, 3.459)
        XCTAssertEqual(fields.total, 38.75)
        XCTAssertEqual(fields.grade, .regular)
        XCTAssertEqual(fields.station, "Costco")
        XCTAssertNotNil(fields.date)
    }

    func testCanadianPumpInCentsPerLiter() {
        let lines = ["$ 72.34", "LITRES 45.240", "159.9 ¢/L"]
        let fields = PumpReader.parse(lines: lines, unit: .liters)
        XCTAssertEqual(fields.volume, 45.24)
        XCTAssertEqual(fields.unitPrice!, 1.599, accuracy: 0.0001)
        XCTAssertEqual(fields.total, 72.34)
    }

    func testTwoFiguresGiveTheThird() {
        let fields = PumpReader.completed(PumpFields(volume: 10, unitPrice: 3.5))
        XCTAssertEqual(fields.total, 35)
        XCTAssertEqual(PumpReader.completed(PumpFields(volume: 10, total: 35)).unitPrice, 3.5)
        XCTAssertEqual(PumpReader.completed(PumpFields(unitPrice: 3.5, total: 35)).volume, 10)
    }

    func testGradeNeedsToBeTheOnlyOne() {
        XCTAssertNil(PumpReader.grade(in: ["REGULAR", "PLUS", "PREMIUM"]))
        XCTAssertEqual(PumpReader.grade(in: ["SUPER UNLEADED"]), .premium)
        XCTAssertEqual(PumpReader.grade(in: ["Diesel #2"]), .diesel)
    }

    func testOdometerPickIgnoresTripClockAndRange() {
        let lines = ["10:41", "72°F", "TRIP A 312.4", "Range 288 mi", "48562", "mi"]
        XCTAssertEqual(OdometerReader.pick(lines: lines, last: 48_210, meter: .miles), 48_562)
        // Nothing plausible beside the last reading: leave the field for the owner.
        XCTAssertNil(OdometerReader.pick(lines: ["120", "55"], last: 48_210, meter: .miles))
        XCTAssertEqual(OdometerReader.pick(lines: ["ODO 48,562 mi"], last: 0, meter: .miles), 48_562)
        XCTAssertEqual(OdometerReader.pick(lines: ["60", "48562i", "10:41", "72°F", "TRIP A 312.4"], last: 48_210, meter: .miles), 48_562)
        XCTAssertEqual(OdometerReader.pick(lines: ["60", "485620i", "72°F", "10:41", "TRIP A 312.4"], last: 48_210, meter: .miles), 48_562)
        XCTAssertEqual(OdometerReader.pick(lines: ["1,204.6 hrs"], last: 1_190, meter: .hours), 1_204.6)
    }

    func testEconomyCountsTopUpsAndSkipsTheFirstFill() {
        let economy = FuelEconomy(meter: .miles, unit: .gallons)
        let day: (Int) -> Date = { Date(timeIntervalSince1970: 1_790_000_000 + Double($0) * 86_400) }
        let gal = FuelVolumeUnit.litersPerGallon
        let fills = [
            FuelEconomy.Fill(id: UUID(), date: day(0), reading: 10_000, liters: 12 * gal, partial: false),
            FuelEconomy.Fill(id: UUID(), date: day(5), reading: 10_150, liters: 3 * gal, partial: true),
            FuelEconomy.Fill(id: UUID(), date: day(9), reading: 10_300, liters: 9 * gal, partial: false),
            FuelEconomy.Fill(id: UUID(), date: day(15), reading: 10_600, liters: 10 * gal, partial: false),
        ]
        let values = economy.values(fills)
        XCTAssertNil(values[fills[0].id])
        XCTAssertNil(values[fills[1].id])
        XCTAssertEqual(values[fills[2].id]!, 300 / 12, accuracy: 0.01)
        XCTAssertEqual(values[fills[3].id]!, 30, accuracy: 0.01)
        XCTAssertEqual(economy.average(fills)!, 600 / 22, accuracy: 0.01)
        XCTAssertEqual(economy.format(25), "25.0 mpg")
        XCTAssertEqual(FuelEconomy(meter: .kilometers, unit: .liters).label, "L/100 km")
        XCTAssertEqual(FuelEconomy(meter: .hours, unit: .gallons).label, "gal/hr")
    }

    func testLoggingAFillUpStoresLitersAndMovesTheOdometer() {
        let store = makeStore()
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 50_000))
        var draft = GarageStore.FuelDraft()
        draft.unit = .gallons
        draft.reading = 50_320
        draft.volume = 10
        draft.unitPrice = 3.5
        draft.grade = .regular
        draft.station = "Costco"
        let entry = store.logFuel(draft, for: car)
        XCTAssertEqual(entry.kind, .fuel)
        XCTAssertEqual(entry.cost, 35)
        XCTAssertEqual(entry.fuelVolume, 10 * FuelVolumeUnit.litersPerGallon, accuracy: 0.0001)
        XCTAssertEqual(FuelVolumeUnit.gallons.fromPerLiter(entry.fuelUnitPrice), 3.5, accuracy: 0.0001)
        XCTAssertEqual(car.reading, 50_320)
        XCTAssertEqual(car.fuelEntries.count, 1)
        XCTAssertTrue(car.serviceEntries.isEmpty)
        XCTAssertEqual(store.recentStations(for: car), ["Costco"])
        // A fill-up never counts as a maintenance job done.
        XCTAssertTrue(store.dues(for: car).allSatisfy { $0.lastDate == nil })
    }
}

final class FuelImportTests: XCTestCase {
    private let us = Locale(identifier: "en_US")

    @MainActor
    func testFuellyFillUpsArriveWithGallonsAndPrice() {
        let store = GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
        let truck = store.addVehicle(NewVehicle(kind: .truck, powertrain: .gasoline, meter: .miles, make: "Toyota", model: "Tacoma", reading: 41_000))
        let fuel = """
        car_name,model,mpg,odometer,miles,gallons,price,city_percentage,fuelup_date,date_added,tags,notes,missed_fuelup,partial_fuelup
        Tacoma,Tacoma,19.2,41200,288,15,3.49,50,2024-03-02,2024-03-02 10:00,,,0,0
        Tacoma,Tacoma,18.7,41510,310,16.6,3.59,50,2024-03-15,2024-03-15 09:00,,,0,1
        """
        let rows = ServiceImport.parse(fuel, locale: us).fillUps
        XCTAssertEqual(rows.first?.unitPrice, 3.49)
        XCTAssertEqual(rows.first?.volumeUnit, .gallons)
        XCTAssertEqual(rows.last?.partial, true)
        let outcome = store.importHistory(rows, into: truck)
        XCTAssertEqual(outcome.fillUps, 2)
        XCTAssertEqual(truck.fuelEntries.count, 2)
        let first = truck.fuelEntries.last!
        XCTAssertEqual(first.cost, 52.35, accuracy: 0.001)
        XCTAssertEqual(FuelVolumeUnit.gallons.fromLiters(first.fuelVolume), 15, accuracy: 0.0001)
        XCTAssertEqual(store.importHistory(rows, into: truck).duplicates, 2)
        XCTAssertEqual(truck.reading, 41_510)
    }

    @MainActor
    func testOwnExportKeepsFillUps() {
        let store = GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, make: "Honda", model: "Civic", reading: 50_000))
        var draft = GarageStore.FuelDraft()
        draft.unit = .gallons
        draft.reading = 50_300
        draft.volume = 10.5
        draft.unitPrice = 3.659
        draft.grade = .premium
        draft.partial = true
        store.logFuel(draft, for: car)
        let csv = CSVExport.csv(for: [car])
        let rows = ServiceImport.parse(csv, locale: us).fillUps
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].kind, .fuel)
        XCTAssertEqual(rows[0].grade, .premium)
        XCTAssertEqual(rows[0].partial, true)
        XCTAssertEqual(rows[0].unitPrice, 3.659)
        XCTAssertEqual(rows[0].cost, 38.42, accuracy: 0.001)
    }
}

final class FieldReaderTests: XCTestCase {
    private func line(_ text: String, _ height: CGFloat) -> FieldReader.Line { FieldReader.Line(text: text, height: height) }

    func testPlatePicksTheBigNumberOverTheStateAndSlogan() {
        let lines = [line("WASHINGTON", 0.06), line("BXY 4821", 0.22), line("Evergreen State", 0.04), line("www.dol.wa.gov", 0.03)]
        XCTAssertEqual(FieldReader.best(in: lines, for: .plate), "BXY 4821")
        XCTAssertNil(FieldReader.best(in: [line("CALIFORNIA", 0.1), line("dmv.ca.gov", 0.03)], for: .plate))
        XCTAssertEqual(FieldReader.tapped("7abc123", for: .plate), "7ABC123")
    }

    func testVINAmountAndReading() {
        XCTAssertEqual(FieldReader.best(in: [line("VIN 1HGCM82633A004352", 0.05)], for: .vin), "1HGCM82633A004352")
        XCTAssertEqual(FieldReader.best(in: [line("Trade-in range", 0.04), line("$24,150 - $26,900", 0.04), line("Private party $28,400.00", 0.04)], for: .amount), "28400")
        XCTAssertEqual(FieldReader.best(in: [line("ODO 48,562 mi", 0.1)], for: .reading(last: 48_000, meter: .miles)), "48562")
        XCTAssertNil(FieldReader.best(in: [line("Oil 0W-20", 0.1)], for: .text))
        XCTAssertEqual(FieldReader.tapped(" 0W-20 full synthetic ", for: .text), "0W-20 full synthetic")
    }
}

@MainActor
final class RecallMatchTests: XCTestCase {
    private let pump = Recall(
        campaign: "20V682000", component: "FUEL SYSTEM, GASOLINE", summary: "", consequence: "",
        remedy: "Dealers will replace the fuel pump free of charge. Toyota's numbers for this recall are 20TB02 and 20TA02 for Toyota vehicles and J16/J06.",
        reported: nil, parkIt: false, parkOutside: false
    )

    func testMakerCodesAndNHTSAForms() {
        XCTAssertEqual(pump.makerCodes, ["20TB02", "20TA02", "J16", "J06"])
        XCTAssertEqual(pump.nhtsaForms, ["20V682000", "20V-682", "20V682"])
    }

    func testMentionsNeedsRecallContextForShortCodes() {
        XCTAssertTrue(RecallMatcher.mentions(pump, in: "Performed campaign 20TA02 fuel pump"))
        XCTAssertTrue(RecallMatcher.mentions(pump, in: "NHTSA 20V-682 complete"))
        XCTAssertTrue(RecallMatcher.mentions(pump, in: "SAFETY RECALL J16 COMPLETED"))
        XCTAssertFalse(RecallMatcher.mentions(pump, in: "Part J16 wiper insert"))
        XCTAssertFalse(RecallMatcher.mentions(pump, in: "Invoice 120TA021"))
    }

    func testNotesOrADealerMarkCloseTheRecall() {
        let store = GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))
        let car = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2019, make: "Toyota", model: "Tacoma", reading: 40_000))
        let other = Recall(campaign: "19V244000", component: "AIR BAGS", summary: "", consequence: "", remedy: "", reported: nil, parkIt: false, parkOutside: false)
        XCTAssertEqual(store.openRecalls([pump, other], for: car).count, 2)

        var visit = GarageStore.ServiceDraft()
        visit.title = "Oil change"
        visit.notes = "Dealer also did safety recall 20TA02."
        store.log(visit, for: car)
        XCTAssertEqual(store.openRecalls([pump, other], for: car).map(\.campaign), [other.campaign])

        store.markRecallFixedByDealer(other, for: car)
        XCTAssertTrue(store.openRecalls([pump, other], for: car).isEmpty)
        let marked = car.entries?.first { $0.recallCampaign == other.campaign }
        XCTAssertEqual(marked?.kind, .recall)
        XCTAssertEqual(marked?.shop, "Dealer")
    }
}

final class VINRecallCheckTests: XCTestCase {
    private func recall(_ campaign: String) -> Recall {
        Recall(campaign: campaign, component: "FUEL SYSTEM", summary: "", consequence: "", remedy: "", reported: nil, parkIt: false, parkOutside: false)
    }

    func testCampaignKeysMatchAcrossForms() {
        XCTAssertEqual(VINRecallCheck.key("25V455000"), "25V455")
        XCTAssertEqual(VINRecallCheck.key("25v-455"), "25V455")
        XCTAssertEqual(VINRecallCheck.key("26V1230"), "26V1230")
    }

    func testOnlyOpenAndNewerRecallsShow() throws {
        let listed = [recall("25V455000"), recall("24V100000"), recall("23V010000")]
        let json = #"{"state":"ok","vin":"1FM5K8LC8MGC14943","count":2,"recalls":[{"maker":"25S75","nhtsa":"25V455","status":"Recall Incomplete","summary":"IT IS POSSIBLE"},{"maker":"26S14","nhtsa":"26V117","status":"Recall Incomplete, remedy not yet available","summary":"THE REAR CAMERA"}]}"#
        let check = try XCTUnwrap(VINRecallCheck.parse(json, vin: "1fm5k8lc8mgc14943", known: listed))
        XCTAssertTrue(check.covered)
        XCTAssertEqual(listed.filter(check.shows).map(\.campaign), ["25V455000"])
        // Open on the VIN but not on the model's list yet.
        let extra = check.unlisted(in: listed)
        XCTAssertEqual(extra.map(\.campaign), ["26V117"])
        XCTAssertEqual(extra.first?.summary, "The rear camera")
        // Listed after the check: shown until the next one.
        XCTAssertTrue(check.shows(recall("26V900000")))
    }

    func testOtherVINAndNoDataResults() {
        XCTAssertNil(VINRecallCheck.parse(#"{"state":"ok","vin":"1HGCM82633A004352","count":0,"recalls":[]}"#, vin: "1FM5K8LC8MGC14943", known: []))
        let none = VINRecallCheck.parse(#"{"state":"none"}"#, vin: "1FM5K8LC8MGC14943", known: [recall("25V455000")])
        XCTAssertEqual(none?.covered, false)
        XCTAssertEqual(none.map { [recall("25V455000")].filter($0.shows).count }, 1)
        let clear = VINRecallCheck.parse(#"{"state":"ok","count":0,"recalls":[]}"#, vin: "1FM5K8LC8MGC14943", known: [recall("25V455000")])
        XCTAssertEqual(clear.map { [recall("25V455000")].filter($0.shows).count }, 0)
    }
}

final class VehicleSectionOrderTests: XCTestCase {
    func testEmptyIsDefault() {
        XCTAssertEqual(VehicleSection.order(from: ""), VehicleSection.defaultOrder)
    }

    func testRoundTripsAndFillsMissing() {
        let order = VehicleSection.order(from: "details,bogus,history,details")
        XCTAssertEqual(order, [.details, .history, .explore, .maintenance, .facts])
        XCTAssertEqual(VehicleSection.order(from: VehicleSection.stored(order)), order)
    }
}
