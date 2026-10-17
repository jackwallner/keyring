import Foundation

/// One recommended job: what it is, how often, and what you'd need for it.
///
/// Intervals are conservative "normal use" figures drawn from owner's manual
/// norms and the published guidance noted in `source`. They are a starting
/// point the owner edits, never a claim about a specific model, and the app
/// says so wherever it shows them.
struct CatalogItem: Identifiable, Hashable, Sendable {
    let key: String
    let name: String
    let detail: String
    let symbol: String
    /// Distance interval when the vehicle's meter reads distance.
    var miles: Double? = nil
    /// Interval when the vehicle's meter reads engine hours.
    var hours: Double? = nil
    var months: Int? = nil
    /// Core items are switched on for a new vehicle; the rest wait in "Add from
    /// the catalog" so a new garage starts calm.
    var isCore = true
    var difficulty: Difficulty = .diy
    /// Amazon searches for the parts and tools. `{vehicle}` becomes
    /// "2019 Toyota Tacoma"; `{make}` becomes the make alone.
    var gear: [GearSuggestion] = []
    var source: String? = nil

    var id: String { key }

    enum Difficulty: String, Sendable {
        case diy, moderate, shop

        var title: String {
            switch self {
            case .diy: "Easy at home"
            case .moderate: "Handy owners"
            case .shop: "Usually a shop job"
            }
        }
    }

    /// The distance interval in the vehicle's own meter, or nil when the job is
    /// time-only for that meter.
    func distanceInterval(for meter: MeterUnit) -> Double? {
        switch meter {
        case .miles: miles
        case .kilometers: miles.map { meter.fromCatalogMiles($0) }
        case .hours: hours
        case .none: nil
        }
    }
}

struct GearSuggestion: Hashable, Sendable {
    let title: String
    let query: String
}

enum MaintenanceCatalog {
    /// Every job that applies to a vehicle of this kind and powertrain, core
    /// items first.
    static func items(for kind: VehicleKind, powertrain: Powertrain) -> [CatalogItem] {
        var list: [CatalogItem]
        switch kind {
        case .car, .suv, .van, .truck:
            list = powertrain == .electric ? electricRoad : roadEngine(powertrain)
        case .motorcycle:
            list = powertrain == .electric ? electricMotorcycle : motorcycle
        case .scooter:
            list = powertrain == .electric ? electricMotorcycle : scooter
        case .rv:
            list = roadEngine(powertrain) + rvHouse
        case .camper:
            list = rvHouse + trailerRunningGear
        case .trailer:
            list = trailerRunningGear
        case .boat:
            list = boatEngine(powertrain) + boatCommon
        case .sailboat:
            list = sailboatRig + (powertrain == .none ? [] : boatEngine(powertrain)) + boatCommon
        case .personalWatercraft:
            list = personalWatercraft
        case .aircraft:
            list = aircraft(powertrain)
        case .atv:
            list = atv
        case .snowmobile:
            list = snowmobile
        case .tractor:
            list = powertrain == .electric ? electricMower : tractor
        case .ebike:
            list = ebike
        case .golfCart:
            list = powertrain == .gasoline ? gasGolfCart : electricGolfCart
        case .other:
            list = generic
        }
        list += paperwork(for: kind)
        var seen = Set<String>()
        let unique = list.filter { seen.insert($0.key).inserted }
        return unique.filter(\.isCore) + unique.filter { !$0.isCore }
    }

    static func item(key: String, kind: VehicleKind, powertrain: Powertrain) -> CatalogItem? {
        items(for: kind, powertrain: powertrain).first { $0.key == key }
    }

    // MARK: - Road vehicles

