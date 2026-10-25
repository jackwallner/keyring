import Foundation

/// Every kind of thing a family keeps running. The kind picks the icon, the
/// meter, the schedule and the suggestions, so it is the one choice that
/// shapes everything else about a vehicle.
enum VehicleKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case car, truck, suv, van, motorcycle, scooter
    case rv, camper, trailer
    case boat, sailboat, personalWatercraft
    case aircraft
    case atv, snowmobile, tractor
    case ebike, golfCart
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .car: "Car"
        case .truck: "Truck"
        case .suv: "SUV"
        case .van: "Van"
        case .motorcycle: "Motorcycle"
        case .scooter: "Scooter"
        case .rv: "Motorhome"
        case .camper: "Camper"
        case .trailer: "Trailer"
        case .boat: "Boat"
        case .sailboat: "Sailboat"
        case .personalWatercraft: "Personal watercraft"
        case .aircraft: "Aircraft"
        case .atv: "ATV / UTV"
        case .snowmobile: "Snowmobile"
        case .tractor: "Tractor / Mower"
        case .ebike: "Bike / E-bike"
        case .golfCart: "Golf Cart"
        case .other: "Other"
        }
    }

    /// SF Symbol name. `VehicleKindTests` proves each one exists on iOS 17.
    var symbol: String {
        switch self {
        case .car: "car.side.fill"
        case .truck: "truck.pickup.side.fill"
        case .suv: "suv.side.fill"
        case .van: "bus.fill"
        case .motorcycle: "motorcycle.fill"
        case .scooter: "scooter"
        case .rv: "bus.doubledecker.fill"
        case .camper: "tent.fill"
        case .trailer: "box.truck.fill"
        case .boat: "ferry.fill"
        case .sailboat: "sailboat.fill"
        case .personalWatercraft: "water.waves"
        case .aircraft: "airplane"
        case .atv: "car.rear.road.lane"
        case .snowmobile: "snowflake"
        case .tractor: "leaf.fill"
        case .ebike: "bicycle"
        case .golfCart: "figure.golf"
        case .other: "wrench.and.screwdriver.fill"
        }
    }

    /// The meter a new vehicle of this kind starts with. Owners can change it.
    var defaultMeter: MeterUnit {
        switch self {
        case .boat, .sailboat, .personalWatercraft, .aircraft, .tractor: .hours
        case .camper, .trailer: .miles
        case .golfCart: .none
        default: .miles
        }
    }

    var defaultPowertrain: Powertrain {
        switch self {
        case .ebike, .golfCart: .electric
        case .camper, .trailer, .sailboat: .none
        case .boat: .outboard
        case .aircraft: .piston
        default: .gasoline
        }
    }

    /// Powertrains worth offering for this kind, in the order a picker shows.
    var powertrainChoices: [Powertrain] {
        switch self {
        case .car, .suv, .van: [.gasoline, .hybrid, .plugInHybrid, .electric, .diesel]
        case .truck: [.gasoline, .diesel, .hybrid, .electric]
        case .motorcycle, .scooter: [.gasoline, .electric]
        case .rv: [.gasoline, .diesel]
        case .camper, .trailer: [.none]
        case .boat: [.outboard, .inboard, .sterndrive, .jetDrive, .electric]
        case .sailboat: [.none, .outboard, .inboard]
        case .personalWatercraft: [.jetDrive]
        case .aircraft: [.piston, .turbine]
        case .atv, .snowmobile: [.gasoline, .electric]
        case .tractor: [.gasoline, .diesel, .electric]
        case .ebike: [.electric, .none]
        case .golfCart: [.electric, .gasoline]
        case .other: Powertrain.allCases
        }
    }

    /// Kinds where a second meter is common enough to offer at setup: an RV
    /// or boat generator, a boat's second engine. Any vehicle can add one
    /// later (track hours, a UTV's miles beside its hours).
    var offersAuxMeter: Bool {
        switch self {
        case .rv, .camper, .boat, .sailboat, .atv: true
        default: false
        }
    }

    /// Names to suggest for a second meter, the first being the default.
    var auxMeterSuggestions: [(name: String, unit: MeterUnit)] {
        switch self {
        case .rv, .camper: [("Generator", .hours)]
        case .boat, .sailboat: [("Generator", .hours), ("Second engine", .hours)]
        case .atv: [("Odometer", .miles)]
        case .car, .truck, .suv, .van, .motorcycle: [("Track", .hours), ("Engine", .hours)]
        case .tractor, .personalWatercraft, .snowmobile: [("Odometer", .miles)]
        default: [("Engine", .hours)]
        }
    }

    /// Typical use per day in the vehicle's own meter, used to estimate when a
    /// distance-based item comes due until the owner's real pace is known.
    var typicalDailyUse: Double {
        switch self {
        case .car, .suv, .van: 33       // ~12,000 mi a year
        case .truck: 35
        case .motorcycle: 10
        case .scooter: 8
        case .rv: 14
        case .camper, .trailer: 8
        case .boat, .sailboat: 0.15     // ~55 engine hours a year
        case .personalWatercraft: 0.1
        case .aircraft: 0.25            // ~90 hours a year
        case .atv: 3
        case .snowmobile: 4
        case .tractor: 0.15
        case .ebike: 6
        case .golfCart: 0
        case .other: 10
        }
    }

    /// Road-registered kinds NHTSA covers for recalls and VIN decoding.
    var hasNHTSARecords: Bool {
        switch self {
        case .car, .truck, .suv, .van, .motorcycle, .scooter, .rv, .camper, .trailer: true
        default: false
        }
    }

    /// The word the app uses for this kind's serial number.
    var identifierLabel: String {
        switch self {
        case .boat, .sailboat, .personalWatercraft: "Hull ID (HIN)"
        case .aircraft: "Serial number"
        case .ebike, .golfCart, .tractor: "Serial number"
        default: "VIN"
        }
    }

    /// The word for the plate or registration mark.
    var registrationLabel: String {
        switch self {
        case .aircraft: "Tail number"
        case .boat, .sailboat, .personalWatercraft: "Registration number"
        default: "Plate"
        }
    }

    /// Groupings for the kind picker, so nineteen choices read as four.
    static let pickerSections: [(title: String, kinds: [VehicleKind])] = [
        ("On the road", [.car, .suv, .truck, .van, .motorcycle, .ebike, .scooter]),
        ("Camping and towing", [.rv, .camper, .trailer]),
        ("On the water and in the air", [.boat, .sailboat, .personalWatercraft, .aircraft]),
        ("Off road and around home", [.atv, .snowmobile, .tractor, .golfCart, .other]),
    ]
}

