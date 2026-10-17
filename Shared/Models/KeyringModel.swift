import CoreData
import Foundation

/// The Core Data model, built in code so the app, tests and the CloudKit
/// schema tool compile one definition. CloudKit mirroring needs every
/// attribute optional or defaulted, every relationship optional with an
/// inverse, and no unique constraints; `KeyringModelTests` holds it to that.
enum KeyringModel {
    nonisolated(unsafe) static let model: NSManagedObjectModel = build()

    /// The model 1.0 builds 1 to 3 shipped, before entries had a kind. SQLite
    /// stores carry their own model, so Core Data migrates them by itself;
    /// this is kept so a test proves those logs still open.
    nonisolated(unsafe) static let firstRelease: NSManagedObjectModel = build(entryKinds: false)

    private static func build(entryKinds: Bool = true) -> NSManagedObjectModel {
        let garage = entity("Garage", Garage.self)
        let vehicle = entity("Vehicle", Vehicle.self)
        let task = entity("MaintenanceTask", MaintenanceTask.self)
        let entry = entity("ServiceEntry", ServiceEntry.self)
        let attachment = entity("Attachment", Attachment.self)
        let reading = entity("MeterReading", MeterReading.self)
        let valuation = entity("Valuation", Valuation.self)

        garage.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("createdAt", .dateAttributeType),
        ]
        vehicle.properties = [
            attr("id", .UUIDAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("kindRaw", .stringAttributeType, default: VehicleKind.car.rawValue),
            attr("powertrainRaw", .stringAttributeType, default: Powertrain.gasoline.rawValue),
            attr("meterRaw", .stringAttributeType, default: MeterUnit.miles.rawValue),
            attr("nickname", .stringAttributeType),
            attr("year", .integer16AttributeType, default: 0),
            attr("make", .stringAttributeType),
            attr("model", .stringAttributeType),
            attr("trim", .stringAttributeType),
            attr("vin", .stringAttributeType),
            attr("plate", .stringAttributeType),
            attr("reading", .doubleAttributeType, default: 0.0),
            attr("readingDate", .dateAttributeType),
            binary("photo"),
            attr("tintRaw", .stringAttributeType),
            attr("purchaseDate", .dateAttributeType),
            attr("purchasePrice", .doubleAttributeType, default: 0.0),
            attr("factsJSON", .stringAttributeType),
            attr("notes", .stringAttributeType),
            attr("sortIndex", .integer16AttributeType, default: 0),
            attr("isRetired", .booleanAttributeType, default: false),
        ]
        task.properties = [
            attr("id", .UUIDAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("catalogKey", .stringAttributeType),
            attr("name", .stringAttributeType),
            attr("symbol", .stringAttributeType),
            attr("intervalDistance", .doubleAttributeType, default: 0.0),
            attr("intervalMonths", .integer16AttributeType, default: 0),
            attr("baselineDate", .dateAttributeType),
            attr("baselineReading", .doubleAttributeType, default: -1.0),
            attr("isEnabled", .booleanAttributeType, default: true),
            attr("notes", .stringAttributeType),
        ]
        entry.properties = [
            attr("id", .UUIDAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("date", .dateAttributeType),
            attr("reading", .doubleAttributeType, default: -1.0),
            attr("title", .stringAttributeType),
            attr("taskIDs", .stringAttributeType),
            attr("cost", .doubleAttributeType, default: 0.0),
            attr("shop", .stringAttributeType),
            attr("isDIY", .booleanAttributeType, default: false),
            attr("notes", .stringAttributeType),
            attr("loggedBy", .stringAttributeType),
        ] + (entryKinds ? [
            attr("kindRaw", .stringAttributeType, default: EntryKind.service.rawValue),
            attr("recallCampaign", .stringAttributeType),
        ] : [])
        attachment.properties = [
            attr("id", .UUIDAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("kindRaw", .stringAttributeType, default: "photo"),
            binary("data"),
        ]
        reading.properties = [
            attr("id", .UUIDAttributeType),
            attr("date", .dateAttributeType),
            attr("value", .doubleAttributeType, default: 0.0),
            attr("loggedBy", .stringAttributeType),
        ]
        valuation.properties = [
            attr("id", .UUIDAttributeType),
            attr("date", .dateAttributeType),
            attr("amount", .doubleAttributeType, default: 0.0),
            attr("source", .stringAttributeType),
        ]

        relate(garage, "vehicles", toMany: true, deleteRule: .cascadeDeleteRule,
               vehicle, "garage", toMany: false, inverseRule: .nullifyDeleteRule)
        relate(vehicle, "tasks", toMany: true, deleteRule: .cascadeDeleteRule,
               task, "vehicle", toMany: false, inverseRule: .nullifyDeleteRule)
        relate(vehicle, "entries", toMany: true, deleteRule: .cascadeDeleteRule,
               entry, "vehicle", toMany: false, inverseRule: .nullifyDeleteRule)
        relate(vehicle, "readings", toMany: true, deleteRule: .cascadeDeleteRule,
               reading, "vehicle", toMany: false, inverseRule: .nullifyDeleteRule)
        relate(vehicle, "valuations", toMany: true, deleteRule: .cascadeDeleteRule,
               valuation, "vehicle", toMany: false, inverseRule: .nullifyDeleteRule)
        relate(entry, "attachments", toMany: true, deleteRule: .cascadeDeleteRule,
               attachment, "entry", toMany: false, inverseRule: .nullifyDeleteRule)

        let model = NSManagedObjectModel()
        model.entities = [garage, vehicle, task, entry, attachment, reading, valuation]
        return model
    }

    private static func entity(_ name: String, _ type: NSManagedObject.Type) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(type)
        return entity
    }

    private static func attr(_ name: String, _ type: NSAttributeType, default value: Any? = nil) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        attribute.defaultValue = value
        return attribute
    }

    /// Photos and receipts live outside the SQLite file and travel to CloudKit
    /// as assets.
    private static func binary(_ name: String) -> NSAttributeDescription {
        let attribute = attr(name, .binaryDataAttributeType)
        attribute.allowsExternalBinaryDataStorage = true
        return attribute
    }

    private static func relate(
        _ source: NSEntityDescription, _ name: String, toMany: Bool, deleteRule: NSDeleteRule,
        _ destination: NSEntityDescription, _ inverseName: String, toMany inverseToMany: Bool, inverseRule: NSDeleteRule
    ) {
        let forward = NSRelationshipDescription()
        forward.name = name
        forward.destinationEntity = destination
        forward.minCount = 0
        forward.maxCount = toMany ? 0 : 1
        forward.deleteRule = deleteRule
        forward.isOptional = true

        let inverse = NSRelationshipDescription()
        inverse.name = inverseName
        inverse.destinationEntity = source
        inverse.minCount = 0
        inverse.maxCount = inverseToMany ? 0 : 1
        inverse.deleteRule = inverseRule
        inverse.isOptional = true

        forward.inverseRelationship = inverse
        inverse.inverseRelationship = forward
        source.properties.append(forward)
        destination.properties.append(inverse)
    }
}

// MARK: - Managed objects

@objc(Garage)
final class Garage: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var vehicles: Set<Vehicle>?

