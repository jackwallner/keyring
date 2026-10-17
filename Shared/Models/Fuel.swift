import Foundation

/// The unit the pump shows: gallons in the US, liters nearly everywhere else.
/// Fill-ups are stored in liters and shown in this unit.
enum FuelVolumeUnit: String, Sendable {
    case gallons, liters

    static var current: FuelVolumeUnit { Locale.current.measurementSystem == .us ? .gallons : .liters }

    static let litersPerGallon = 3.785411784
    static let litersPerImperialGallon = 4.54609

    var short: String { self == .gallons ? "gal" : "L" }
    var name: String { self == .gallons ? "gallon" : "liter" }
    var plural: String { self == .gallons ? "Gallons" : "Liters" }

    func liters(_ value: Double) -> Double { self == .gallons ? value * Self.litersPerGallon : value }
    func fromLiters(_ liters: Double) -> Double { self == .gallons ? liters / Self.litersPerGallon : liters }

    /// A price per this unit as a price per liter, and back.
    func perLiter(_ price: Double) -> Double { self == .gallons ? price / Self.litersPerGallon : price }
    func fromPerLiter(_ price: Double) -> Double { self == .gallons ? price * Self.litersPerGallon : price }
}

enum FuelGrade: String, CaseIterable, Identifiable, Sendable {
    case regular, midgrade, premium, e85, diesel, ethanolFree, avgas, jetA

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: "Regular"
        case .midgrade: "Midgrade"
        case .premium: "Premium"
        case .e85: "E85"
        case .diesel: "Diesel"
        case .ethanolFree: "Ethanol-free"
        case .avgas: "100LL"
        case .jetA: "Jet A"
        }
    }

    /// What a vehicle like this actually takes, most likely first.
    static func choices(for kind: VehicleKind, powertrain: Powertrain) -> [FuelGrade] {
        switch (kind, powertrain) {
        case (_, .diesel): [.diesel]
        case (.aircraft, .turbine): [.jetA]
        case (.aircraft, _): [.avgas, .ethanolFree]
        case (.boat, _), (.sailboat, _), (.personalWatercraft, _), (.atv, _), (.snowmobile, _), (.tractor, _), (.golfCart, _):
            [.regular, .ethanolFree, .midgrade, .premium, .diesel]
        case (.rv, _), (.truck, _): [.regular, .midgrade, .premium, .diesel, .e85]
        case (.other, _): allCases
        default: [.regular, .midgrade, .premium, .e85]
        }
    }
}

extension Vehicle {
    /// Fill-ups make sense for anything with a fuel tank.
    var takesFuel: Bool { powertrain.burnsFuel && !isRetired }

    var fuelEntries: [ServiceEntry] { sortedEntries.filter { $0.kind == .fuel } }

    /// Everything but fill-ups: the maintenance log a buyer or a shop reads.
    var serviceEntries: [ServiceEntry] { sortedEntries.filter { $0.kind != .fuel } }

    var fuelGradeChoices: [FuelGrade] { FuelGrade.choices(for: kind, powertrain: powertrain) }
}

extension ServiceEntry {
    var grade: FuelGrade? {
        get { fuelGrade.flatMap(FuelGrade.init(rawValue:)) }
        set { fuelGrade = newValue?.rawValue }
    }
}

/// Fuel economy the way people work it out at the pump: fill the tank, and the
/// next full fill-up's distance over the fuel it took (counting any top-ups in
/// between) is the figure.
struct FuelEconomy: Equatable, Sendable {
    struct Fill: Sendable {
        let id: UUID
        let date: Date
        let reading: Double?
        let liters: Double
        let partial: Bool
    }

    let meter: MeterUnit
    let unit: FuelVolumeUnit

    /// The figure for each full fill-up that has a full one before it.
    func values(_ fills: [Fill]) -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        for (distance, liters, id) in segments(fills) {
            if let value = figure(distance: distance, liters: liters) { result[id] = value }
        }
        return result
    }

    /// Over every measured stretch, so long trips weigh more than short ones.
    func average(_ fills: [Fill]) -> Double? {
        let all = segments(fills).filter { figure(distance: $0.0, liters: $0.1) != nil }
        let distance = all.reduce(0) { $0 + $1.0 }
        let liters = all.reduce(0) { $0 + $1.1 }
        return figure(distance: distance, liters: liters)
    }

    func format(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) \(label)"
    }

    /// mpg and km per gallon read higher-is-better; liters per 100 km and per
    /// hour read lower-is-better.
    var label: String {
        switch (meter, unit) {
        case (.hours, _): "\(unit.short)/hr"
        case (.miles, _): "mpg"
        case (.kilometers, .gallons): "km/gal"
        default: "L/100 km"
        }
    }

    private func figure(distance: Double, liters: Double) -> Double? {
        guard distance > 0, liters > 0 else { return nil }
        let value: Double
        let range: ClosedRange<Double>
        switch (meter, unit) {
        case (.hours, _):
            value = unit.fromLiters(liters) / distance
            range = 0.05...150
        case (.miles, .gallons):
            value = distance / (liters / FuelVolumeUnit.litersPerGallon)
            range = 3...200
        case (.miles, .liters):
            // Britain buys liters and quotes imperial mpg.
            value = distance / (liters / FuelVolumeUnit.litersPerImperialGallon)
            range = 3...240
        case (.kilometers, .gallons):
            value = distance / (liters / FuelVolumeUnit.litersPerGallon)
            range = 5...320
        default:
            value = liters / distance * 100
            range = 1...80
        }
        // A typo in a reading makes a figure nobody's engine could manage.
        return range.contains(value) ? value : nil
    }

    private func segments(_ fills: [Fill]) -> [(Double, Double, UUID)] {
        let ordered = fills.sorted { ($0.date, $0.reading ?? 0) < ($1.date, $1.reading ?? 0) }
        var result: [(Double, Double, UUID)] = []
        var anchor: Double?
        var used = 0.0
        for fill in ordered {
            if anchor != nil { used += fill.liters }
            guard !fill.partial else { continue }
            guard let reading = fill.reading else {
                // A full tank with no reading starts nothing measurable.
                anchor = nil
                used = 0
                continue
            }
            if let start = anchor, reading > start { result.append((reading - start, used, fill.id)) }
            anchor = reading
            used = 0
        }
        return result
    }
}

extension FuelEconomy {
    @MainActor
    static func fills(for vehicle: Vehicle) -> [Fill] {
        vehicle.fuelEntries.compactMap { entry in
            guard let id = entry.id, let date = entry.date, entry.fuelVolume > 0 else { return nil }
            return Fill(id: id, date: date, reading: entry.hasReading ? entry.reading : nil, liters: entry.fuelVolume, partial: entry.fuelPartial)
        }
    }
}

extension FuelEconomy {
    /// Each fill-up's figure, ready to show, keyed by entry id.
    @MainActor
    static func labels(for vehicles: [Vehicle]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for vehicle in vehicles where vehicle.entries?.contains(where: { $0.kind == .fuel }) == true {
            let economy = FuelEconomy(meter: vehicle.meter, unit: .current)
            for (id, value) in economy.values(fills(for: vehicle)) { result[id] = economy.format(value) }
        }
        return result
    }
}

extension ServiceEntry {
    /// "12.35 gal" in the unit this iPhone's pumps show.
    var fuelVolumeText: String? {
        guard fuelVolume > 0 else { return nil }
        let unit = FuelVolumeUnit.current
        return "\(unit.fromLiters(fuelVolume).formatted(.number.precision(.fractionLength(0...2)))) \(unit.short)"
    }
}
