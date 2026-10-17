import Foundation

/// Worthwhile upgrades owners actually recommend to each other: the ones
/// that pay back in safety, convenience or resale, not stickers. Each opens
/// an Amazon search tailored to the vehicle.
struct Upgrade: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case safety, protection, convenience, care

        var title: String {
            switch self {
            case .safety: "Safety"
            case .protection: "Protection"
            case .convenience: "Convenience"
            case .care: "Care kit"
            }
        }
    }

    let title: String
    let why: String
    let symbol: String
    let category: Category
    /// `{vehicle}` and `{make}` are filled like catalog gear.
    let query: String

    var id: String { title }
}

enum UpgradeCatalog {
    static func upgrades(for kind: VehicleKind, powertrain: Powertrain) -> [Upgrade] {
        var list: [Upgrade]
        switch kind {
        case .car, .suv, .van, .truck:
            list = road
            if kind == .truck { list += truck }
            if powertrain == .electric || powertrain == .plugInHybrid { list += ev }
        case .motorcycle, .scooter: list = motorcycle
        case .rv, .camper: list = rv
        case .trailer: list = trailer
        case .boat, .personalWatercraft, .sailboat: list = boat
        case .aircraft: list = aircraft
        case .atv, .snowmobile: list = powersports
        case .tractor: list = tractor
        case .ebike: list = ebike
        case .golfCart: list = golfCart
        case .other: list = generic
        }
        return list
    }

    static let road: [Upgrade] = [
        Upgrade(title: "All-weather floor liners", why: "Laser-fit liners keep mud and spills off the carpet, which is the first thing a buyer looks at.", symbol: "square.stack.3d.down.forward.fill", category: .protection, query: "{vehicle} all weather floor liners"),
        Upgrade(title: "Dash camera", why: "Front and rear footage settles fault disputes and some insurers discount for it.", symbol: "video.fill", category: .safety, query: "front and rear dash cam"),
        Upgrade(title: "Portable jump starter", why: "Starts a dead battery without a second car, and doubles as a phone charger.", symbol: "bolt.car.fill", category: .safety, query: "portable car jump starter"),
        Upgrade(title: "Tire inflator", why: "A cordless inflator turns a slow leak into a five minute stop instead of a tow.", symbol: "gauge.with.dots.needle.67percent", category: .safety, query: "cordless tire inflator"),
        Upgrade(title: "Ceramic coating kit", why: "Makes washing easier and protects paint for a year or more.", symbol: "sparkles", category: .care, query: "ceramic coating kit car"),
        Upgrade(title: "Seat-back organizer", why: "Gets the kids' stuff off the floor on long drives.", symbol: "tray.full.fill", category: .convenience, query: "car seat back organizer"),
        Upgrade(title: "Wireless CarPlay adapter", why: "Wired CarPlay goes wireless for cars that shipped without it.", symbol: "iphone.radiowaves.left.and.right", category: .convenience, query: "wireless carplay adapter"),
        Upgrade(title: "Roadside emergency kit", why: "Cables, flares, gloves and a first aid kit in one bag for the trunk.", symbol: "cross.case.fill", category: .safety, query: "roadside emergency kit car"),
    ]

    static let truck: [Upgrade] = [
        Upgrade(title: "Tonneau cover", why: "Keeps the bed dry and locked, and can improve highway mileage.", symbol: "rectangle.fill.on.rectangle.fill", category: .protection, query: "{vehicle} tonneau cover"),
        Upgrade(title: "Bed liner mat", why: "Stops cargo sliding and saves the bed paint.", symbol: "square.grid.3x3.fill", category: .protection, query: "{vehicle} bed mat"),
        Upgrade(title: "Hitch lock and pin set", why: "Cheap insurance for an expensive trailer or bike rack.", symbol: "lock.fill", category: .safety, query: "trailer hitch lock"),
    ]

    static let ev: [Upgrade] = [
        Upgrade(title: "Level 2 home charger", why: "Overnight full charges at home cost far less than public fast charging.", symbol: "ev.charger.fill", category: .convenience, query: "level 2 ev charger"),
        Upgrade(title: "Charging cable organizer", why: "Keeps the cable off the garage floor and away from tires.", symbol: "cable.connector", category: .convenience, query: "ev charger cable organizer"),
    ]