    static func make(in context: NSManagedObjectContext, name: String) -> Garage {
        let garage = Garage(context: context)
        garage.id = UUID()
        garage.name = name
        garage.createdAt = .now
        return garage
    }

    var displayName: String { (name?.isEmpty == false ? name : nil) ?? "Our garage" }

    var activeVehicles: [Vehicle] {
        (vehicles ?? []).filter { !$0.isRetired }.sorted(by: Vehicle.displayOrder)
    }
}

@objc(Vehicle)
final class Vehicle: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var createdAt: Date?
    @NSManaged var kindRaw: String?
    @NSManaged var powertrainRaw: String?
    @NSManaged var meterRaw: String?
    @NSManaged var nickname: String?
    @NSManaged var year: Int16
    @NSManaged var make: String?
    @NSManaged var model: String?
    @NSManaged var trim: String?
    @NSManaged var vin: String?
    @NSManaged var plate: String?
    @NSManaged var reading: Double
    @NSManaged var readingDate: Date?
    @NSManaged var photo: Data?
    @NSManaged var tintRaw: String?
    @NSManaged var purchaseDate: Date?
    @NSManaged var purchasePrice: Double
    @NSManaged var factsJSON: String?
    @NSManaged var notes: String?
    @NSManaged var sortIndex: Int16
    @NSManaged var isRetired: Bool
    @NSManaged var garage: Garage?
    @NSManaged var tasks: Set<MaintenanceTask>?
    @NSManaged var entries: Set<ServiceEntry>?
    @NSManaged var readings: Set<MeterReading>?
    @NSManaged var valuations: Set<Valuation>?

    static func displayOrder(_ lhs: Vehicle, _ rhs: Vehicle) -> Bool {
        if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
        return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
    }

    var kind: VehicleKind {
        get { VehicleKind(rawValue: kindRaw ?? "") ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var powertrain: Powertrain {
        get { Powertrain(rawValue: powertrainRaw ?? "") ?? kind.defaultPowertrain }
        set { powertrainRaw = newValue.rawValue }
    }

    var meter: MeterUnit {
        get { MeterUnit(rawValue: meterRaw ?? "") ?? kind.defaultMeter }
        set { meterRaw = newValue.rawValue }
    }

    var tint: VehicleTint {
        get { VehicleTint(rawValue: tintRaw ?? "") ?? .defaultTint(for: kind) }
        set { tintRaw = newValue.rawValue }
    }

    /// "2019 Toyota Tacoma", or whatever parts are known.
    var descriptor: String {
        [year > 0 ? String(year) : nil, make, model]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The name people call it by: the nickname, else the model, else the kind.
    var displayName: String {
        if let nickname, !nickname.trimmingCharacters(in: .whitespaces).isEmpty { return nickname }
        if let model, !model.isEmpty { return model }
        if let make, !make.isEmpty { return make }
        return kind.title
    }

    /// "Toyota Tacoma" for searches where the year only adds noise.
    var makeAndModel: String {
        [make, model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    var enabledTasks: [MaintenanceTask] {
        (tasks ?? []).filter(\.isEnabled).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    var sortedEntries: [ServiceEntry] {
        (entries ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var facts: [VehicleFact] {
        get {
            guard let data = factsJSON?.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([VehicleFact].self, from: data) else { return [] }
            return decoded
        }
        set {
            factsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }
}

/// A line on the vehicle's card: oil type, tire size, paint code. The things
/// people otherwise look up in the manual every single time.
struct VehicleFact: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var label: String
    var value: String

    static let suggestions: [String] = ["Oil", "Oil filter", "Tire size", "Tire pressure", "Wiper sizes", "Battery", "Paint code", "Key fob battery", "Spare key"]
}

@objc(MaintenanceTask)
final class MaintenanceTask: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var createdAt: Date?
    @NSManaged var catalogKey: String?
    @NSManaged var name: String?
    @NSManaged var symbol: String?
    @NSManaged var intervalDistance: Double
    @NSManaged var intervalMonths: Int16
    /// "Last done" an owner told us about without logging it, such as the oil
    /// change from before they had the app. Negative reading means unknown.
    @NSManaged var baselineDate: Date?
    @NSManaged var baselineReading: Double
    @NSManaged var isEnabled: Bool
    @NSManaged var notes: String?
    @NSManaged var vehicle: Vehicle?

    var displayName: String { name ?? "Maintenance" }
    var displaySymbol: String { symbol ?? "wrench.adjustable" }
}

@objc(ServiceEntry)
final class ServiceEntry: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var createdAt: Date?
    @NSManaged var date: Date?
    @NSManaged var reading: Double
    @NSManaged var title: String?
    /// Newline-separated ids of the schedule items this visit covered.
    @NSManaged var taskIDs: String?
    @NSManaged var cost: Double
    @NSManaged var shop: String?
    @NSManaged var isDIY: Bool
    @NSManaged var notes: String?
    @NSManaged var loggedBy: String?
    @NSManaged var kindRaw: String?
    /// The NHTSA campaign a recall visit closed, so the whole family sees it fixed.
    @NSManaged var recallCampaign: String?
    @NSManaged var vehicle: Vehicle?
    @NSManaged var attachments: Set<Attachment>?

    var kind: EntryKind {
        get { kindRaw.flatMap(EntryKind.init(rawValue:)) ?? .service }
        set { kindRaw = newValue.rawValue }
    }

    var coveredTaskIDs: [UUID] {
        get { (taskIDs ?? "").split(separator: "\n").compactMap { UUID(uuidString: String($0)) } }
        set { taskIDs = newValue.map(\.uuidString).joined(separator: "\n") }
    }

    var hasReading: Bool { reading >= 0 }

    var sortedAttachments: [Attachment] {
        (attachments ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }
}

@objc(Attachment)
final class Attachment: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var createdAt: Date?
    @NSManaged var kindRaw: String?
    @NSManaged var data: Data?
    @NSManaged var entry: ServiceEntry?

    var isReceipt: Bool { kindRaw == "receipt" }
}

@objc(MeterReading)
final class MeterReading: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var date: Date?
    @NSManaged var value: Double
    @NSManaged var loggedBy: String?
    @NSManaged var vehicle: Vehicle?
}

@objc(Valuation)
final class Valuation: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var date: Date?
    @NSManaged var amount: Double
    @NSManaged var source: String?
    @NSManaged var vehicle: Vehicle?
}