    static func roadEngine(_ powertrain: Powertrain) -> [CatalogItem] {
        var items: [CatalogItem] = [
            CatalogItem(
                key: "oil", name: "Oil and filter", detail: "Fresh oil is the cheapest engine insurance there is. Most modern engines on synthetic run 5,000 to 10,000 miles; check your manual for yours.",
                symbol: "drop.fill", miles: 7_500, months: 12,
                gear: [.init(title: "Oil filter for your vehicle", query: "{vehicle} oil filter"),
                       .init(title: "Drain pan", query: "oil drain pan"),
                       .init(title: "Filter wrench", query: "oil filter wrench")],
                source: "Owner's manual norm; AAA"
            ),
            CatalogItem(
                key: "rotate", name: "Tire rotation", detail: "Moving tires front to back evens out wear, and most shops do it with the oil change.",
                symbol: "arrow.triangle.2.circlepath", miles: 7_500, months: 12,
                gear: [.init(title: "Torque wrench", query: "1/2 inch torque wrench"),
                       .init(title: "Floor jack and stands", query: "floor jack and jack stands")]
            ),
            CatalogItem(
                key: "cabinFilter", name: "Cabin air filter", detail: "Keeps dust and pollen out of the air you breathe. Usually a five minute job behind the glovebox.",
                symbol: "wind", miles: 15_000, months: 12,
                gear: [.init(title: "Cabin filter for your vehicle", query: "{vehicle} cabin air filter")]
            ),
            CatalogItem(
                key: "airFilter", name: "Engine air filter", detail: "A clogged filter costs power and fuel. Replace sooner on dusty roads.",
                symbol: "aqi.medium", miles: 30_000, months: 36,
                gear: [.init(title: "Engine air filter", query: "{vehicle} engine air filter")]
            ),
            CatalogItem(
                key: "brakes", name: "Brake inspection", detail: "Pads, rotors and lines checked before they're a problem.",
                symbol: "exclamationmark.octagon", miles: 15_000, months: 12, difficulty: .moderate,
                gear: [.init(title: "Brake pads", query: "{vehicle} brake pads")]
            ),
            CatalogItem(
                key: "wipers", name: "Wiper blades", detail: "Streaking or chattering means they're done. Sun kills them faster than use.",
                symbol: "windshield.front.and.wiper", months: 12,
                gear: [.init(title: "Wiper blades for your vehicle", query: "{vehicle} wiper blades")]
            ),
            CatalogItem(
                key: "battery", name: "Battery test", detail: "Most 12-volt batteries last three to five years. A free test at a parts store spots a weak one before a cold morning does.",
                symbol: "minus.plus.batteryblock", months: 12,
                gear: [.init(title: "Portable jump starter", query: "portable car jump starter"),
                       .init(title: "Battery tester", query: "12v battery load tester")]
            ),
            CatalogItem(
                key: "brakeFluid", name: "Brake fluid", detail: "Brake fluid absorbs water over time, which lowers its boiling point. Most makers say every two to three years.",
                symbol: "drop.triangle", months: 36, difficulty: .moderate,
                gear: [.init(title: "Brake bleeder kit", query: "one person brake bleeder kit")]
            ),
            CatalogItem(
                key: "coolant", name: "Coolant", detail: "Long-life coolant often goes 100,000 miles or more; older formulas need it sooner.",
                symbol: "thermometer.snowflake", miles: 100_000, months: 60, isCore: false, difficulty: .moderate
            ),
            CatalogItem(
                key: "transmission", name: "Transmission fluid", detail: "Even 'lifetime' fluid benefits from a change around 60,000 miles, more if you tow.",
                symbol: "gearshape.2", miles: 60_000, months: 60, isCore: false, difficulty: .shop
            ),
            CatalogItem(
                key: "alignment", name: "Wheel alignment", detail: "Pulling to one side or uneven tire wear are the tells. Check after hitting something hard.",
                symbol: "arrow.left.and.right", months: 24, isCore: false, difficulty: .shop
            ),
            CatalogItem(
                key: "belt", name: "Drive belt inspection", detail: "Cracks or squeals mean it's time.",
                symbol: "circle.dashed", miles: 60_000, months: 60, isCore: false, difficulty: .moderate
            ),
            CatalogItem(
                key: "tires", name: "New tires", detail: "Replace at 2/32 inch of tread, or about six years old whatever the tread says.",
                symbol: "circle.circle", miles: 50_000, months: 72, isCore: false, difficulty: .shop,
                gear: [.init(title: "Tread depth gauge", query: "tire tread depth gauge"),
                       .init(title: "Tire inflator", query: "portable tire inflator")]
            ),
        ]
        if powertrain == .gasoline || powertrain == .hybrid || powertrain == .plugInHybrid {
            items.append(CatalogItem(
                key: "plugs", name: "Spark plugs", detail: "Iridium plugs typically last around 100,000 miles.",
                symbol: "bolt.fill", miles: 100_000, isCore: false, difficulty: .moderate,
                gear: [.init(title: "Spark plugs", query: "{vehicle} spark plugs")]
            ))
        }
        if powertrain == .diesel {
            items.append(CatalogItem(
                key: "fuelFilter", name: "Fuel filter", detail: "Diesels are picky about clean fuel. Drain the water separator between changes.",
                symbol: "fuelpump", miles: 15_000, months: 12, difficulty: .moderate,
                gear: [.init(title: "Fuel filter", query: "{vehicle} fuel filter")]
            ))
            items.append(CatalogItem(
                key: "def", name: "DEF top-up", detail: "Diesel exhaust fluid runs out roughly every few thousand miles.",
                symbol: "drop.halffull", miles: 5_000, isCore: false,
                gear: [.init(title: "Diesel exhaust fluid", query: "diesel exhaust fluid 2.5 gallon")]
            ))
        }
        return items
    }

