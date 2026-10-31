import CoreData
import Foundation
import os
import UIKit

/// One job on one vehicle, with when it comes due.
struct TaskDue: Identifiable, Hashable {
    static func == (lhs: TaskDue, rhs: TaskDue) -> Bool { lhs.id == rhs.id && lhs.result == rhs.result }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: NSManagedObjectID
    let taskID: UUID
    let name: String
    let symbol: String
    let catalogKey: String?
    let result: DueResult
    let lastDate: Date?
    let lastReading: Double?
    let intervalDistance: Double
    let intervalMonths: Int
    /// The meter this job counts on and where it stands: the main one, or a
    /// second hour meter such as an RV's generator.
    var meter: MeterUnit = .miles
    var currentReading: Double = 0
    var usesAuxMeter = false
    /// The whichever-first interval on the second meter, and that meter.
    var secondInterval: Double = 0
    var secondMeter: MeterUnit = .hours
    /// The event that also brings it due, and the pending one if any.
    var trigger: UsageEvent?
    var pendingEvent: Date?

    /// False for an "as needed" job such as a wash, which only tracks when it
    /// was last done.
    var hasInterval: Bool { intervalMonths > 0 || (intervalDistance > 0 && meter.hasReading) || secondInterval > 0 }

    /// Overdue, due soon, then up to date by date, with jobs that have no
    /// record yet last so they never push a real date down the list.
    private static func rank(_ status: DueStatus) -> Int {
        switch status {
        case .overdue: 0
        case .dueSoon: 1
        case .ok: 2
        case .noRecord: 3
        }
    }

    static func ordering(_ lhs: TaskDue, _ rhs: TaskDue) -> Bool {
        if lhs.result.status != rhs.result.status { return rank(lhs.result.status) < rank(rhs.result.status) }
        switch (lhs.result.dueDate, rhs.result.dueDate) {
        case let (l?, r?): return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.name < rhs.name
        }
    }
}

/// What a new vehicle starts with.
struct NewVehicle: Equatable {
    var kind: VehicleKind = .car
    var powertrain: Powertrain = .gasoline
    var meter: MeterUnit = .miles
    var year: Int = 0
    var make = ""
    var model = ""
    var trim = ""
    var nickname = ""
    var vin = ""
    var plate = ""
    var reading: Double = 0
    /// A second meter's name ("Generator", "Track"), or empty for none.
    var auxMeterName = ""
    var auxMeter: MeterUnit = .hours
    var traits: Set<VehicleTrait> = []
    var drive: FinalDrive?
    /// How far it goes in a year, in its own unit. 0 = not given.
    var yearlyUse: Double = 0
    var photo: Data?
    var tint: VehicleTint?
    var purchaseDate: Date?
    var purchasePrice: Double = 0
    /// "When was the oil last changed?" from setup, keyed by catalog key.
    var lastDone: [String: Date] = [:]
}

/// The single door to the garage. Every add, log, edit and delete goes
/// through here, and each change republishes the widget and the reminders.
@MainActor
final class GarageStore: ObservableObject {
    static let shared = GarageStore(persistence: .shared)

    @Published private(set) var garages: [Garage] = []
    @Published private(set) var vehicles: [Vehicle] = []
    /// Bumped on every change so views holding managed objects redraw.
    @Published private(set) var revision = 0

    let persistence: Persistence
    private var observers: [Any] = []
    private let logger = Logger(subsystem: AppGroup.subsystem, category: "Garage")

    var context: NSManagedObjectContext { persistence.viewContext }

