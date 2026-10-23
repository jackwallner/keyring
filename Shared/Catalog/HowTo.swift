import Foundation

/// A basic job an owner can do without a shop, opened as a video search for
/// this exact vehicle so the steps match what's in the driveway.
struct HowToGuide: Identifiable, Hashable, Sendable {
    let title: String
    let symbol: String
    let query: String
    /// Engine-only jobs (oil, air filter) drop out for an electric or engineless vehicle.
    var needsEngine = false

    var id: String { title }
}

enum HowToCatalog {
    static func guides(for vehicle: Vehicle) -> [HowToGuide] {
        guides(for: vehicle.kind, powertrain: vehicle.powertrain)
    }

    static func guides(for kind: VehicleKind, powertrain: Powertrain) -> [HowToGuide] {
        list(for: kind).filter { !$0.needsEngine || powertrain.burnsFuel }
    }

    /// "how to change a flat tire 2019 Toyota Tacoma" on YouTube.
    static func url(for guide: HowToGuide, vehicle descriptor: String, kind: VehicleKind) -> URL {
        let subject = descriptor.trimmed.isEmpty ? kind.title.lowercased() : descriptor
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: "\(guide.query) \(subject)")]
        return components.url!
    }

    private static func list(for kind: VehicleKind) -> [HowToGuide] {
        switch kind {
        case .car, .truck, .suv, .van: road
        case .motorcycle, .scooter: motorcycle
        case .rv: rv
        case .camper: camper
        case .trailer: trailer
        case .boat, .sailboat, .personalWatercraft: boat
        case .aircraft: aircraft
        case .atv, .snowmobile: powersport
        case .tractor: tractor
        case .ebike: ebike
        case .golfCart: golfCart
        case .other: other
        }
    }

    private static let flatTire = HowToGuide(title: "Change a flat tire", symbol: "lifepreserver", query: "how to change a flat tire")
    private static let jumpStart = HowToGuide(title: "Jump-start the battery", symbol: "bolt.fill", query: "how to jump start")
    private static let tirePressure = HowToGuide(title: "Check tire pressure", symbol: "gauge.with.dots.needle.33percent", query: "how to check tire pressure")
    private static let checkOil = HowToGuide(title: "Check the oil", symbol: "oilcan.fill", query: "how to check the oil level", needsEngine: true)

    private static let road: [HowToGuide] = [
        flatTire,
        jumpStart,
        HowToGuide(title: "Add washer fluid", symbol: "drop.fill", query: "how to add windshield washer fluid"),
        HowToGuide(title: "Replace wiper blades", symbol: "windshield.front.and.wiper", query: "how to replace wiper blades"),
        checkOil,
        tirePressure,
        HowToGuide(title: "Replace the engine air filter", symbol: "wind", query: "how to replace engine air filter", needsEngine: true),
        HowToGuide(title: "Replace the cabin air filter", symbol: "fan.fill", query: "how to replace cabin air filter"),
        HowToGuide(title: "Replace a headlight bulb", symbol: "lightbulb.fill", query: "how to replace headlight bulb"),
    ]

    private static let motorcycle: [HowToGuide] = [
        tirePressure,
        HowToGuide(title: "Clean and lube the chain", symbol: "link", query: "how to clean and lube motorcycle chain"),
        HowToGuide(title: "Adjust chain slack", symbol: "arrow.left.and.right", query: "how to adjust motorcycle chain slack"),
        checkOil,
        HowToGuide(title: "Plug a tubeless tire", symbol: "lifepreserver", query: "how to plug a tubeless motorcycle tire"),
        HowToGuide(title: "Charge the battery", symbol: "bolt.fill", query: "how to charge motorcycle battery"),
    ]

    private static let towed: [HowToGuide] = [
        HowToGuide(title: "Change a trailer tire", symbol: "lifepreserver", query: "how to change a trailer tire"),
        tirePressure,
        HowToGuide(title: "Hitch up safely", symbol: "link", query: "how to hitch a trailer safely"),
        HowToGuide(title: "Grease the wheel bearings", symbol: "gearshape.fill", query: "how to grease trailer wheel bearings"),
    ]

    private static let living: [HowToGuide] = [
        HowToGuide(title: "Dump the tanks", symbol: "drop.fill", query: "how to dump black and grey tanks"),
        HowToGuide(title: "Winterize the water lines", symbol: "snowflake", query: "how to winterize water system"),
    ]

    private static let rv: [HowToGuide] = [flatTire, tirePressure] + living + [
        HowToGuide(title: "Jump the house batteries", symbol: "bolt.fill", query: "how to charge house batteries"),
        checkOil,
    ]
    private static let camper: [HowToGuide] = towed + living
    private static let trailer: [HowToGuide] = towed

    private static let boat: [HowToGuide] = [
        HowToGuide(title: "Launch and retrieve", symbol: "sailboat.fill", query: "how to launch and retrieve at a boat ramp"),
        HowToGuide(title: "Flush the engine", symbol: "drop.fill", query: "how to flush engine with fresh water", needsEngine: true),
        HowToGuide(title: "Replace the impeller", symbol: "fan.fill", query: "how to replace water pump impeller", needsEngine: true),
        HowToGuide(title: "Change the gear oil", symbol: "oilcan.fill", query: "how to change lower unit gear oil", needsEngine: true),
        HowToGuide(title: "Test the bilge pump", symbol: "water.waves", query: "how to test bilge pump"),
        HowToGuide(title: "Winterize", symbol: "snowflake", query: "how to winterize"),
    ]

    private static let aircraft: [HowToGuide] = [
        HowToGuide(title: "Walk the preflight", symbol: "checklist", query: "preflight inspection walkthrough"),
        HowToGuide(title: "Check and add oil", symbol: "oilcan.fill", query: "how to check and add oil", needsEngine: true),
        tirePressure,
        HowToGuide(title: "Clean the windscreen", symbol: "sparkles", query: "how to clean acrylic windscreen"),
    ]

    private static let powersport: [HowToGuide] = [
        HowToGuide(title: "Change the oil", symbol: "oilcan.fill", query: "how to change the oil", needsEngine: true),
        HowToGuide(title: "Clean the air filter", symbol: "wind", query: "how to clean air filter", needsEngine: true),
        HowToGuide(title: "Charge the battery", symbol: "bolt.fill", query: "how to charge battery"),
        tirePressure,
        HowToGuide(title: "Store for the season", symbol: "archivebox.fill", query: "how to store for the off season"),
    ]

    private static let tractor: [HowToGuide] = [
        HowToGuide(title: "Change the oil", symbol: "oilcan.fill", query: "how to change the oil", needsEngine: true),
        HowToGuide(title: "Sharpen the blades", symbol: "scissors", query: "how to sharpen mower blades"),
        HowToGuide(title: "Replace the air filter", symbol: "wind", query: "how to replace air filter", needsEngine: true),
        HowToGuide(title: "Charge the battery", symbol: "bolt.fill", query: "how to charge battery"),
        tirePressure,
    ]

    private static let ebike: [HowToGuide] = [
        HowToGuide(title: "Fix a flat", symbol: "lifepreserver", query: "how to fix a flat bike tire"),
        HowToGuide(title: "Clean and lube the chain", symbol: "link", query: "how to clean and lube a bike chain"),
        HowToGuide(title: "Adjust the brakes", symbol: "hand.raised.fill", query: "how to adjust bike brakes"),
        tirePressure,
        HowToGuide(title: "Care for the battery", symbol: "battery.75percent", query: "how to charge and store e-bike battery"),
    ]

    private static let golfCart: [HowToGuide] = [
        HowToGuide(title: "Water the batteries", symbol: "drop.fill", query: "how to water golf cart batteries"),
        HowToGuide(title: "Clean battery terminals", symbol: "bolt.fill", query: "how to clean golf cart battery terminals"),
        tirePressure,
        checkOil,
    ]

    private static let other: [HowToGuide] = [
        tirePressure,
        checkOil,
        HowToGuide(title: "Charge the battery", symbol: "bolt.fill", query: "how to charge battery"),
        HowToGuide(title: "Store for the season", symbol: "archivebox.fill", query: "how to store for the off season"),
    ]
}