    static let electricRoad: [CatalogItem] = [
        CatalogItem(
            key: "rotate", name: "Tire rotation", detail: "EVs are heavy and quick, so tires wear faster. Rotation matters more than it does on a gas car.",
            symbol: "arrow.triangle.2.circlepath", miles: 6_500, months: 12,
            gear: [.init(title: "Torque wrench", query: "1/2 inch torque wrench"),
                   .init(title: "Tire inflator", query: "portable tire inflator")]
        ),
        CatalogItem(
            key: "cabinFilter", name: "Cabin air filter", detail: "The filter that keeps the cabin air clean. Every one to two years.",
            symbol: "wind", months: 24,
            gear: [.init(title: "Cabin filter for your vehicle", query: "{vehicle} cabin air filter")]
        ),
        CatalogItem(
            key: "brakeFluid", name: "Brake fluid check", detail: "Regenerative braking means the pads rarely work, but the fluid still ages.",
            symbol: "drop.triangle", months: 48, difficulty: .moderate
        ),
        CatalogItem(
            key: "brakes", name: "Brake clean and lube", detail: "Pads that rarely get used can seize, especially where roads are salted. Once a year in winter climates.",
            symbol: "exclamationmark.octagon", miles: 12_500, months: 12, difficulty: .shop
        ),
        CatalogItem(
            key: "wipers", name: "Wiper blades", detail: "Streaking or chattering means they're done.",
            symbol: "windshield.front.and.wiper", months: 12,
            gear: [.init(title: "Wiper blades for your vehicle", query: "{vehicle} wiper blades")]
        ),
        CatalogItem(
            key: "battery12v", name: "12-volt battery", detail: "The small battery that wakes the car still wears out, usually in four to six years.",
            symbol: "minus.plus.batteryblock", months: 48, isCore: false, difficulty: .moderate
        ),
        CatalogItem(
            key: "acDesiccant", name: "A/C desiccant", detail: "Some makers replace the A/C drying bag about every six years.",
            symbol: "snowflake", months: 72, isCore: false, difficulty: .shop
        ),
        CatalogItem(
            key: "tires", name: "New tires", detail: "Replace at 2/32 inch of tread. EV-rated tires are quieter and carry the weight.",
            symbol: "circle.circle", miles: 40_000, months: 72, isCore: false, difficulty: .shop,
            gear: [.init(title: "Tread depth gauge", query: "tire tread depth gauge")]
        ),
        CatalogItem(
            key: "charger", name: "Charging cable check", detail: "Look over the cable and plug for wear or heat marks.",
            symbol: "powerplug", months: 12, isCore: false
        ),
    ]

    // MARK: - Two wheels

    static let motorcycle: [CatalogItem] = [
        CatalogItem(
            key: "oil", name: "Oil and filter", detail: "Bikes work their oil hard, often sharing it with the clutch and gearbox. Most call for 3,000 to 6,000 miles.",
            symbol: "drop.fill", miles: 4_000, months: 12,
            gear: [.init(title: "Oil filter", query: "{vehicle} oil filter"),
                   .init(title: "Motorcycle oil", query: "motorcycle oil 10w40 synthetic")]
        ),
        CatalogItem(
            key: "chain", name: "Chain clean, lube and adjust", detail: "Every 300 to 600 miles and after riding in the rain. Skip it if you ride a belt or shaft drive.",
            symbol: "link", miles: 500, months: 1,
            gear: [.init(title: "Chain lube", query: "motorcycle chain lube"),
                   .init(title: "Chain brush", query: "motorcycle chain cleaning brush"),
                   .init(title: "Rear stand", query: "motorcycle rear paddock stand")]
        ),
        CatalogItem(
            key: "tires", name: "Tire check", detail: "Pressure, tread and age. Two contact patches the size of a credit card hold you up.",
            symbol: "circle.circle", months: 6,
            gear: [.init(title: "Tire pressure gauge", query: "motorcycle tire pressure gauge")]
        ),
        CatalogItem(
            key: "brakeFluid", name: "Brake fluid", detail: "Every two years. Clutch fluid too if the clutch is hydraulic.",
            symbol: "drop.triangle", months: 24, difficulty: .moderate
        ),
        CatalogItem(
            key: "airFilter", name: "Air filter", detail: "Sooner if you ride dusty roads.",
            symbol: "aqi.medium", miles: 8_000, months: 24,
            gear: [.init(title: "Air filter", query: "{vehicle} air filter")]
        ),
        CatalogItem(
            key: "plugs", name: "Spark plugs", detail: "Typically 8,000 to 16,000 miles depending on the engine.",
            symbol: "bolt.fill", miles: 12_000, isCore: false, difficulty: .moderate
        ),
        CatalogItem(
            key: "coolant", name: "Coolant", detail: "Liquid-cooled bikes, every two to three years.",
            symbol: "thermometer.snowflake", months: 24, isCore: false, difficulty: .moderate
        ),
        CatalogItem(
            key: "valves", name: "Valve clearance check", detail: "The big service. Intervals vary widely, so check your manual.",
            symbol: "gearshape.2", miles: 15_000, isCore: false, difficulty: .shop
        ),
        CatalogItem(
            key: "forks", name: "Fork oil", detail: "Fresh fork oil brings back the front end.",
            symbol: "arrow.up.and.down", miles: 20_000, months: 36, isCore: false, difficulty: .shop
        ),
        CatalogItem(
            key: "battery", name: "Battery tender over winter", detail: "A smart charger through the off season saves a dead battery in spring.",
            symbol: "minus.plus.batteryblock", months: 12, isCore: false,
            gear: [.init(title: "Battery tender", query: "motorcycle battery tender")]
        ),
    ]