    init(persistence: Persistence) {
        self.persistence = persistence
        reload()
        backfillCatalogJobs()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: persistence.container.persistentStoreCoordinator, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
                self?.backfillCatalogJobs()
            }
        })
        observers.append(center.addObserver(forName: Persistence.storesDidReopen, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
                self?.backfillCatalogJobs()
            }
        })
    }

    // MARK: - Catalog backfill

    /// Core jobs added to the catalog after people had set up their vehicles.
    static let backfilledKeys: Set<String> = ["wash"]

    /// Adds each backfilled job once to vehicles in a garage this person owns,
    /// so the owner's device does it for everyone sharing the garage. A job
    /// switched off later keeps its task, so it is never added back.
    func backfillCatalogJobs() {
        var changed = false
        for vehicle in vehicles where !persistence.isShared(vehicle) {
            let existing = Set((vehicle.tasks ?? []).compactMap(\.catalogKey))
            let missing = Self.backfilledKeys.subtracting(existing)
            guard !missing.isEmpty else { continue }
            let items = vehicle.catalogItems
            for item in items where missing.contains(item.key) && item.isCore {
                makeTask(from: item, for: vehicle)
                changed = true
            }
        }
        if removeDuplicateBackfills() { changed = true }
        if changed { save() }
    }

    /// Two of the owner's devices can each add a job before they sync. Every
    /// device keeps the same one (the oldest, or the one with history) and
    /// deletes copies that were never logged.
    private func removeDuplicateBackfills() -> Bool {
        var removed = false
        for vehicle in vehicles {
            for key in Self.backfilledKeys {
                let copies = (vehicle.tasks ?? []).filter { $0.catalogKey == key && !$0.isDeleted }
                guard copies.count > 1 else { continue }
                let hasHistory = { (task: MaintenanceTask) in
                    let last = self.lastDone(for: task)
                    return last.date != nil || last.reading != nil
                }
                let ordered = copies.sorted {
                    let (l, r) = (hasHistory($0), hasHistory($1))
                    if l != r { return l }
                    let (ld, rd) = ($0.createdAt ?? .distantPast, $1.createdAt ?? .distantPast)
                    if ld != rd { return ld < rd }
                    return ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "")
                }
                for extra in ordered.dropFirst() where !hasHistory(extra) {
                    context.delete(extra)
                    removed = true
                }
            }
        }
        return removed
    }

    // MARK: - Reading

    func reload() {
        let request = NSFetchRequest<Garage>(entityName: "Garage")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        garages = (try? context.fetch(request)) ?? []
        let vehicleRequest = NSFetchRequest<Vehicle>(entityName: "Vehicle")
        vehicles = ((try? context.fetch(vehicleRequest)) ?? [])
            .filter { !$0.isRetired && !$0.isDeleted }
            .sorted(by: Vehicle.displayOrder)
        revision += 1
        publish()
    }

    var retiredVehicles: [Vehicle] {
        let request = NSFetchRequest<Vehicle>(entityName: "Vehicle")
        request.predicate = NSPredicate(format: "isRetired == YES")
        return ((try? context.fetch(request)) ?? []).sorted(by: Vehicle.displayOrder)
    }

    /// The garage this person created, which is the one they can share.
    var ownGarage: Garage? { garages.first { !persistence.isShared($0) } }

    /// Garages other people shared with this person.
    var joinedGarages: [Garage] { garages.filter { persistence.isShared($0) } }

    /// Vehicles counted against the free limit: only ones in a garage this
    /// person owns. A joined garage is the owner's to pay for.
    var ownedVehicleCount: Int {
        vehicles.filter { !persistence.isShared($0) }.count
    }

    func isShared(_ object: NSManagedObject) -> Bool { persistence.isShared(object) }

    @discardableResult
    func ensureOwnGarage() -> Garage {
        if let ownGarage { return ownGarage }
        let garage = Garage.make(in: context, name: "Our garage")
        context.assign(garage, to: persistence.privateStore)
        save()
        return garage
    }

    func vehicle(id: UUID?) -> Vehicle? {
        guard let id else { return nil }
        return vehicles.first { $0.id == id } ?? retiredVehicles.first { $0.id == id }
    }

    // MARK: - Due

    func dailyUse(for vehicle: Vehicle) -> Double {
        var points: [(date: Date, value: Double)] = vehicle.mainReadings.compactMap { reading in
            reading.date.map { ($0, reading.value) }
        }
        points += (vehicle.entries ?? []).compactMap { entry in
            guard entry.hasReading, let date = entry.date else { return nil }
            return (date, entry.reading)
        }
        if let date = vehicle.readingDate { points.append((date, vehicle.reading)) }
        return DueEngine.dailyUse(readings: points, fallback: typicalDailyUse(for: vehicle))
    }

    /// The kind's typical figure in this vehicle's own unit.
    func typicalDailyUse(for vehicle: Vehicle) -> Double {
        if vehicle.yearlyUse > 0 { return vehicle.yearlyUse / 365 }
        let miles = vehicle.kind.typicalDailyUse
        return vehicle.meter == .kilometers ? miles * 1.609344 : miles
    }

    /// Hours a day on the second meter. A generator runs about 100 hours a year.
    func auxDailyUse(for vehicle: Vehicle) -> Double {
        var points: [(date: Date, value: Double)] = vehicle.auxReadings.compactMap { reading in
            reading.date.map { ($0, reading.value) }
        }
        points += (vehicle.entries ?? []).compactMap { entry in
            guard entry.hasAuxReading, let date = entry.date else { return nil }
            return (date, entry.auxReading)
        }
        if let date = vehicle.auxReadingDate { points.append((date, vehicle.auxReading)) }
        return DueEngine.dailyUse(readings: points, fallback: 0.3)
    }

    /// The most recent time this job was done: a logged entry that covered it,
    /// or the "last done" the owner gave at setup, whichever is later.
    func lastDone(for task: MaintenanceTask, onAux: Bool? = nil) -> (date: Date?, reading: Double?) {
        let onAux = onAux ?? task.usesAuxMeter
        var date = task.baselineDate
        // The setup baseline is on the job's own meter only.
        var reading: Double? = task.baselineReading >= 0 && onAux == task.usesAuxMeter ? task.baselineReading : nil
        guard let id = task.id, let entries = task.vehicle?.entries else { return (date, reading) }
        let covering = entries.filter { $0.coveredTaskIDs.contains(id) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        if let latest = covering.first, let latestDate = latest.date, latestDate >= (date ?? .distantPast) {
            date = latestDate
            // No reading on the entry: the meter as it stood that day, never an
            // older visit's reading, which would leave the job overdue.
            if onAux {
                reading = latest.hasAuxReading ? latest.auxReading : task.vehicle.flatMap { self.auxReading(of: $0, on: latestDate) }
            } else {
                reading = latest.hasReading ? latest.reading : task.vehicle.flatMap { self.reading(of: $0, on: latestDate) }
            }
        }
        return (date, reading)
    }

    /// The highest reading known by the end of `date`, from meter updates and
    /// logged entries.
    func reading(of vehicle: Vehicle, on date: Date) -> Double? {
        let cutoff = Calendar.current.startOfDay(for: date).addingTimeInterval(86_400)
        var values = vehicle.mainReadings.compactMap { reading in
            reading.date.flatMap { $0 < cutoff ? reading.value : nil }
        }
        values += (vehicle.entries ?? []).compactMap { entry in
            guard entry.hasReading, let entryDate = entry.date, entryDate < cutoff else { return nil }
            return entry.reading
        }
        if let readingDate = vehicle.readingDate, readingDate < cutoff { values.append(vehicle.reading) }
        return values.max()
    }

    /// The same for the second hour meter.
    func auxReading(of vehicle: Vehicle, on date: Date) -> Double? {
        let cutoff = Calendar.current.startOfDay(for: date).addingTimeInterval(86_400)
        var values = vehicle.auxReadings.compactMap { reading in
            reading.date.flatMap { $0 < cutoff ? reading.value : nil }
        }
        values += (vehicle.entries ?? []).compactMap { entry in
            guard entry.hasAuxReading, let entryDate = entry.date, entryDate < cutoff else { return nil }
            return entry.auxReading
        }
        if let readingDate = vehicle.auxReadingDate, readingDate < cutoff { values.append(vehicle.auxReading) }
        return values.max()
    }

    func dues(for vehicle: Vehicle, now: Date = .now) -> [TaskDue] {
        // Stored, it isn't going anywhere: only the calendar moves.
        let stored = vehicle.storedSince != nil
        let pace = stored ? 0 : dailyUse(for: vehicle)
        let auxPace = vehicle.hasAuxMeter && !stored ? auxDailyUse(for: vehicle) : 0
        return vehicle.enabledTasks.compactMap { task -> TaskDue? in
            guard let id = task.id else { return nil }
            let last = lastDone(for: task)
            let onAux = task.usesAuxMeter && vehicle.hasAuxMeter
            let meter: MeterUnit = onAux ? vehicle.auxMeter : vehicle.meter
            let current = onAux ? vehicle.auxReading : vehicle.reading
            var results = [DueEngine.evaluate(DueInput(
                intervalDistance: task.intervalDistance,
                intervalMonths: Int(task.intervalMonths),
                lastDate: last.date,
                lastReading: last.reading,
                currentReading: current,
                dailyUse: onAux ? auxPace : pace,
                meter: meter,
                calendarMonths: MaintenanceCatalog.usesCalendarMonths(key: task.catalogKey, kind: vehicle.kind)
            ), now: now)]
            let second = task.secondInterval
            if second > 0 {
                let lastAux = lastDone(for: task, onAux: true)
                results.append(DueEngine.evaluate(DueInput(
                    intervalDistance: second, intervalMonths: 0, lastDate: lastAux.date, lastReading: lastAux.reading,
                    currentReading: vehicle.auxReading, dailyUse: auxPace, meter: vehicle.auxMeter
                ), now: now))
            }
            let pending = task.trigger.flatMap { pendingEvent($0, on: vehicle, after: last.date) }
            if let pending { results.append(DueEngine.triggered(by: pending, now: now)) }
            return TaskDue(
                id: task.objectID, taskID: id, name: task.displayName, symbol: task.displaySymbol,
                catalogKey: task.catalogKey, result: DueEngine.combine(results), lastDate: last.date, lastReading: last.reading,
                intervalDistance: task.intervalDistance, intervalMonths: Int(task.intervalMonths),
                meter: meter, currentReading: current, usesAuxMeter: onAux,
                secondInterval: second, secondMeter: vehicle.auxMeter,
                trigger: task.trigger, pendingEvent: pending
            )
        }
        .sorted(by: TaskDue.ordering)
    }

    /// The earliest event of this kind logged after the job was last done:
    /// past means it's owed now, future means it's owed by then.
    func pendingEvent(_ event: UsageEvent, on vehicle: Vehicle, after lastDone: Date?) -> Date? {
        let since = lastDone.map { Calendar.current.startOfDay(for: $0).addingTimeInterval(86_400) } ?? .distantPast
        return (vehicle.entries ?? [])
            .filter { $0.kind == .event && $0.details.event == event }
            .compactMap(\.date)
            .filter { $0 >= since }
            .min()
    }

    /// The worst known status on a vehicle and the next job, for its card.
    func headline(for vehicle: Vehicle) -> (status: DueStatus, urgentCount: Int, next: TaskDue?) {
        let dues = dues(for: vehicle)
        let known = dues.filter { $0.result.status != .noRecord }
        let status = known.first?.result.status ?? (dues.isEmpty ? .ok : .noRecord)
        return (status, known.filter { $0.result.status <= .dueSoon }.count, known.first)
    }

    // MARK: - Vehicles

    @discardableResult
    func addVehicle(_ draft: NewVehicle, to garage: Garage? = nil, now: Date = .now) -> Vehicle {
        let garage = garage ?? ensureOwnGarage()
        let vehicle = Vehicle(context: context)
        persistence.place(vehicle, beside: garage, in: context)
        vehicle.id = UUID()
        vehicle.createdAt = now
        vehicle.kind = draft.kind
        vehicle.powertrain = draft.powertrain
        vehicle.meter = draft.meter
        vehicle.year = Int16(clamping: draft.year)
        vehicle.make = draft.make.trimmed.nilIfEmpty
        vehicle.model = draft.model.trimmed.nilIfEmpty
        vehicle.trim = draft.trim.trimmed.nilIfEmpty
        vehicle.nickname = draft.nickname.trimmed.nilIfEmpty
        vehicle.vin = draft.vin.trimmed.uppercased().nilIfEmpty
        vehicle.plate = draft.plate.trimmed.uppercased().nilIfEmpty
        vehicle.reading = max(0, draft.reading)
        // The odometer is optional, so zero means it wasn't entered. Stored as a
        // reading, the first real one months later would read as a drive from
        // nothing: an absurd pace, and every job done since "overdue" by the whole odometer.
        let hasStartingReading = draft.meter.hasReading && draft.reading > 0
        vehicle.readingDate = hasStartingReading ? now : nil
        vehicle.auxMeterName = draft.auxMeterName.trimmed.nilIfEmpty
        vehicle.auxMeter = draft.auxMeter
        var profile = VehicleProfile()
        profile.traits = draft.traits
        profile.drive = draft.kind == .motorcycle ? draft.drive : nil
        vehicle.profile = profile
        vehicle.yearlyUse = draft.meter.hasReading ? max(0, draft.yearlyUse) : 0
        vehicle.photo = draft.photo
        vehicle.purchaseDate = draft.purchaseDate
        vehicle.purchasePrice = max(0, draft.purchasePrice)
        vehicle.tint = draft.tint ?? .defaultTint(for: draft.kind)
        vehicle.sortIndex = Int16(clamping: (garage.vehicles?.count ?? 0))
        vehicle.garage = garage
        if hasStartingReading {
            let reading = MeterReading(context: context)
            persistence.place(reading, beside: garage, in: context)
            reading.id = UUID()
            reading.date = now
            reading.value = vehicle.reading
            reading.loggedBy = ownerName
            reading.vehicle = vehicle
        }
        let starting = vehicle.catalogItems
            .filter { $0.isCore || (vehicle.hasAuxMeter && vehicle.auxMeter == .hours && $0.auxHours != nil) }
        for (index, item) in starting.enumerated() {
            let task = makeTask(from: item, for: vehicle, createdAt: now.addingTimeInterval(Double(index) * 0.001))
            if let date = draft.lastDone[item.key] {
                task.baselineDate = date
                // A date in the last few weeks most likely came at today's
                // reading; older ones leave the meter unknown. A job counted on
                // the second meter can't borrow the main meter's figure.
                if now.timeIntervalSince(date) < 45 * 86_400, hasStartingReading, !task.usesAuxMeter {
                    task.baselineReading = vehicle.reading
                }
            }
        }
        save()
        return vehicle
    }

    @discardableResult
    func makeTask(from item: CatalogItem, for vehicle: Vehicle, createdAt: Date = .now) -> MaintenanceTask {
        let task = MaintenanceTask(context: context)
        persistence.place(task, beside: vehicle, in: context)
        task.id = UUID()
        task.createdAt = createdAt
        task.catalogKey = item.key
        task.name = item.name
        task.symbol = item.symbol
        if let auxHours = item.auxHours, vehicle.hasAuxMeter, vehicle.auxMeter == .hours {
            task.usesAuxMeter = true
            task.intervalDistance = auxHours
        } else {
            task.intervalDistance = item.distanceInterval(for: vehicle.meter) ?? 0
            task.auxInterval = Self.secondInterval(for: item, on: vehicle)
        }
        task.intervalMonths = Int16(item.months ?? 0)
        task.trigger = item.trigger
        task.baselineReading = -1
        task.isEnabled = true
        task.vehicle = vehicle
        return task
    }

    /// A catalog job's figure on the second meter when that meter reads a
    /// different unit from the main one: a UTV's 1,000 miles beside its
    /// 100 hours.
    static func secondInterval(for item: CatalogItem, on vehicle: Vehicle) -> Double {
        guard vehicle.hasAuxMeter, vehicle.auxMeter != vehicle.meter,
              vehicle.auxMeter.convert(1, to: vehicle.meter) == nil else { return 0 }
        return item.distanceInterval(for: vehicle.auxMeter) ?? 0
    }

    /// After a powertrain change: switches off catalog jobs the new
    /// powertrain doesn't have (spark plugs on an EV), but only ones that were
    /// never done, so nothing with history disappears.
    func switchOffInapplicableTasks(on vehicle: Vehicle) {
        let applicable = Set(vehicle.catalogItems.map(\.key))
        for task in vehicle.enabledTasks {
            guard let key = task.catalogKey, !applicable.contains(key) else { continue }
            let last = lastDone(for: task)
            guard last.date == nil, last.reading == nil else { continue }
            task.isEnabled = false
        }
        save()
    }

    func addCatalogItems(_ items: [CatalogItem], to vehicle: Vehicle) {
        let existing = Set((vehicle.tasks ?? []).compactMap(\.catalogKey))
        for item in items {
            if existing.contains(item.key),
               let task = (vehicle.tasks ?? []).first(where: { $0.catalogKey == item.key }) {
                task.isEnabled = true
            } else {
                makeTask(from: item, for: vehicle)
            }
        }
        save()
    }

    @discardableResult
    func addCustomTask(name: String, symbol: String = "wrench.adjustable", distance: Double, months: Int, onAuxMeter: Bool = false,
                       auxInterval: Double = 0, trigger: UsageEvent? = nil, to vehicle: Vehicle) -> MaintenanceTask {
        let task = MaintenanceTask(context: context)
        persistence.place(task, beside: vehicle, in: context)
        task.id = UUID()
        task.createdAt = .now
        task.name = name.trimmed
        task.symbol = symbol
        task.intervalDistance = max(0, distance)
        task.intervalMonths = Int16(clamping: max(0, months))
        task.baselineReading = -1
        task.usesAuxMeter = onAuxMeter && vehicle.hasAuxMeter
        task.auxInterval = task.usesAuxMeter ? 0 : max(0, auxInterval)
        task.trigger = trigger
        task.isEnabled = true
        task.vehicle = vehicle
        save()
        return task
    }

    func update(_ task: MaintenanceTask, name: String, distance: Double, months: Int, notes: String,
                auxInterval: Double? = nil, trigger: UsageEvent?? = nil) {
        task.name = name.trimmed.nilIfEmpty ?? task.name
        task.intervalDistance = max(0, distance)
        task.intervalMonths = Int16(clamping: max(0, months))
        task.notes = notes.trimmed.nilIfEmpty
        if let auxInterval { task.auxInterval = task.usesAuxMeter ? 0 : max(0, auxInterval) }
        if let trigger { task.trigger = trigger }
        save()
    }

    /// New setup answers (4x4, track days, a belt drive): adds the core jobs
    /// they bring and switches off never-done ones that no longer apply.
    func setProfile(_ vehicle: Vehicle, traits: Set<VehicleTrait>, drive: FinalDrive?) {
        var profile = vehicle.profile
        guard profile.traits != traits || profile.drive != drive else { return }
        let old = vehicle.catalogItems
        let before = Set(old.filter(\.isCore).map(\.key))
        profile.traits = traits
        profile.drive = drive
        vehicle.profile = profile
        let items = vehicle.catalogItems
        // Tuned figures (track brake fluid every six months) follow onto
        // jobs the owner never edited; their own figures stay.
        for task in vehicle.tasks ?? [] where !task.usesAuxMeter {
            guard let key = task.catalogKey,
                  let was = old.first(where: { $0.key == key }),
                  let item = items.first(where: { $0.key == key }),
                  task.intervalDistance == (was.distanceInterval(for: vehicle.meter) ?? 0),
                  Int(task.intervalMonths) == (was.months ?? 0) else { continue }
            task.intervalDistance = item.distanceInterval(for: vehicle.meter) ?? 0
            task.intervalMonths = Int16(item.months ?? 0)
            if task.trigger == was.trigger { task.trigger = item.trigger }
        }
        let added = items.filter { $0.isCore && !before.contains($0.key) }
        addCatalogItems(added, to: vehicle)
        switchOffInapplicableTasks(on: vehicle)
    }

    func remove(_ task: MaintenanceTask) {
        if task.catalogKey != nil {
            task.isEnabled = false
        } else {
            context.delete(task)
        }
        save()
    }

    /// "It was done on this date" without a visit to log, such as at setup.
    func setBaseline(_ task: MaintenanceTask, date: Date, reading: Double?) {
        task.baselineDate = date
        task.baselineReading = reading ?? -1
        save()
    }

    func saveVehicleEdits() { save() }

    func retire(_ vehicle: Vehicle, _ retired: Bool = true) {
        vehicle.isRetired = retired
        if !retired {
            vehicle.soldDate = nil
            vehicle.soldPrice = 0
        }
        save()
    }

    /// Lays it up: reminders pause until it's back on the road.
    func store(_ vehicle: Vehicle, until: Date?, now: Date = .now) {
        vehicle.storedSince = vehicle.storedSince ?? now
        vehicle.storedUntil = until
        save()
    }

    /// Back on the road, with a fresh reading when there is one.
    func returnFromStorage(_ vehicle: Vehicle, reading: Double?, auxReading: Double? = nil, now: Date = .now) {
        vehicle.storedSince = nil
        vehicle.storedUntil = nil
        if let reading, reading > 0, vehicle.meter.hasReading {
            updateReading(vehicle, to: reading, at: now)
        }
        if let auxReading, auxReading > 0, vehicle.hasAuxMeter {
            updateAuxReading(vehicle, to: auxReading, at: now)
        }
        save()
    }

    /// Retires it as sold, keeping the date and price with its history.
    func markSold(_ vehicle: Vehicle, on date: Date, price: Double?) {
        vehicle.isRetired = true
        vehicle.soldDate = date
        vehicle.soldPrice = max(0, price ?? 0)
        save()
    }

    /// Turns the second meter on, renames it, changes its unit, or (with nil)
    /// removes it. Jobs the catalog counts in its hours, like generator
    /// service, follow, and so do whichever-first figures on it.
    func setAuxMeter(_ vehicle: Vehicle, name: String?, unit: MeterUnit? = nil) {
        let name = name?.trimmed.nilIfEmpty
        let wasOn = vehicle.hasAuxMeter
        let unitChanged = unit.map { $0 != vehicle.auxMeter } ?? false
        vehicle.auxMeterName = name
        if let unit { vehicle.auxMeter = unit }
        if name != nil, !wasOn || unitChanged {
            vehicle.auxReading = 0
            vehicle.auxReadingDate = nil
            for reading in vehicle.auxReadings { context.delete(reading) }
        }
        let hours = name != nil && vehicle.auxMeter == .hours
        for task in vehicle.tasks ?? [] {
            guard let key = task.catalogKey, let item = vehicle.catalogItem(key: key) else { continue }
            if let auxHours = item.auxHours {
                task.usesAuxMeter = hours
                task.intervalDistance = hours ? auxHours : (item.distanceInterval(for: vehicle.meter) ?? 0)
                task.baselineReading = -1
            }
            if !task.usesAuxMeter { task.auxInterval = Self.secondInterval(for: item, on: vehicle) }
        }
        if !hours {
            for task in vehicle.tasks ?? [] where task.usesAuxMeter && (name == nil || unitChanged) {
                task.usesAuxMeter = false
                task.intervalDistance = 0
            }
        }
        if hours, !wasOn || unitChanged {
            let existing = Set((vehicle.tasks ?? []).filter(\.isEnabled).compactMap(\.catalogKey))
            for item in vehicle.catalogItems
            where item.auxHours != nil && !existing.contains(item.key) {
                if let task = (vehicle.tasks ?? []).first(where: { $0.catalogKey == item.key }) {
                    task.isEnabled = true
                } else {
                    makeTask(from: item, for: vehicle)
                }
            }
        }
        save()
    }

    func delete(_ vehicle: Vehicle) {
        context.delete(vehicle)
        save()
    }

    func move(_ vehicle: Vehicle, to index: Int) {
        var ordered = vehicles
        guard let from = ordered.firstIndex(of: vehicle) else { return }
        ordered.remove(at: from)
        ordered.insert(vehicle, at: max(0, min(index, ordered.count)))
        for (position, item) in ordered.enumerated() { item.sortIndex = Int16(position) }
        save()
    }

    // MARK: - Meter

    func updateAuxReading(_ vehicle: Vehicle, to value: Double, at date: Date = .now) {
        guard vehicle.hasAuxMeter, value >= 0 else { return }
        let reading = MeterReading(context: context)
        persistence.place(reading, beside: vehicle, in: context)
        reading.id = UUID()
        reading.date = date
        reading.value = value
        reading.isAux = true
        reading.loggedBy = ownerName
        reading.vehicle = vehicle
        if value >= vehicle.auxReading {
            vehicle.auxReading = value
            vehicle.auxReadingDate = max(vehicle.auxReadingDate ?? .distantPast, date)
        }
        save()
    }

    /// `shown` is what the odometer reads; a rolled-over or replaced
    /// odometer's missing distance is added back.
    func updateReading(_ vehicle: Vehicle, to shown: Double, at date: Date = .now) {
        guard vehicle.meter.hasReading, shown >= 0 else { return }
        let value = vehicle.trueReading(shown: shown, on: date)
        let reading = MeterReading(context: context)
        persistence.place(reading, beside: vehicle, in: context)
        reading.id = UUID()
        reading.date = date
        reading.value = value
        reading.loggedBy = ownerName
        reading.vehicle = vehicle
        if value >= vehicle.reading || (vehicle.readingDate ?? .distantPast) <= date {
            vehicle.reading = max(vehicle.reading, value)
            vehicle.readingDate = max(vehicle.readingDate ?? .distantPast, date)
        }
        save()
    }

    /// Fixes a mistyped meter: the vehicle reads exactly `value` now, and any
    /// saved reading above it (the typo) is removed so the pace recovers.
    func correctReading(_ vehicle: Vehicle, to shown: Double, at date: Date = .now) {
        guard vehicle.meter.hasReading, shown >= 0 else { return }
        let value = vehicle.trueReading(shown: shown, on: date)
        for reading in vehicle.mainReadings where reading.value > value {
            context.delete(reading)
        }
        vehicle.reading = value
        vehicle.readingDate = date
        let reading = MeterReading(context: context)
        persistence.place(reading, beside: vehicle, in: context)
        reading.id = UUID()
        reading.date = date
        reading.value = value
        reading.loggedBy = ownerName
        reading.vehicle = vehicle
        save()
    }

    /// Switches a vehicle's meter. Miles and kilometers convert every stored
    /// figure; a switch to or from hours can't, so distance intervals reset to
    /// the catalog's and old readings stop counting toward due dates.
    func changeMeter(_ vehicle: Vehicle, to meter: MeterUnit) {
        let old = vehicle.meter
        guard old != meter else { return }
        if let factor = old.convert(1, to: meter) {
            vehicle.reading *= factor
            for reading in vehicle.mainReadings { reading.value *= factor }
            for entry in vehicle.entries ?? [] where entry.hasReading { entry.reading *= factor }
            for task in vehicle.tasks ?? [] where !task.usesAuxMeter {
                task.intervalDistance = Self.roundedInterval(task.intervalDistance * factor)
                if task.baselineReading >= 0 { task.baselineReading *= factor }
            }
        } else {
            vehicle.reading = 0
            vehicle.readingDate = nil
            for reading in vehicle.mainReadings { context.delete(reading) }
            for entry in vehicle.entries ?? [] { entry.reading = -1 }
            for task in vehicle.tasks ?? [] where !task.usesAuxMeter {
                task.baselineReading = -1
                let item = task.catalogKey.flatMap { vehicle.catalogItem(key: $0) }
                task.intervalDistance = item?.distanceInterval(for: meter) ?? 0
            }
        }
        vehicle.meter = meter
        save()
    }

    private static func roundedInterval(_ value: Double) -> Double {
        let step: Double = value >= 10_000 ? 500 : (value >= 1_000 ? 100 : 10)
        return (value / step).rounded() * step
    }

    /// Removes one saved reading; the vehicle falls back to the latest one left.
    func delete(_ reading: MeterReading) {
        guard let vehicle = reading.vehicle else { return }
        context.delete(reading)
        let isAux = reading.isAux
        let remaining = (isAux ? vehicle.auxReadings : vehicle.mainReadings).filter { $0 != reading && !$0.isDeleted }
        if let latest = remaining.max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }) {
            if isAux {
                vehicle.auxReading = latest.value
                vehicle.auxReadingDate = latest.date
            } else {
                vehicle.reading = latest.value
                vehicle.readingDate = latest.date
            }
        } else if isAux {
            // Nothing else is saved, so the wrong figure can't stay as the vehicle's reading.
            vehicle.auxReading = 0
            vehicle.auxReadingDate = nil
        } else {
            let logged = (vehicle.entries ?? [])
                .filter { $0.hasReading && $0.date != nil }
                .max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            vehicle.reading = logged?.reading ?? 0
            vehicle.readingDate = logged?.date
        }
        save()
    }

    /// A reading far beyond the vehicle's pace is usually a typo: an extra digit.
    func isSuspiciousJump(_ shown: Double, for vehicle: Vehicle) -> Bool {
        let value = vehicle.trueReading(shown: shown)
        guard vehicle.meter.hasReading, vehicle.reading > 0, value > vehicle.reading else { return false }
        let days = max(1, Date.now.timeIntervalSince(vehicle.readingDate ?? .now) / 86_400)
        let plausible = max(dailyUse(for: vehicle), typicalDailyUse(for: vehicle)) * days * 4 + vehicle.meter.typoSlack
        return value - vehicle.reading > plausible
    }

    // MARK: - Service log

    struct ServiceDraft: Equatable {
        var kind: EntryKind = .service
        var recallCampaign: String?
        var date: Date = .now
        var reading: Double?
        var auxReading: Double?
        var taskIDs: [UUID] = []
        var title = ""
        var cost: Double = 0
        var shop = ""
        var isDIY = false
        var notes = ""
        var details = EntryDetails()
        var photos: [Data] = []
        var receipts: [Data] = []
        /// Files picked from Files or Mail: (name, data), PDFs or images.
        var files: [(name: String, data: Data)] = []

        static func == (lhs: ServiceDraft, rhs: ServiceDraft) -> Bool {
            lhs.kind == rhs.kind && lhs.recallCampaign == rhs.recallCampaign && lhs.date == rhs.date
                && lhs.reading == rhs.reading && lhs.auxReading == rhs.auxReading && lhs.taskIDs == rhs.taskIDs
                && lhs.title == rhs.title && lhs.cost == rhs.cost && lhs.shop == rhs.shop && lhs.isDIY == rhs.isDIY
                && lhs.notes == rhs.notes && lhs.details == rhs.details && lhs.photos == rhs.photos
                && lhs.receipts == rhs.receipts && lhs.files.map(\.name) == rhs.files.map(\.name)
        }
    }

    @discardableResult
    func log(_ draft: ServiceDraft, for vehicle: Vehicle, editing existing: ServiceEntry? = nil) -> ServiceEntry {
        let entry = existing ?? ServiceEntry(context: context)
        if existing == nil {
            persistence.place(entry, beside: vehicle, in: context)
            entry.id = UUID()
            entry.createdAt = .now
            entry.loggedBy = ownerName
            entry.vehicle = vehicle
        }
        entry.kind = draft.kind
        // A service visit can close a recall too, when its receipt names one.
        entry.recallCampaign = draft.recallCampaign
        entry.date = draft.date
        let reading = draft.reading.map { vehicle.trueReading(shown: $0, on: draft.date) }
        entry.reading = reading ?? -1
        entry.auxReading = vehicle.hasAuxMeter ? (draft.auxReading ?? -1) : -1
        // Mods and events don't do scheduled jobs; an event's own jobs come
        // due from it instead.
        entry.coveredTaskIDs = draft.kind == .event ? [] : draft.taskIDs
        var details = draft.details
        details.parts = details.parts.filter { !$0.isBlank }
        details.specs = details.specs.filter { !$0.isBlank }
        if draft.kind != .event { details.event = nil }
        if draft.kind != .mod { details.removedOn = nil }
        entry.details = details
        entry.title = draft.title.trimmed.nilIfEmpty ?? defaultTitle(for: draft, on: vehicle)
        entry.cost = max(0, draft.cost)
        entry.shop = draft.isDIY ? nil : draft.shop.trimmed.nilIfEmpty
        entry.isDIY = draft.isDIY
        entry.notes = draft.notes.trimmed.nilIfEmpty
        for (data, kind) in draft.photos.map({ ($0, "photo") }) + draft.receipts.map({ ($0, "receipt") }) {
            let attachment = Attachment(context: context)
            persistence.place(attachment, beside: vehicle, in: context)
            attachment.id = UUID()
            attachment.createdAt = .now
            attachment.kindRaw = kind
            attachment.data = data
            attachment.entry = entry
        }
        for file in draft.files {
            let attachment = makeDocument(file.name, data: file.data, beside: vehicle)
            attachment.entry = entry
        }
        if let reading, reading > vehicle.reading, draft.date <= .now {
            vehicle.reading = reading
            vehicle.readingDate = draft.date
        }
        if vehicle.hasAuxMeter, let aux = draft.auxReading, aux > vehicle.auxReading {
            vehicle.auxReading = aux
            vehicle.auxReadingDate = draft.date
        }
        save()
        return entry
    }

    private func defaultTitle(for draft: ServiceDraft, on vehicle: Vehicle) -> String {
        switch draft.kind {
        case .event: return draft.details.event?.title ?? EntryKind.event.title
        case .mod: return draft.details.parts.first(where: { !$0.isBlank })?.summary.nilIfEmpty ?? "Mod"
        case .repair where draft.taskIDs.isEmpty: return "Repair"
        default: return title(for: draft.taskIDs, on: vehicle)
        }
    }

    /// Logs a track day or a water crossing, which brings its jobs due.
    @discardableResult
    func logEvent(_ event: UsageEvent, on date: Date, notes: String = "", for vehicle: Vehicle) -> ServiceEntry {
        var draft = ServiceDraft()
        draft.kind = .event
        draft.date = date
        draft.notes = notes
        draft.details.event = event
        return log(draft, for: vehicle)
    }

    /// Jobs a kind of event brings due on this vehicle.
    func jobs(triggeredBy event: UsageEvent, on vehicle: Vehicle) -> [MaintenanceTask] {
        vehicle.enabledTasks.filter { $0.trigger == event }
    }

    /// A mod that came off. It stays in the history, out of the build list.
    func setRemoved(_ entry: ServiceEntry, on date: Date?) {
        var details = entry.details
        details.removedOn = date
        entry.details = details
        save()
    }

    // MARK: - Documents

    /// A file kept against a vehicle or a visit: PDFs stay PDFs, images are
    /// scaled down like photos.
    func makeDocument(_ name: String, data: Data, beside vehicle: Vehicle) -> Attachment {
        let attachment = Attachment(context: context)
        persistence.place(attachment, beside: vehicle, in: context)
        attachment.id = UUID()
        attachment.createdAt = .now
        let isPDF = data.starts(with: Array("%PDF".utf8))
        attachment.kindRaw = isPDF ? "pdf" : "photo"
        attachment.data = isPDF ? data : (ImageTools.jpeg(data) ?? data)
        attachment.name = name.trimmed.nilIfEmpty
        return attachment
    }

    func addDocument(_ name: String, data: Data, to vehicle: Vehicle) {
        let attachment = makeDocument(name, data: data, beside: vehicle)
        attachment.vehicle = vehicle
        save()
    }

    func rename(_ attachment: Attachment, to name: String) {
        attachment.name = name.trimmed.nilIfEmpty
        save()
    }

    // MARK: - Odometer changes

    /// The odometer rolled over or was replaced: what it showed before and
    /// after. The true total carries on, so nothing comes due by mistake.
    func recordOdometerChange(_ vehicle: Vehicle, on date: Date, lastShown: Double, newShown: Double, replaced: Bool) {
        guard vehicle.meter.hasReading, lastShown >= 0, newShown >= 0 else { return }
        var profile = vehicle.profile
        profile.odometerChanges.append(OdometerChange(date: date, lastShown: lastShown, newShown: newShown, replaced: replaced))
        profile.odometerChanges.sort { $0.date < $1.date }
        vehicle.profile = profile
        save()
        updateReading(vehicle, to: newShown, at: date)
    }

    func removeOdometerChange(_ change: OdometerChange, from vehicle: Vehicle) {
        var profile = vehicle.profile
        profile.odometerChanges.removeAll { $0.id == change.id }
        vehicle.profile = profile
        save()
    }

    func setMileageStatus(_ status: MileageStatus, on vehicle: Vehicle) {
        var profile = vehicle.profile
        profile.mileageStatus = status
        vehicle.profile = profile
        save()
    }

    func setRoadside(_ info: RoadsideInfo, on vehicle: Vehicle) {
        var profile = vehicle.profile
        let cleaned = info.cleaned
        profile.roadside = cleaned.isEmpty ? nil : cleaned
        vehicle.profile = profile
        save()
    }

    struct FuelDraft: Equatable {
        var date: Date = .now
        var reading: Double?
        /// In `unit`, as the pump showed it.
        var volume: Double?
        var unitPrice: Double?
        var total: Double?
        var unit: FuelVolumeUnit = .current
        var grade: FuelGrade?
        var partial = false
        var station = ""
        var pumpPhotos: [Data] = []
        var meterPhotos: [Data] = []
    }

    /// A fill-up: kept in the log with its own fields, never against a
    /// maintenance job, and its reading teaches Keyring the vehicle's pace.
    @discardableResult
    func logFuel(_ draft: FuelDraft, for vehicle: Vehicle, editing existing: ServiceEntry? = nil) -> ServiceEntry {
        let entry = existing ?? ServiceEntry(context: context)
        if existing == nil {
            persistence.place(entry, beside: vehicle, in: context)
            entry.id = UUID()
            entry.createdAt = .now
            entry.loggedBy = ownerName
            entry.vehicle = vehicle
        }
        let fields = PumpReader.completed(PumpFields(volume: draft.volume, unitPrice: draft.unitPrice, total: draft.total))
        entry.kind = .fuel
        entry.title = EntryKind.fuel.title
        entry.date = draft.date
        let reading = draft.reading.map { vehicle.trueReading(shown: $0, on: draft.date) }
        entry.reading = reading ?? -1
        entry.fuelVolume = fields.volume.map(draft.unit.liters) ?? 0
        entry.fuelUnitPrice = fields.unitPrice.map(draft.unit.perLiter) ?? 0
        entry.cost = max(0, fields.total ?? 0)
        entry.grade = draft.grade
        entry.fuelPartial = draft.partial
        entry.shop = draft.station.trimmed.nilIfEmpty
        entry.isDIY = false
        for (data, kind) in draft.pumpPhotos.map({ ($0, "receipt") }) + draft.meterPhotos.map({ ($0, "photo") }) {
            let attachment = Attachment(context: context)
            persistence.place(attachment, beside: vehicle, in: context)
            attachment.id = UUID()
            attachment.createdAt = .now
            attachment.kindRaw = kind
            attachment.data = data
            attachment.entry = entry
        }
        if let reading, reading > vehicle.reading {
            vehicle.reading = reading
            vehicle.readingDate = draft.date
        }
        save()
        return entry
    }

    /// Stations already used, most recent first, for one-tap entry.
    func recentStations(for vehicle: Vehicle? = nil) -> [String] {
        let entries = (vehicle?.fuelEntries ?? allEntries().filter { $0.kind == .fuel })
        var seen = Set<String>()
        return entries.compactMap(\.shop).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(5).map { $0 }
    }

    /// Recalls still worth a look: open on the VIN check if there is one, not
    /// shown fixed in the log, not dismissed here.
    func openRecalls(_ recalls: [Recall], for vehicle: Vehicle) -> [Recall] {
        let reviewed = RecallLedger.reviewed(for: vehicle.id)
        let check = VINRecallChecks.check(for: vehicle)
        let candidates = check.map { check in recalls.filter(check.shows) + check.unlisted(in: recalls) } ?? recalls
        return candidates.filter { !reviewed.contains($0.campaign) && RecallMatcher.fix(for: $0, on: vehicle) == nil }
    }

    /// Recorded once the owner has checked the VIN and the dealer already did it.
    func markRecallFixedByDealer(_ recall: Recall, for vehicle: Vehicle) {
        var draft = ServiceDraft()
        draft.kind = .recall
        draft.recallCampaign = recall.campaign
        draft.title = "Recall: \(recall.componentTitle.lowercased())"
        draft.shop = "Dealer"
        draft.notes = "Already fixed by a dealer, per the VIN check. Repair date not known."
        log(draft, for: vehicle)
    }

    func title(for taskIDs: [UUID], on vehicle: Vehicle) -> String {
        let names = (vehicle.tasks ?? []).filter { task in task.id.map(taskIDs.contains) ?? false }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            .map(\.displayName)
        switch names.count {
        case 0: return "Service"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1].lowercasedFirst)"
        default: return "\(names[0]) and \(names.count - 1) more"
        }
    }

    func delete(_ entry: ServiceEntry) {
        context.delete(entry)
        save()
    }

    func delete(_ attachment: Attachment) {
        context.delete(attachment)
        save()
    }

    /// Every entry in every garage, newest first, for the history timeline.
    func allEntries() -> [ServiceEntry] {
        let request = NSFetchRequest<ServiceEntry>(entityName: "ServiceEntry")
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return ((try? context.fetch(request)) ?? []).filter { $0.vehicle != nil }
    }

    // MARK: - Import

    struct ImportOutcome: Equatable {
        var added = 0
        var duplicates = 0
        var readings = 0
        var fillUps = 0
        var jobsUpdated = 0
    }

    /// Adds rows from another app's export to one vehicle. Rows already in the
    /// log (same day, same work) are skipped, so importing twice is harmless.
    @discardableResult
    func importHistory(_ rows: [ServiceImport.Row], into vehicle: Vehicle, keepFillUps: Bool = true) -> ImportOutcome {
        var outcome = ImportOutcome()
        let calendar = Calendar.current
        let dayKey = { (date: Date, title: String) in "\(calendar.startOfDay(for: date).timeIntervalSince1970)|\(title.lowercased().trimmed)" }
        // Same day, same work and same cost is the same visit; front and rear
        // brakes on one day at different prices are two.
        let serviceKey = { (date: Date, title: String, cost: Double) in dayKey(date, "\(title)|\(Int((cost * 100).rounded()))") }
        var existing = Set((vehicle.entries ?? []).compactMap { entry in
            entry.date.map { entry.kind == .fuel ? dayKey($0, "\(EntryKind.fuel.title)|\(Int(entry.reading))") : serviceKey($0, entry.title ?? "", entry.cost) }
        })
        var readingDays = Set(vehicle.mainReadings.compactMap { reading in
            reading.date.map { "\(calendar.startOfDay(for: $0).timeIntervalSince1970)|\(Int(reading.value))" }
        })
        var touched = Set<UUID>()
        var highest: (value: Double, date: Date)?

        for row in rows {
            let reading = row.reading.flatMap { value in
                guard vehicle.meter.hasReading else { return nil as Double? }
                return (row.unit ?? vehicle.meter).convert(value, to: vehicle.meter).map { vehicle.trueReading(shown: $0, on: row.date) }
            }
            if let reading, reading > (highest?.value ?? -1) { highest = (reading, row.date) }
            if row.isFillUp, keepFillUps, row.volume != nil || row.cost > 0 {
                // A real fill-up: gallons, price and all, so economy works from day one.
                let key = dayKey(row.date, "\(EntryKind.fuel.title)|\(Int(reading ?? -1))")
                guard existing.insert(key).inserted else {
                    outcome.duplicates += 1
                    continue
                }
                let unit = row.volumeUnit ?? .current
                let figures = PumpReader.completed(PumpFields(volume: row.volume, unitPrice: row.unitPrice, total: row.cost > 0 ? row.cost : nil))
                let entry = ServiceEntry(context: context)
                persistence.place(entry, beside: vehicle, in: context)
                entry.id = UUID()
                entry.createdAt = .now
                entry.vehicle = vehicle
                entry.kind = .fuel
                entry.title = EntryKind.fuel.title
                entry.date = row.date
                entry.reading = reading ?? -1
                entry.fuelVolume = figures.volume.map(unit.liters) ?? 0
                entry.fuelUnitPrice = figures.unitPrice.map(unit.perLiter) ?? 0
                entry.cost = figures.total ?? 0
                entry.grade = row.grade
                entry.fuelPartial = row.partial
                entry.shop = row.shop
                entry.notes = row.notes
                entry.loggedBy = row.loggedBy ?? ownerName
                outcome.fillUps += 1
                continue
            }
            if row.isFillUp {
                guard keepFillUps, let reading else { continue }
                let key = "\(calendar.startOfDay(for: row.date).timeIntervalSince1970)|\(Int(reading))"
                guard readingDays.insert(key).inserted else { continue }
                let meter = MeterReading(context: context)
                persistence.place(meter, beside: vehicle, in: context)
                meter.id = UUID()
                meter.date = row.date
                meter.value = reading
                meter.loggedBy = row.loggedBy
                meter.vehicle = vehicle
                outcome.readings += 1
                continue
            }
            let taskIDs = matchingTasks(for: row.work, on: vehicle)
            let title = row.work.nilIfEmpty ?? (taskIDs.isEmpty ? "Service" : self.title(for: taskIDs, on: vehicle))
            guard existing.insert(serviceKey(row.date, title, row.cost)).inserted else {
                outcome.duplicates += 1
                continue
            }
            let entry = ServiceEntry(context: context)
            persistence.place(entry, beside: vehicle, in: context)
            entry.id = UUID()
            entry.createdAt = .now
            entry.vehicle = vehicle
            entry.kind = row.kind
            entry.date = row.date
            entry.reading = reading ?? -1
            entry.title = title
            entry.coveredTaskIDs = taskIDs
            entry.cost = row.cost
            entry.isDIY = row.isDIY
            entry.shop = row.isDIY ? nil : row.shop
            entry.notes = row.notes
            entry.loggedBy = row.loggedBy ?? ownerName
            touched.formUnion(taskIDs)
            outcome.added += 1
        }
        if let highest, highest.value > vehicle.reading {
            vehicle.reading = highest.value
            vehicle.readingDate = max(vehicle.readingDate ?? .distantPast, highest.date)
        }
        outcome.jobsUpdated = touched.count
        save()
        return outcome
    }

    /// Schedule items a line of imported work covers: by catalog job, then by
    /// a custom item's own name.
    func matchingTasks(for work: String, on vehicle: Vehicle) -> [UUID] {
        let keys = ServiceImport.catalogKeys(for: work)
        let lower = work.lowercased()
        return vehicle.enabledTasks.filter { task in
            if let key = task.catalogKey { return keys.contains(key) }
            let name = task.displayName.lowercased()
            return name.count > 3 && lower.contains(name)
        }
        .compactMap(\.id)
    }

    // MARK: - Value

    func addValuation(_ amount: Double, source: String, kind: ValuationKind = .estimate, to vehicle: Vehicle, at date: Date = .now) {
        let valuation = Valuation(context: context)
        persistence.place(valuation, beside: vehicle, in: context)
        valuation.id = UUID()
        valuation.date = date
        valuation.amount = amount
        valuation.source = source.trimmed.nilIfEmpty
        valuation.kind = kind
        valuation.vehicle = vehicle
        save()
    }

    func delete(_ valuation: Valuation) {
        context.delete(valuation)
        save()
    }

    // MARK: - People

    /// How this person's entries are signed for the rest of the family.
    var ownerName: String? {
        AppGroup.defaults.string(forKey: AppGroup.Key.ownerName)?.trimmed.nilIfEmpty
    }

    func setOwnerName(_ name: String) {
        AppGroup.defaults.set(name.trimmed, forKey: AppGroup.Key.ownerName)
    }

    // MARK: - Saving

    @discardableResult
    func save() -> Bool {
        let saved = persistence.save(context)
        reload()
        return saved
    }

    /// Pushes the derived state out to the widget and the reminders after
    /// every change.
    private func publish() {
        let summaries = vehicles.filter { $0.storedSince == nil }.map { vehicle -> WidgetSnapshot.VehicleSummary in
            let dues = dues(for: vehicle).filter { $0.result.status != .noRecord }
            return WidgetSnapshot.VehicleSummary(
                id: vehicle.id?.uuidString ?? "",
                name: vehicle.displayName,
                symbol: vehicle.kind.symbol,
                tintHex: vehicle.tint.hex,
                items: dues.prefix(3).map { due in
                    WidgetSnapshot.Item(
                        name: due.name,
                        statusRaw: due.result.status.rawValue,
                        dueDate: due.result.dueDate,
                        estimated: due.result.dateIsEstimated,
                        dueAt: due.result.dueReading.map { "At \(Format.reading($0, due.meter))" }
                    )
                }
            )
        }
        WidgetSnapshot.write(WidgetSnapshot(vehicles: summaries, updatedAt: .now))
        ReminderScheduler.shared.schedule(for: self)
    }
}

