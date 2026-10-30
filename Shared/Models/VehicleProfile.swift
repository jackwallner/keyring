import Foundation

/// Setup choices and odometer history that shape a vehicle's schedule and
/// record, kept as one JSON field so new choices need no schema change.
/// Raw strings survive a newer app's values that this build doesn't know.
struct VehicleProfile: Codable, Equatable, Sendable {
    var traitsRaw: [String] = []
    var driveRaw: String?
    var odometerChanges: [OdometerChange] = []
    var mileageStatusRaw: String?
    var roadside: RoadsideInfo?

    var traits: Set<VehicleTrait> {
        get { Set(traitsRaw.compactMap(VehicleTrait.init(rawValue:))) }
        set {
            let unknown = traitsRaw.filter { VehicleTrait(rawValue: $0) == nil }
            traitsRaw = unknown + VehicleTrait.allCases.filter(newValue.contains).map(\.rawValue)
        }
    }

    var drive: FinalDrive? {
        get { driveRaw.flatMap(FinalDrive.init(rawValue:)) }
        set { driveRaw = newValue?.rawValue }
    }

    var mileageStatus: MileageStatus {
        get { mileageStatusRaw.flatMap(MileageStatus.init(rawValue:)) ?? .actual }
        set { mileageStatusRaw = newValue == .actual ? nil : newValue.rawValue }
    }

    /// Distance the odometer no longer shows, added to what it reads on
    /// `date` to give the vehicle's true total.
    func offset(on date: Date) -> Double {
        odometerChanges.filter { $0.date <= date }.reduce(0) { $0 + $1.offset }
    }

    static func decode(_ json: String) -> VehicleProfile? {
        json.data(using: .utf8).flatMap { try? JSONDecoder().decode(VehicleProfile.self, from: $0) }
    }

    var encoded: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// How a vehicle is used, beyond its kind. Each adds catalog jobs.
enum VehicleTrait: String, CaseIterable, Identifiable, Codable, Sendable {
    case fourByFour, track, collector

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fourByFour: "4x4 or transfer case"
        case .track: "Track days"
        case .collector: "Collector, driven little"
        }
    }

    var detail: String {
        switch self {
        case .fourByFour: "Front and rear diffs, transfer case, driveline grease"
        case .track: "Brake fluid, pads and torque checks around every event"
        case .collector: "Fluids and tires by age, a monthly drive, battery tender"
        }
    }

    var symbol: String {
        switch self {
        case .fourByFour: "mountain.2.fill"
        case .track: "flag.checkered"
        case .collector: "star.fill"
        }
    }

    static func choices(for kind: VehicleKind) -> [VehicleTrait] {
        switch kind {
        case .car, .van: [.track, .collector]
        case .truck, .suv: [.fourByFour, .track, .collector]
        case .motorcycle: [.track, .collector]
        default: []
        }
    }
}

/// A motorcycle's final drive, which decides chain care versus belt or shaft.
enum FinalDrive: String, CaseIterable, Identifiable, Codable, Sendable {
    case chain, belt, shaft

    var id: String { rawValue }
    var title: String {
        switch self {
        case .chain: "Chain"
        case .belt: "Belt"
        case .shaft: "Shaft"
        }
    }
}

/// An odometer that rolled over or was swapped. The true total carries on.
struct OdometerChange: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    /// What it showed just before.
    var lastShown: Double
    /// What it showed just after: 0 for a rollover, the new unit's figure
    /// for a replacement.
    var newShown: Double
    var replaced: Bool

    var offset: Double { lastShown - newShown }
}

/// The title-branding words for an odometer that can't be taken at face value.
enum MileageStatus: String, CaseIterable, Identifiable, Codable, Sendable {
    case actual, notActual, exempt

    var id: String { rawValue }
    var title: String {
        switch self {
        case .actual: "Actual mileage"
        case .notActual: "Not actual mileage (TMU)"
        case .exempt: "Exempt"
        }
    }
}