    static let scooter: [CatalogItem] = [
        CatalogItem(key: "oil", name: "Oil change", detail: "Small engines, small oil capacity: change it often.", symbol: "drop.fill", miles: 2_000, months: 12,
                    gear: [.init(title: "Scooter oil", query: "4 stroke scooter oil 10w40")]),
        CatalogItem(key: "cvt", name: "Drive belt", detail: "The CVT belt is the part that strands scooters. Inspect it regularly.", symbol: "circle.dashed", miles: 6_000, difficulty: .moderate),
        CatalogItem(key: "tires", name: "Tire check", detail: "Pressure, tread and age.", symbol: "circle.circle", months: 6),
        CatalogItem(key: "plugs", name: "Spark plug", detail: "A cheap part that makes cold starts easy.", symbol: "bolt.fill", miles: 4_000, months: 24),
        CatalogItem(key: "airFilter", name: "Air filter", detail: "Clean or replace.", symbol: "aqi.medium", miles: 4_000, months: 24, isCore: false),
        CatalogItem(key: "brakes", name: "Brake check", detail: "Pads and fluid.", symbol: "exclamationmark.octagon", months: 12, isCore: false),
    ]

    static let electricMotorcycle: [CatalogItem] = [
        CatalogItem(key: "tires", name: "Tire check", detail: "Instant torque eats rear tires. Check pressure and tread.", symbol: "circle.circle", months: 3),
        CatalogItem(key: "belt", name: "Drive belt or chain", detail: "Inspect tension and wear.", symbol: "link", miles: 3_000, months: 6),
        CatalogItem(key: "brakeFluid", name: "Brake fluid", detail: "Every two years.", symbol: "drop.triangle", months: 24, difficulty: .moderate),
        CatalogItem(key: "storageCharge", name: "Storage charge", detail: "Park it between about 30 and 60 percent for long storage.", symbol: "battery.50", months: 6, isCore: false),
    ]

    // MARK: - RVs, campers and trailers

    static let rvHouse: [CatalogItem] = [
        CatalogItem(
            key: "roofSeals", name: "Roof and seal inspection", detail: "Water is the thing that kills RVs. Check roof sealant and every seam twice a year.",
            symbol: "house.fill", months: 6,
            gear: [.init(title: "Self-leveling sealant", query: "rv self leveling lap sealant"),
                   .init(title: "Eternabond tape", query: "eternabond rv roof tape")]
        ),
        CatalogItem(
            key: "propane", name: "Propane system and detectors", detail: "Leak check the LP system, and test the LP, CO and smoke detectors.",
            symbol: "flame", months: 12, difficulty: .moderate,
            gear: [.init(title: "LP leak detector", query: "propane leak detector rv")]
        ),
        CatalogItem(
            key: "waterHeater", name: "Water heater flush and anode", detail: "Flush the sediment and check the anode rod each season.",
            symbol: "drop.degreesign", months: 12,
            gear: [.init(title: "Anode rod", query: "rv water heater anode rod"),
                   .init(title: "Tank flush wand", query: "rv water heater flush wand")]
        ),
        CatalogItem(
            key: "freshWater", name: "Sanitize fresh water", detail: "Sanitize the tank and lines at the start of each season.",
            symbol: "drop", months: 12,
            gear: [.init(title: "Water pressure regulator", query: "rv water pressure regulator"),
                   .init(title: "Inline water filter", query: "rv inline water filter")]
        ),
        CatalogItem(
            key: "winterize", name: "Winterize", detail: "Blow out or antifreeze the plumbing before the first freeze.",
            symbol: "snowflake", months: 12,
            gear: [.init(title: "RV antifreeze", query: "rv plumbing antifreeze"),
                   .init(title: "Blowout plug", query: "rv winterizing blowout plug")]
        ),
        CatalogItem(key: "slides", name: "Slide-out seals and lube", detail: "Clean, condition and lube the slide mechanism.", symbol: "rectangle.expand.vertical", months: 12, isCore: false),
        CatalogItem(key: "houseBattery", name: "House batteries", detail: "Check water levels on flooded batteries, and terminals on all of them.", symbol: "battery.75", months: 3, isCore: false),
        CatalogItem(key: "generator", name: "Generator service", detail: "Oil change and an exercise run. Generators hate sitting.", symbol: "bolt.circle", months: 12, isCore: false, difficulty: .moderate),
        CatalogItem(key: "acFilters", name: "A/C filters", detail: "Wash the roof unit filters.", symbol: "air.conditioner.horizontal", months: 6, isCore: false),
    ]