    static let motorcycle: [Upgrade] = [
        Upgrade(title: "Battery tender", why: "A maintainer through the off season is the difference between a spring start and a new battery.", symbol: "minus.plus.batteryblock.fill", category: .care, query: "motorcycle battery tender"),
        Upgrade(title: "Chain cleaning kit", why: "Brush, cleaner and lube in one kit makes the 500 mile chain job quick.", symbol: "link", category: .care, query: "motorcycle chain cleaning kit"),
        Upgrade(title: "Rear stand", why: "Lifts the back wheel for chain work and tire checks.", symbol: "arrow.up.to.line", category: .care, query: "motorcycle rear paddock stand"),
        Upgrade(title: "Helmet communicator", why: "Navigation and calls without taking a hand off the bars.", symbol: "headphones", category: .convenience, query: "motorcycle helmet bluetooth communicator"),
        Upgrade(title: "Frame sliders", why: "A tip-over in a parking lot stays a scuff instead of a cracked fairing.", symbol: "shield.fill", category: .protection, query: "{vehicle} frame sliders"),
        Upgrade(title: "Waterproof cover", why: "Keeps rain, sun and birds off between rides.", symbol: "cloud.rain.fill", category: .protection, query: "waterproof motorcycle cover"),
    ]

    static let rv: [Upgrade] = [
        Upgrade(title: "Surge protector", why: "One bad campground pedestal can fry the converter and every appliance aboard.", symbol: "bolt.shield.fill", category: .safety, query: "rv surge protector 30 amp"),
        Upgrade(title: "Water pressure regulator", why: "Protects your plumbing from high pressure park water.", symbol: "drop.degreesign.fill", category: .protection, query: "rv water pressure regulator with gauge"),
        Upgrade(title: "Tire pressure monitor", why: "RV blowouts are expensive and dangerous; a monitor shows trouble on the dash.", symbol: "gauge.with.dots.needle.33percent", category: .safety, query: "rv tire pressure monitoring system"),
        Upgrade(title: "Leveling blocks", why: "Fast, stackable leveling on uneven sites.", symbol: "square.3.layers.3d", category: .convenience, query: "rv leveling blocks"),
        Upgrade(title: "Drinking water hose and filter", why: "A dedicated hose and inline filter for the fresh tank.", symbol: "drop.fill", category: .care, query: "rv drinking water hose filter"),
        Upgrade(title: "Sewer hose kit", why: "A good kit makes the least favorite job quick and clean.", symbol: "arrow.down.to.line", category: .care, query: "rv sewer hose kit"),
    ]

    static let trailer: [Upgrade] = [
        Upgrade(title: "Bearing grease gun", why: "Repacking bearings yourself is the cheapest way to avoid a roadside failure.", symbol: "gearshape.2.fill", category: .care, query: "grease gun trailer bearings"),
        Upgrade(title: "Spare tire and mount", why: "Trailer tire sizes are hard to find on a Sunday.", symbol: "circle.circle.fill", category: .safety, query: "{vehicle} trailer spare tire"),
        Upgrade(title: "LED trailer lights", why: "LEDs outlast bulbs and survive dunking at the ramp.", symbol: "lightbulb.fill", category: .safety, query: "led trailer light kit"),
        Upgrade(title: "Coupler lock", why: "Stops someone from hitching up and driving away.", symbol: "lock.fill", category: .safety, query: "trailer coupler lock"),
    ]

    static let boat: [Upgrade] = [
        Upgrade(title: "Onboard battery charger", why: "Keeps batteries topped up at the dock or in storage.", symbol: "minus.plus.batteryblock.fill", category: .care, query: "marine onboard battery charger"),
        Upgrade(title: "Fuel stabilizer", why: "Ethanol fuel goes stale fast; stabilizer is the cheapest winterizing step.", symbol: "fuelpump.fill", category: .care, query: "marine fuel stabilizer"),
        Upgrade(title: "Inflatable life jackets", why: "Comfortable enough that people actually wear them.", symbol: "lifepreserver.fill", category: .safety, query: "inflatable life jacket"),
        Upgrade(title: "Bilge pump backup", why: "A second automatic pump is cheap insurance on a mooring.", symbol: "water.waves.and.arrow.down", category: .safety, query: "automatic bilge pump"),
        Upgrade(title: "Boat cover", why: "Sun and rain wear out vinyl and canvas fastest.", symbol: "umbrella.fill", category: .protection, query: "{vehicle} boat cover"),
        Upgrade(title: "Flush muffs", why: "Rinse an outboard with fresh water after every salt run.", symbol: "drop.triangle.fill", category: .care, query: "outboard motor flush muffs"),
    ]

