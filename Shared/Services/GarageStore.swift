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

    static func ordering(_ lhs: TaskDue, _ rhs: TaskDue) -> Bool {
        if lhs.result.status != rhs.result.status { return lhs.result.status < rhs.result.status }
        switch (lhs.result.dueDate, rhs.result.dueDate) {
        case let (l?, r?): return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.name < rhs.name
        }
    }
}

/// What a new vehicle starts with.
struct NewVehicle {
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
    var photo: Data?
    var tint: VehicleTint?
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
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: persistence.container.persistentStoreCoordinator, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        })
        observers.append(center.addObserver(forName: Persistence.storesDidReopen, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        })
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
        var points: [(date: Date, value: Double)] = (vehicle.readings ?? []).compactMap { reading in
            reading.date.map { ($0, reading.value) }
        }
        points += (vehicle.entries ?? []).compactMap { entry in
            guard entry.hasReading, let date = entry.date else { return nil }
            return (date, entry.reading)
        }
        if let date = vehicle.readingDate { points.append((date, vehicle.reading)) }
        return DueEngine.dailyUse(readings: points, fallback: vehicle.kind.typicalDailyUse)
    }

    /// The most recent time this job was done: a logged entry that covered it,
    /// or the "last done" the owner gave at setup, whichever is later.
    func lastDone(for task: MaintenanceTask) -> (date: Date?, reading: Double?) {
        var date = task.baselineDate
        var reading: Double? = task.baselineReading >= 0 ? task.baselineReading : nil
        guard let id = task.id, let entries = task.vehicle?.entries else { return (date, reading) }
        let covering = entries.filter { $0.coveredTaskIDs.contains(id) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        if let latest = covering.first, let latestDate = latest.date, latestDate >= (date ?? .distantPast) {
            date = latestDate
            if latest.hasReading { reading = latest.reading }
            else if let withReading = covering.first(where: \.hasReading) { reading = max(reading ?? 0, withReading.reading) }
        }
        return (date, reading)
    }

    func dues(for vehicle: Vehicle, now: Date = .now) -> [TaskDue] {
        let pace = dailyUse(for: vehicle)
        return vehicle.enabledTasks.compactMap { task -> TaskDue? in
            guard let id = task.id else { return nil }
            let last = lastDone(for: task)
            let result = DueEngine.evaluate(DueInput(
                intervalDistance: task.intervalDistance,
                intervalMonths: Int(task.intervalMonths),
                lastDate: last.date,
                lastReading: last.reading,
                currentReading: vehicle.reading,
                dailyUse: pace,
                meter: vehicle.meter
            ), now: now)
            return TaskDue(
                id: task.objectID, taskID: id, name: task.displayName, symbol: task.displaySymbol,
                catalogKey: task.catalogKey, result: result, lastDate: last.date, lastReading: last.reading,
                intervalDistance: task.intervalDistance, intervalMonths: Int(task.intervalMonths)
            )
        }
        .sorted(by: TaskDue.ordering)
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
        vehicle.readingDate = draft.meter.hasReading ? now : nil
        vehicle.photo = draft.photo
        vehicle.tint = draft.tint ?? .defaultTint(for: draft.kind)
        vehicle.sortIndex = Int16(clamping: (garage.vehicles?.count ?? 0))
        vehicle.garage = garage
        if draft.meter.hasReading {
            let reading = MeterReading(context: context)
            persistence.place(reading, beside: garage, in: context)
            reading.id = UUID()
            reading.date = now
            reading.value = vehicle.reading
            reading.loggedBy = ownerName
            reading.vehicle = vehicle
        }
        for (index, item) in MaintenanceCatalog.items(for: draft.kind, powertrain: draft.powertrain).filter(\.isCore).enumerated() {
            let task = makeTask(from: item, for: vehicle, createdAt: now.addingTimeInterval(Double(index) * 0.001))
            if let date = draft.lastDone[item.key] {
                task.baselineDate = date
                // A date in the last few weeks most likely came at today's
                // reading; older ones leave the meter unknown.
                if now.timeIntervalSince(date) < 45 * 86_400, draft.meter.hasReading {
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
        task.intervalDistance = item.distanceInterval(for: vehicle.meter) ?? 0
        task.intervalMonths = Int16(item.months ?? 0)
        task.baselineReading = -1
        task.isEnabled = true
        task.vehicle = vehicle
        return task
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
    func addCustomTask(name: String, symbol: String = "wrench.adjustable", distance: Double, months: Int, to vehicle: Vehicle) -> MaintenanceTask {
        let task = MaintenanceTask(context: context)
        persistence.place(task, beside: vehicle, in: context)
        task.id = UUID()
        task.createdAt = .now
        task.name = name.trimmed
        task.symbol = symbol
        task.intervalDistance = max(0, distance)
        task.intervalMonths = Int16(clamping: max(0, months))
        task.baselineReading = -1
        task.isEnabled = true
        task.vehicle = vehicle
        save()
        return task
    }

    func update(_ task: MaintenanceTask, name: String, distance: Double, months: Int, notes: String) {
        task.name = name.trimmed.nilIfEmpty ?? task.name
        task.intervalDistance = max(0, distance)
        task.intervalMonths = Int16(clamping: max(0, months))
        task.notes = notes.trimmed.nilIfEmpty
        save()
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

    func updateReading(_ vehicle: Vehicle, to value: Double, at date: Date = .now) {
        guard vehicle.meter.hasReading, value >= 0 else { return }
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

    // MARK: - Service log

    struct ServiceDraft {
        var date: Date = .now
        var reading: Double?
        var taskIDs: [UUID] = []
        var title = ""
        var cost: Double = 0
        var shop = ""
        var isDIY = false
        var notes = ""
        var photos: [Data] = []
        var receipts: [Data] = []
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
        entry.date = draft.date
        entry.reading = draft.reading ?? -1
        entry.coveredTaskIDs = draft.taskIDs
        entry.title = draft.title.trimmed.nilIfEmpty ?? title(for: draft.taskIDs, on: vehicle)
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
        if let reading = draft.reading, reading > vehicle.reading {
            vehicle.reading = reading
            vehicle.readingDate = draft.date
        }
        save()
        return entry
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

    // MARK: - Value

    func addValuation(_ amount: Double, source: String, to vehicle: Vehicle, at date: Date = .now) {
        let valuation = Valuation(context: context)
        persistence.place(valuation, beside: vehicle, in: context)
        valuation.id = UUID()
        valuation.date = date
        valuation.amount = amount
        valuation.source = source.trimmed.nilIfEmpty
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
        let summaries = vehicles.map { vehicle -> WidgetSnapshot.VehicleSummary in
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
                        estimated: due.result.dateIsEstimated
                    )
                }
            )
        }
        WidgetSnapshot.write(WidgetSnapshot(vehicles: summaries, updatedAt: .now))
        ReminderScheduler.shared.schedule(for: self)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