/// Something that happened to a vehicle that brings jobs due regardless of
/// the meter: a track day, a river crossing.
enum UsageEvent: String, CaseIterable, Identifiable, Codable, Sendable {
    case trackDay, waterCrossing, dust, saltwater

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trackDay: "Track day"
        case .waterCrossing: "Water crossing"
        case .dust: "Dusty ride"
        case .saltwater: "Saltwater run"
        }
    }

    /// "Due after every track day."
    var dueRule: String {
        switch self {
        case .trackDay: "Every track day"
        case .waterCrossing: "After a water crossing"
        case .dust: "After a dusty ride"
        case .saltwater: "After a saltwater run"
        }
    }

    var symbol: String {
        switch self {
        case .trackDay: "flag.checkered"
        case .waterCrossing: "water.waves"
        case .dust: "aqi.high"
        case .saltwater: "drop.fill"
        }
    }

    static func choices(for kind: VehicleKind) -> [UsageEvent] {
        switch kind {
        case .car, .van, .motorcycle: [.trackDay, .waterCrossing, .dust]
        case .truck, .suv, .atv: [.waterCrossing, .dust, .trackDay]
        case .boat, .sailboat, .personalWatercraft: [.saltwater]
        case .snowmobile, .scooter: [.dust]
        default: [.waterCrossing, .dust]
        }
    }
}

/// Structured extras on a logged entry, kept as one JSON field.
struct EntryDetails: Codable, Equatable, Sendable {
    var parts: [EntryPart] = []
    var specs: [EntrySpec] = []
    var eventRaw: String?
    /// When a mod came off the vehicle; it stays in the history.
    var removedOn: Date?

    var event: UsageEvent? {
        get { eventRaw.flatMap(UsageEvent.init(rawValue:)) }
        set { eventRaw = newValue?.rawValue }
    }

    var isEmpty: Bool { parts.isEmpty && specs.isEmpty && eventRaw == nil && removedOn == nil }

    /// What the parts add up to, when every part has a price.
    var partsTotal: Double? {
        let priced = parts.compactMap(\.lineTotal)
        return priced.isEmpty ? nil : priced.reduce(0, +)
    }

    static func decode(_ json: String) -> EntryDetails? {
        json.data(using: .utf8).flatMap { try? JSONDecoder().decode(EntryDetails.self, from: $0) }
    }

    var encoded: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

struct EntryPart: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name = ""
    var brand = ""
    var number = ""
    var quantity: Double?
    var price: Double?

    var lineTotal: Double? { price.map { $0 * (quantity ?? 1) } }
    var isBlank: Bool { name.trimmed.isEmpty && number.trimmed.isEmpty && brand.trimmed.isEmpty }

    /// "Hawk DTC-60 front pads · HB453G.654"
    var summary: String {
        let label = [brand.trimmed, name.trimmed].filter { !$0.isEmpty }.joined(separator: " ")
        let qty = (quantity ?? 1) != 1 ? "\(Format.number(quantity ?? 1)) × " : ""
        return [qty + label, number.trimmed].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// A figure worth keeping: a torque, a pressure, camber, an oil analysis
/// result. Named the same twice, it becomes a trend.
struct EntrySpec: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name = ""
    var value = ""
    var unit = ""

    var number: Double? { Double(value.trimmed.replacingOccurrences(of: ",", with: "")) }
    var isBlank: Bool { name.trimmed.isEmpty || value.trimmed.isEmpty }
    var display: String { [value.trimmed, unit.trimmed].filter { !$0.isEmpty }.joined(separator: " ") }

    static let suggestions: [(name: String, unit: String)] = [
        ("Lug nut torque", "ft-lb"), ("Tire pressure front", "psi"), ("Tire pressure rear", "psi"),
        ("Camber front", "°"), ("Toe front", "in"), ("Oil", ""), ("Brake fluid", ""),
        ("Pad thickness", "mm"), ("Iron (oil analysis)", "ppm"), ("Copper (oil analysis)", "ppm"),
        ("Lead (oil analysis)", "ppm"), ("Wheel horsepower", "whp"),
    ]
}

/// What a noted value was. Insurers and buyers weigh them differently.
enum ValuationKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case estimate, appraisal, agreedValue, offer

    var id: String { rawValue }
    var title: String {
        switch self {
        case .estimate: "Estimate"
        case .appraisal: "Appraisal"
        case .agreedValue: "Agreed value (insurance)"
        case .offer: "Offer"
        }
    }
}

extension Vehicle {
    /// The true total for what the odometer showed on `date`.
    func trueReading(shown value: Double, on date: Date = .now) -> Double {
        value + profile.offset(on: date)
    }

    /// What the odometer shows for a true total recorded on `date`.
    func shownReading(true value: Double, on date: Date = .now) -> Double {
        value - profile.offset(on: date)
    }

    var shownReading: Double { shownReading(true: reading) }

    var traits: Set<VehicleTrait> { profile.traits }
}