    static let aircraft: [Upgrade] = [
        Upgrade(title: "Engine monitor", why: "Per-cylinder temperatures catch trouble long before an annual does.", symbol: "waveform.path.ecg", category: .safety, query: "aircraft engine monitor"),
        Upgrade(title: "Carbon monoxide detector", why: "A cracked exhaust can poison a cabin without any smell.", symbol: "sensor.fill", category: .safety, query: "aviation carbon monoxide detector"),
        Upgrade(title: "Sun shade and cowl plugs", why: "Keeps the panel cool and birds out of the cowling.", symbol: "sun.max.fill", category: .protection, query: "{make} aircraft sunshade cowl plugs"),
        Upgrade(title: "Preheater", why: "Cold starts are the hardest minutes on an engine.", symbol: "thermometer.sun.fill", category: .care, query: "aircraft engine preheater"),
        Upgrade(title: "Fuel tester", why: "Sump every tank, every preflight.", symbol: "testtube.2", category: .safety, query: "aircraft fuel sampler tester"),
    ]

    static let powersports: [Upgrade] = [
        Upgrade(title: "Battery tender", why: "Seasonal machines kill batteries in storage.", symbol: "minus.plus.batteryblock.fill", category: .care, query: "powersports battery tender"),
        Upgrade(title: "Winch", why: "Self-recovery when the trail gets the better of you.", symbol: "arrow.uturn.backward.circle.fill", category: .safety, query: "{vehicle} winch"),
        Upgrade(title: "Skid plates", why: "Protects the underside from rocks and stumps.", symbol: "shield.lefthalf.filled", category: .protection, query: "{vehicle} skid plate"),
        Upgrade(title: "Storage cover", why: "Keeps rodents and sun off between seasons.", symbol: "umbrella.fill", category: .protection, query: "{vehicle} cover"),
    ]

    static let tractor: [Upgrade] = [
        Upgrade(title: "Blade sharpener", why: "A sharp blade cuts cleaner and saves fuel.", symbol: "scissors", category: .care, query: "lawn mower blade sharpener"),
        Upgrade(title: "Seat cover", why: "Saves a cracked seat and a sore back.", symbol: "chair.fill", category: .protection, query: "tractor seat cover"),
        Upgrade(title: "Battery tender", why: "Winter storage is hard on small batteries.", symbol: "minus.plus.batteryblock.fill", category: .care, query: "lawn tractor battery maintainer"),
        Upgrade(title: "Grease gun", why: "Most tractor wear starts at a dry fitting.", symbol: "gearshape.2.fill", category: .care, query: "grease gun"),
    ]

    static let ebike: [Upgrade] = [
        Upgrade(title: "Heavy-duty lock", why: "E-bikes are top theft targets; a rated U-lock or chain matters.", symbol: "lock.fill", category: .safety, query: "ebike heavy duty lock"),
        Upgrade(title: "Floor pump with gauge", why: "Correct pressure is free range and fewer flats.", symbol: "gauge.with.dots.needle.50percent", category: .care, query: "bike floor pump with gauge"),
        Upgrade(title: "Bright lights", why: "Be seen at e-bike speeds, day and night.", symbol: "flashlight.on.fill", category: .safety, query: "ebike front rear light set"),
        Upgrade(title: "GPS tracker", why: "A hidden tracker helps recover a stolen bike.", symbol: "location.fill", category: .safety, query: "bike gps tracker hidden"),
    ]

    static let golfCart: [Upgrade] = [
        Upgrade(title: "Battery watering system", why: "Fills every cell at once, which keeps lead-acid packs alive longer.", symbol: "drop.fill", category: .care, query: "golf cart battery watering system"),
        Upgrade(title: "Enclosure", why: "Turns a fair-weather cart into a year-round one.", symbol: "cloud.rain.fill", category: .protection, query: "{make} golf cart enclosure"),
        Upgrade(title: "LED light kit", why: "Safer driving at dusk around the neighborhood.", symbol: "lightbulb.fill", category: .safety, query: "golf cart led light kit"),
    ]

    static let generic: [Upgrade] = [
        Upgrade(title: "Battery maintainer", why: "Anything that sits needs one.", symbol: "minus.plus.batteryblock.fill", category: .care, query: "battery maintainer"),
        Upgrade(title: "Cover", why: "Sun and weather wear out everything faster.", symbol: "umbrella.fill", category: .protection, query: "{vehicle} cover"),
    ]
}