    static let trailerRunningGear: [CatalogItem] = [
        CatalogItem(
            key: "bearings", name: "Wheel bearings", detail: "Repack or check bearings once a year or every 12,000 miles. Boat trailers that get dunked need them more.",
            symbol: "gearshape", miles: 12_000, months: 12, difficulty: .moderate,
            gear: [.init(title: "Bearing kit", query: "trailer wheel bearing kit"),
                   .init(title: "Marine grease", query: "marine wheel bearing grease")]
        ),
        CatalogItem(
            key: "trailerTires", name: "Tire age and pressure", detail: "Trailer tires age out before they wear out. Replace around five to six years from the date code.",
            symbol: "circle.circle", months: 60,
            gear: [.init(title: "Tire pressure gauge", query: "tire pressure gauge"),
                   .init(title: "Spare tire", query: "trailer spare tire")]
        ),
        CatalogItem(
            key: "lights", name: "Lights and wiring", detail: "Check every light and the plug before a trip.",
            symbol: "lightbulb", months: 12,
            gear: [.init(title: "Trailer wiring tester", query: "trailer light tester"),
                   .init(title: "LED trailer lights", query: "led trailer light kit")]
        ),
        CatalogItem(key: "trailerBrakes", name: "Trailer brakes", detail: "Adjust and inspect electric or surge brakes.", symbol: "exclamationmark.octagon", months: 12, isCore: false, difficulty: .moderate),
        CatalogItem(key: "coupler", name: "Coupler, chains and jack", detail: "Lube the coupler and jack, and check the safety chains.", symbol: "link", months: 12, isCore: false),
    ]

    // MARK: - Water

    static func boatEngine(_ powertrain: Powertrain) -> [CatalogItem] {
        if powertrain == .electric {
            return [
                CatalogItem(key: "boatBattery", name: "Battery care", detail: "Charge after every outing and store charged.", symbol: "battery.75", months: 6),
                CatalogItem(key: "prop", name: "Propeller inspection", detail: "Pull it, check for dings and fishing line, grease the shaft.", symbol: "fanblades", hours: 100, months: 12),
            ]
        }
        var items: [CatalogItem] = [
            CatalogItem(
                key: "oil", name: "Engine oil and filter", detail: "Most marine four-strokes call for 100 hours or once a season, whichever comes first.",
                symbol: "drop.fill", hours: 100, months: 12, difficulty: .moderate,
                gear: [.init(title: "Marine oil change kit", query: "{make} marine oil change kit")]
            ),
            CatalogItem(
                key: "impeller", name: "Water pump impeller", detail: "A cracked impeller overheats the engine fast. Most makers say every two to three years.",
                symbol: "fanblades.fill", hours: 300, months: 24, difficulty: .shop,
                gear: [.init(title: "Impeller kit", query: "{make} water pump impeller kit")]
            ),
            CatalogItem(
                key: "fuelSeparator", name: "Fuel/water separator", detail: "Ethanol fuel picks up water. A fresh filter protects the injectors.",
                symbol: "fuelpump", hours: 100, months: 12,
                gear: [.init(title: "Separator filter", query: "marine fuel water separator filter")]
            ),
            CatalogItem(
                key: "plugs", name: "Spark plugs", detail: "Once a season on most gas engines.",
                symbol: "bolt.fill", hours: 100, months: 12, isCore: false, difficulty: .moderate
            ),
            CatalogItem(
                key: "winterize", name: "Winterize or layup", detail: "Stabilize the fuel, fog the engine, drain or antifreeze, and change the oil before storage.",
                symbol: "snowflake", months: 12,
                gear: [.init(title: "Fuel stabilizer", query: "marine fuel stabilizer"),
                       .init(title: "Fogging oil", query: "engine fogging oil")]
            ),
        ]
        if powertrain == .outboard || powertrain == .sterndrive {
            items.insert(CatalogItem(
                key: "gearOil", name: "Lower unit gear oil", detail: "Milky gear oil means water got in. Change it every season.",
                symbol: "drop.halffull", hours: 100, months: 12,
                gear: [.init(title: "Gear lube and pump", query: "{make} lower unit gear lube pump")]
            ), at: 1)
            items.append(CatalogItem(
                key: "prop", name: "Propeller and shaft", detail: "Pull the prop, check for damage and fishing line, grease the shaft.",
                symbol: "fanblades", hours: 100, months: 12,
                gear: [.init(title: "Prop wrench", query: "boat propeller wrench")]
            ))
        }
        if powertrain == .sterndrive {
            items.append(CatalogItem(key: "bellows", name: "Bellows and gimbal bearing", detail: "Torn bellows sink boats. Inspect them every season.", symbol: "arrow.up.and.down.and.sparkles", months: 24, difficulty: .shop))
        }
        if powertrain == .inboard {
            items.append(CatalogItem(key: "transmissionFluid", name: "Transmission fluid", detail: "Marine gear oil, usually each season.", symbol: "gearshape.2", hours: 100, months: 12, difficulty: .moderate))
            items.append(CatalogItem(key: "alignment", name: "Shaft alignment and packing", detail: "Check the stuffing box drip and engine alignment.", symbol: "arrow.left.and.right", months: 24, isCore: false, difficulty: .shop))
        }
        if powertrain == .jetDrive {
            items.append(CatalogItem(key: "wearRing", name: "Wear ring and impeller", detail: "A worn ring costs top speed and holeshot.", symbol: "circle.dashed", hours: 100, months: 24, difficulty: .shop))
        }
        return items
    }

