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
                for item in items {
                    XCTAssertTrue(item.miles != nil || item.hours != nil || item.months != nil, "\(item.key) has no interval")
                }
            }
        }
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

    func testCommonsParsingKeepsOnlyMatchingFiles() {
        let json = #"{"query":{"pages":{"1":{"title":"File:2019 Toyota Tacoma SR5.jpg","index":1,"imageinfo":[{"thumburl":"https://upload.wikimedia.org/a.jpg","descriptionurl":"https://commons.wikimedia.org/wiki/File:A.jpg","extmetadata":{"Artist":{"value":"<a href=\"x\">Someone</a>"},"LicenseShortName":{"value":"CC BY-SA 4.0"}}}]},"2":{"title":"File:Sunset from a car.jpg","index":2,"imageinfo":[{"thumburl":"https://upload.wikimedia.org/b.jpg","descriptionurl":"https://commons.wikimedia.org/wiki/File:B.jpg"}]}}}}"#
        let photos = CommunityPhotos.parseCommons(Data(json.utf8), mustMention: ["Toyota", "Tacoma"])
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos[0].credit, "Photo: Someone · CC BY-SA 4.0")
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

    func testCarPlayAdapterOnlyWhereItFits() {
        let store = makeStore()
        let tesla = store.addVehicle(NewVehicle(kind: .car, powertrain: .electric, meter: .miles, year: 2023, make: "Tesla", model: "Model Y"))
        let classic = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 1972, make: "Ford", model: "Bronco"))
        let modern = store.addVehicle(NewVehicle(kind: .car, powertrain: .gasoline, meter: .miles, year: 2019, make: "Honda", model: "Accord"))
        XCTAssertFalse(UpgradeCatalog.upgrades(for: tesla).contains { $0.title.contains("CarPlay") })
        XCTAssertFalse(UpgradeCatalog.upgrades(for: classic).contains { $0.title.contains("CarPlay") })
        XCTAssertTrue(UpgradeCatalog.upgrades(for: modern).contains { $0.title.contains("CarPlay") })
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