enum MeterUnit: String, CaseIterable, Identifiable, Codable, Sendable {
    case miles, kilometers, hours, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .miles: "Miles"
        case .kilometers: "Kilometers"
        case .hours: "Engine hours"
        case .none: "No meter"
        }
    }

    var short: String {
        switch self {
        case .miles: "mi"
        case .kilometers: "km"
        case .hours: "hrs"
        case .none: ""
        }
    }

    /// Choices for "How much is it used?", in this unit a year.
    var yearlyUseChoices: [Double] {
        switch self {
        case .miles: [3_000, 7_500, 12_000, 18_000]
        case .kilometers: [5_000, 12_000, 20_000, 30_000]
        case .hours: [25, 50, 100, 200]
        case .none: []
        }
    }

    var meterName: String {
        switch self {
        case .miles, .kilometers: "Odometer"
        case .hours: "Hour meter"
        case .none: "Meter"
        }
    }

    /// Room for an honest long trip before a new reading looks like a typo.
    var typoSlack: Double {
        switch self {
        case .miles: 1_500
        case .kilometers: 2_500
        case .hours: 60
        case .none: 0
        }
    }

    /// The same figure in another unit, when one converts (miles and
    /// kilometers do; hours never do).
    func convert(_ value: Double, to other: MeterUnit) -> Double? {
        switch (self, other) {
        case _ where self == other: value
        case (.miles, .kilometers): value * 1.609344
        case (.kilometers, .miles): value / 1.609344
        default: nil
        }
    }

    /// Catalog distances are written in miles. Kilometers convert and round to
    /// a figure a person would actually say; hours are never converted.
    func fromCatalogMiles(_ miles: Double) -> Double {
        switch self {
        case .kilometers:
            let km = miles * 1.609344
            let step: Double = km >= 10_000 ? 1_000 : (km >= 1_000 ? 500 : 50)
            return (km / step).rounded() * step
        default:
            return miles
        }
    }

    var hasReading: Bool { self != .none }
}

enum Powertrain: String, CaseIterable, Identifiable, Codable, Sendable {
    case gasoline, diesel, hybrid, plugInHybrid, electric
    case outboard, inboard, sterndrive, jetDrive
    case piston, turbine
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gasoline: "Gas"
        case .diesel: "Diesel"
        case .hybrid: "Hybrid"
        case .plugInHybrid: "Plug-in hybrid"
        case .electric: "Electric"
        case .outboard: "Outboard"
        case .inboard: "Inboard"
        case .sterndrive: "Sterndrive"
        case .jetDrive: "Jet drive"
        case .piston: "Piston"
        case .turbine: "Turbine"
        case .none: "No engine"
        }
    }

    var burnsFuel: Bool {
        switch self {
        case .electric, .none: false
        default: true
        }
    }
}

extension VehicleTint {
    /// A sensible first color per kind, so a new garage isn't a row of grays.
    static func defaultTint(for kind: VehicleKind) -> VehicleTint {
        switch kind {
        case .car: .navy
        case .suv: .racingGreen
        case .truck: .graphite
        case .van: .sky
        case .motorcycle, .scooter: .oxblood
        case .rv, .camper: .sand
        case .trailer: .silver
        case .boat, .personalWatercraft: .marine
        case .sailboat: .navy
        case .aircraft: .sky
        case .atv, .snowmobile: .orange
        case .tractor: .olive
        case .ebike, .golfCart: .plum
        case .other: .graphite
        }
    }
}

/// What a logged visit was. Maintenance is planned and restarts schedule
/// countdowns; a repair is the unplanned kind; a recall visit closes an NHTSA
/// campaign; a mod is money spent making it better, not keeping it running;
/// an event is a track day or a water crossing that brings jobs due. Kept
/// apart so the real cost of owning something shows.
enum EntryKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case service, repair, recall, fuel, mod, event

    /// Counted in what it costs to keep running.
    var isUpkeep: Bool { self == .service || self == .repair || self == .recall }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .service: "Maintenance"
        case .repair: "Repair"
        case .recall: "Recall"
        case .fuel: "Fill-up"
        case .mod: "Mod"
        case .event: "Event"
        }
    }

    var symbol: String {
        switch self {
        case .service: "wrench.and.screwdriver.fill"
        case .repair: "hammer.fill"
        case .recall: "exclamationmark.shield.fill"
        case .fuel: "fuelpump.fill"
        case .mod: "sparkles"
        case .event: "flag.checkered"
        }
    }
}