    static let boatCommon: [CatalogItem] = [
        CatalogItem(
            key: "anodes", name: "Anodes (zincs)", detail: "Sacrificial anodes protect the metal underwater. Replace at about half gone.",
            symbol: "hexagon", months: 12,
            gear: [.init(title: "Anode kit", query: "{make} anode kit")]
        ),
        CatalogItem(
            key: "safety", name: "Safety gear check", detail: "Life jackets, fire extinguisher, flare dates, horn and nav lights.",
            symbol: "lifepreserver", months: 12,
            gear: [.init(title: "Inflatable life jackets", query: "inflatable life jacket uscg approved"),
                   .init(title: "Marine extinguisher", query: "marine fire extinguisher")]
        ),
        CatalogItem(
            key: "bilge", name: "Bilge pump and float switch", detail: "Test it before you need it.",
            symbol: "drop.circle", months: 12
        ),
        CatalogItem(key: "boatBattery", name: "Batteries", detail: "Clean terminals, check charge, and keep them on a maintainer in storage.", symbol: "battery.75", months: 12, isCore: false,
                    gear: [.init(title: "Marine battery charger", query: "onboard marine battery charger")]),
        CatalogItem(key: "bottom", name: "Bottom paint and hull", detail: "Boats kept in the water need fresh antifouling every year or two.", symbol: "paintbrush", months: 24, isCore: false, difficulty: .shop),
        CatalogItem(key: "wax", name: "Wash and wax", detail: "Gelcoat oxidizes in the sun. Wax twice a season.", symbol: "sparkles", months: 6, isCore: false,
                    gear: [.init(title: "Marine wax", query: "marine gelcoat wax")]),
    ]

    static let sailboatRig: [CatalogItem] = [
        CatalogItem(key: "rigging", name: "Standing rigging inspection", detail: "Look for cracked swages, broken strands and loose pins. Many surveyors suggest replacing wire at ten to fifteen years.", symbol: "triangle", months: 12, difficulty: .moderate),
        CatalogItem(key: "sails", name: "Sails and running rigging", detail: "Check stitching, chafe and UV covers.", symbol: "sailboat", months: 12),
        CatalogItem(key: "winches", name: "Winch service", detail: "Strip, clean and grease each winch.", symbol: "gearshape", months: 12, isCore: false,
                    gear: [.init(title: "Winch service kit", query: "sailboat winch service kit")]),
    ]

    static let personalWatercraft: [CatalogItem] = [
        CatalogItem(key: "oil", name: "Oil and filter", detail: "About every 50 hours or each season.", symbol: "drop.fill", hours: 50, months: 12,
                    gear: [.init(title: "PWC oil change kit", query: "{make} pwc oil change kit")]),
        CatalogItem(key: "flush", name: "Freshwater flush", detail: "After every saltwater ride.", symbol: "drop", hours: 3, isCore: false),
        CatalogItem(key: "wearRing", name: "Wear ring and impeller", detail: "Check for nicks and wear.", symbol: "circle.dashed", hours: 100, months: 24, difficulty: .shop),
        CatalogItem(key: "plugs", name: "Spark plugs", detail: "Every 100 hours or two seasons.", symbol: "bolt.fill", hours: 100, months: 24),
        CatalogItem(key: "winterize", name: "Winterize", detail: "Stabilize fuel, fog, drain the exhaust, and pull the battery.", symbol: "snowflake", months: 12,
                    gear: [.init(title: "Fuel stabilizer", query: "marine fuel stabilizer")]),
        CatalogItem(key: "safety", name: "Safety gear check", detail: "Life jackets, extinguisher and the kill switch lanyard.", symbol: "lifepreserver", months: 12),
    ]

    // MARK: - Air

    static func aircraft(_ powertrain: Powertrain) -> [CatalogItem] {
        var items: [CatalogItem] = [
            CatalogItem(
                key: "annual", name: "Annual inspection", detail: "Required every 12 calendar months under 14 CFR 91.409.",
                symbol: "checkmark.seal", months: 12, difficulty: .shop, source: "14 CFR 91.409"
            ),
            CatalogItem(
                key: "elt", name: "ELT inspection", detail: "Required every 12 calendar months under 14 CFR 91.207(d). Check the battery expiration too.",
                symbol: "antenna.radiowaves.left.and.right", months: 12, difficulty: .shop, source: "14 CFR 91.207"
            ),
            CatalogItem(
                key: "transponder", name: "Transponder check", detail: "Every 24 calendar months under 14 CFR 91.413.",
                symbol: "dot.radiowaves.right", months: 24, difficulty: .shop, source: "14 CFR 91.413"
            ),
            CatalogItem(
                key: "pitotStatic", name: "Pitot-static and altimeter", detail: "Every 24 calendar months for IFR flight under 14 CFR 91.411.",
                symbol: "gauge.with.dots.needle.33percent", months: 24, difficulty: .shop, source: "14 CFR 91.411"
            ),
            CatalogItem(
                key: "registration", name: "Registration renewal", detail: "FAA aircraft registration runs seven years.",
                symbol: "doc.text", months: 84, source: "14 CFR 47.40"
            ),
            CatalogItem(
                key: "hundredHour", name: "100-hour inspection", detail: "Required when the aircraft is used for hire or flight instruction.",
                symbol: "clock.badge.checkmark", hours: 100, isCore: false, difficulty: .shop, source: "14 CFR 91.409(b)"
            ),
            CatalogItem(
                key: "vor", name: "VOR check", detail: "Within the preceding 30 days for IFR under 14 CFR 91.171.",
                symbol: "location.north.line", months: 1, isCore: false, source: "14 CFR 91.171"
            ),
        ]
        if powertrain == .piston {
            items.insert(CatalogItem(
                key: "oil", name: "Oil change", detail: "Commonly 50 hours with a full-flow filter, or every four months, whichever comes first.",
                symbol: "drop.fill", hours: 50, months: 4, difficulty: .moderate, source: "Engine maker guidance"
            ), at: 1)
            items.append(CatalogItem(key: "plugs", name: "Spark plug rotation", detail: "Clean, gap and rotate top to bottom.", symbol: "bolt.fill", hours: 100, isCore: false, difficulty: .shop))
        }
        return items
    }

