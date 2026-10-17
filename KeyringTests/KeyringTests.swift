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
        let url = AmazonLinks.search("2019 Toyota Tacoma oil filter")
        XCTAssertEqual(url.host(), "www.amazon.com")
        XCTAssertTrue(url.absoluteString.contains("k=2019%20Toyota%20Tacoma%20oil%20filter"))
    }
}