extension TaskDue {
    /// "Every 7,500 mi or 1 year", in this job's own meters.
    func intervalText(auxName: String?) -> String {
        Format.interval(
            distance: intervalDistance, months: intervalMonths, meter: meter, auxName: usesAuxMeter ? auxName : nil,
            second: secondInterval, secondMeter: secondMeter, secondName: auxName, trigger: trigger
        )
    }
}

extension MaintenanceTask {
    var intervalText: String {
        Format.interval(
            distance: intervalDistance, months: Int(intervalMonths), meter: countingMeter,
            auxName: countsOnAuxMeter ? vehicle?.auxMeterName : nil,
            second: secondInterval, secondMeter: vehicle?.auxMeter ?? .hours, secondName: vehicle?.auxMeterName,
            trigger: trigger
        )
    }
}

extension CatalogItem {
    /// How often it would run if added to this vehicle.
    @MainActor func intervalText(on vehicle: Vehicle) -> String {
        let onAux = vehicle.hasAuxMeter && vehicle.auxMeter == .hours && auxHours != nil
        return Format.interval(
            distance: onAux ? (auxHours ?? 0) : (distanceInterval(for: vehicle.meter) ?? 0),
            months: months ?? 0,
            meter: onAux ? .hours : vehicle.meter,
            auxName: onAux ? vehicle.auxMeterName : nil,
            second: onAux ? 0 : GarageStore.secondInterval(for: self, on: vehicle),
            secondMeter: vehicle.auxMeter, secondName: vehicle.auxMeterName,
            trigger: trigger
        )
    }
}