    // MARK: - Off road and around home

    static let atv: [CatalogItem] = [
        CatalogItem(key: "oil", name: "Oil and filter", detail: "Dust and heat are hard on small engines. Every 100 hours, 1,000 miles or once a season.", symbol: "drop.fill", miles: 1_000, hours: 100, months: 12,
                    gear: [.init(title: "Oil change kit", query: "{vehicle} oil change kit")]),
        CatalogItem(key: "airFilter", name: "Air filter clean", detail: "After every dusty ride. A dirty filter is how ATV engines die.", symbol: "aqi.medium", miles: 250, hours: 25, months: 6,
                    gear: [.init(title: "Air filter", query: "{vehicle} air filter")]),
        CatalogItem(key: "cvt", name: "CVT belt inspection", detail: "Glazing or cracks mean replace it before it lets go on the trail.", symbol: "circle.dashed", miles: 1_000, hours: 50, months: 12, difficulty: .moderate,
                    gear: [.init(title: "Spare drive belt", query: "{vehicle} drive belt")]),
        CatalogItem(key: "diffs", name: "Differential and gearcase fluid", detail: "Front and rear differentials, once a year for most.", symbol: "gearshape.2", miles: 2_000, hours: 100, months: 24, difficulty: .moderate),
        CatalogItem(key: "grease", name: "Grease fittings", detail: "Suspension pivots and driveline.", symbol: "drop.triangle", miles: 250, hours: 25, months: 3, isCore: false,
                    gear: [.init(title: "Grease gun", query: "grease gun cordless")]),
        CatalogItem(key: "coolant", name: "Coolant", detail: "Every two years on liquid-cooled machines.", symbol: "thermometer.snowflake", months: 24, isCore: false),
    ]

    static let snowmobile: [CatalogItem] = [
        CatalogItem(key: "preseason", name: "Preseason check", detail: "Track, hyfax, carbides, belt and lights before the first ride.", symbol: "checklist", months: 12),
        CatalogItem(key: "chaincase", name: "Chaincase oil", detail: "Once a season.", symbol: "drop.halffull", months: 12),
        CatalogItem(key: "belt", name: "Drive belt", detail: "Carry a spare. Replace when glazed or narrow.", symbol: "circle.dashed", miles: 1_500, months: 12,
                    gear: [.init(title: "Spare drive belt", query: "{vehicle} drive belt")]),
        CatalogItem(key: "plugs", name: "Spark plugs", detail: "Once a season.", symbol: "bolt.fill", months: 12),
        CatalogItem(key: "storage", name: "Summer storage", detail: "Stabilize the fuel, fog the engine, and loosen the track.", symbol: "sun.max", months: 12,
                    gear: [.init(title: "Fuel stabilizer", query: "fuel stabilizer")]),
    ]

    static let tractor: [CatalogItem] = [
        CatalogItem(key: "oil", name: "Engine oil and filter", detail: "Most small engines call for 50 to 100 hours, or every season.", symbol: "drop.fill", hours: 50, months: 12,
                    gear: [.init(title: "Oil filter", query: "{vehicle} oil filter")]),
        CatalogItem(key: "airFilter", name: "Air filter", detail: "Clean often, replace yearly.", symbol: "aqi.medium", hours: 100, months: 12,
                    gear: [.init(title: "Air filter", query: "{vehicle} air filter")]),
        CatalogItem(key: "blades", name: "Sharpen blades", detail: "A sharp blade cuts grass cleanly instead of tearing it. About every 25 hours.", symbol: "scissors", hours: 25, months: 12,
                    gear: [.init(title: "Blade sharpener", query: "lawn mower blade sharpener"),
                           .init(title: "Replacement blades", query: "{vehicle} mower blades")]),
        CatalogItem(key: "plugs", name: "Spark plug", detail: "Once a season.", symbol: "bolt.fill", hours: 100, months: 12),
        CatalogItem(key: "grease", name: "Grease fittings", detail: "Spindles and pivots.", symbol: "drop.triangle", hours: 25, months: 6, isCore: false),
        CatalogItem(key: "hydraulic", name: "Hydraulic and transmission fluid", detail: "Compact tractors usually every 300 to 400 hours.", symbol: "gearshape.2", hours: 300, months: 24, isCore: false, difficulty: .moderate),
        CatalogItem(key: "storage", name: "Off-season storage", detail: "Stabilize or drain the fuel and keep the battery charged.", symbol: "snowflake", months: 12, isCore: false),
    ]

    static let electricMower: [CatalogItem] = [
        CatalogItem(key: "blades", name: "Sharpen blades", detail: "A sharp blade also stretches the battery.", symbol: "scissors", hours: 25, months: 12),
        CatalogItem(key: "deck", name: "Clean the deck", detail: "Caked grass costs runtime.", symbol: "sparkles", months: 3),
        CatalogItem(key: "storageCharge", name: "Storage charge", detail: "Store the battery partly charged somewhere cool and dry.", symbol: "battery.50", months: 12),
    ]

    static let ebike: [CatalogItem] = [
        CatalogItem(key: "chain", name: "Chain clean and lube", detail: "A clean chain shifts better and lasts longer. More often in the wet.", symbol: "link", miles: 200, months: 1,
                    gear: [.init(title: "Chain lube", query: "bike chain lube"),
                           .init(title: "Chain checker", query: "bike chain wear checker")]),
        CatalogItem(key: "brakes", name: "Brake pads", detail: "E-bikes are heavy and fast, so pads go quicker.", symbol: "exclamationmark.octagon", miles: 500, months: 6,
                    gear: [.init(title: "Disc brake pads", query: "e-bike disc brake pads")]),
        CatalogItem(key: "tune", name: "Tune-up", detail: "Gears, cables, bolts and spokes checked over.", symbol: "wrench.adjustable", miles: 1_000, months: 12, difficulty: .moderate),
        CatalogItem(key: "tires", name: "Tire pressure and wear", detail: "Low pressure costs range and invites flats.", symbol: "circle.circle", months: 1,
                    gear: [.init(title: "Floor pump with gauge", query: "bike floor pump with gauge")]),
        CatalogItem(key: "battery", name: "Battery care", detail: "Store around half charge in the cool and dry, and check the contacts.", symbol: "battery.75", months: 6, isCore: false),
    ]

    static let electricGolfCart: [CatalogItem] = [
        CatalogItem(key: "waterLevel", name: "Battery water level", detail: "Flooded lead-acid batteries need distilled water topped up monthly. Lithium packs skip this.", symbol: "drop", months: 1,
                    gear: [.init(title: "Battery watering system", query: "golf cart battery watering system")]),
        CatalogItem(key: "terminals", name: "Clean battery terminals", detail: "Corrosion steals range.", symbol: "minus.plus.batteryblock", months: 6),
        CatalogItem(key: "tires", name: "Tire pressure", detail: "Soft tires cost range and wear unevenly.", symbol: "circle.circle", months: 3),
        CatalogItem(key: "annual", name: "Annual service", detail: "Brakes, steering, suspension and charger checked over.", symbol: "wrench.adjustable", months: 12, difficulty: .shop),
    ]

    static let gasGolfCart: [CatalogItem] = [
        CatalogItem(key: "oil", name: "Oil change", detail: "Every 100 hours or once a year.", symbol: "drop.fill", months: 12),
        CatalogItem(key: "airFilter", name: "Air filter", detail: "Once a year.", symbol: "aqi.medium", months: 12),
        CatalogItem(key: "tires", name: "Tire pressure", detail: "Check quarterly.", symbol: "circle.circle", months: 3),
        CatalogItem(key: "annual", name: "Annual service", detail: "Belt, brakes and steering checked over.", symbol: "wrench.adjustable", months: 12, difficulty: .shop),
    ]

    static let generic: [CatalogItem] = [
        CatalogItem(key: "service", name: "General service", detail: "The yearly once-over.", symbol: "wrench.adjustable", months: 12),
        CatalogItem(key: "oil", name: "Oil change", detail: "If it has an engine, it has oil.", symbol: "drop.fill", months: 12),
    ]

    // MARK: - Paperwork

    /// Renewals, kept off by default because the dates are personal and the
    /// app shouldn't nag about something it can't know.
    static func paperwork(for kind: VehicleKind) -> [CatalogItem] {
        var items: [CatalogItem] = []
        if kind != .aircraft && kind != .ebike {
            items.append(CatalogItem(key: "registration", name: "Registration renewal", detail: "Set it to the month your registration expires.", symbol: "doc.text", months: 12, isCore: false))
        }
        if kind != .ebike && kind != .trailer {
            items.append(CatalogItem(key: "insurance", name: "Insurance renewal", detail: "A reminder to shop your rate before it renews.", symbol: "shield.lefthalf.filled", months: 12, isCore: false))
        }
        if kind.hasNHTSARecords && kind != .trailer && kind != .camper {
            items.append(CatalogItem(key: "inspection", name: "State inspection or emissions", detail: "Only where your state requires it.", symbol: "checkmark.seal", months: 12, isCore: false))
        }
        return items
    }
}
