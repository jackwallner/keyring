import Foundation

/// The common makes for each kind, for quick picking. Anything else can be
/// typed; this list only saves keystrokes.
enum Makes {
    static func common(for kind: VehicleKind, region: String? = Locale.current.region?.identifier) -> [String] {
        switch kind {
        case .car, .suv, .van, .truck:
            carMakes(region: region)
        default:
            otherMakes(for: kind)
        }
    }

    /// Best sellers first, by the reader's region, so the first chips are
    /// the ones they're likely to tap.
    static func carMakes(region: String?) -> [String] {
        switch region {
        case "CA":
            ["Toyota", "Ford", "Honda", "Hyundai", "Chevrolet", "Kia", "Nissan", "Mazda", "Ram", "GMC", "Jeep", "Subaru", "Volkswagen", "Tesla", "Mitsubishi", "BMW", "Mercedes-Benz", "Audi", "Lexus", "Acura", "Dodge", "Buick", "Volvo", "Cadillac", "Genesis", "Porsche", "Lincoln", "Chrysler", "Infiniti", "Land Rover", "MINI", "Polestar"]
        case "GB", "IE":
            ["Ford", "Vauxhall", "Volkswagen", "BMW", "Toyota", "Audi", "Mercedes-Benz", "Kia", "Nissan", "Hyundai", "Skoda", "Peugeot", "Land Rover", "MINI", "Volvo", "Tesla", "Renault", "SEAT", "Honda", "Mazda", "Citroën", "Fiat", "MG", "Jaguar", "Suzuki", "Dacia", "Cupra", "Lexus", "Porsche", "Polestar", "BYD"]
        case "AU", "NZ":
            ["Toyota", "Mazda", "Ford", "Hyundai", "Mitsubishi", "Kia", "Tesla", "Isuzu", "MG", "Subaru", "Nissan", "Volkswagen", "BYD", "GWM", "Suzuki", "Mercedes-Benz", "BMW", "Honda", "Audi", "Lexus", "LDV", "Land Rover", "Volvo", "Skoda", "Porsche", "Jeep", "Polestar"]
        default:
            ["Toyota", "Ford", "Chevrolet", "Honda", "Nissan", "Jeep", "Hyundai", "Kia", "Subaru", "Ram", "GMC", "Tesla", "Mazda", "Volkswagen", "BMW", "Mercedes-Benz", "Lexus", "Audi", "Dodge", "Acura", "Cadillac", "Buick", "Volvo", "Porsche", "Rivian", "Lincoln", "Mitsubishi", "Chrysler", "Genesis", "Infiniti", "Land Rover", "MINI"]
        }
    }

    private static func otherMakes(for kind: VehicleKind) -> [String] {
        switch kind {
        case .car, .suv, .van, .truck:
            []
        case .motorcycle, .scooter:
            ["Harley-Davidson", "Honda", "Yamaha", "Kawasaki", "Suzuki", "BMW", "Ducati", "Triumph", "KTM", "Indian", "Royal Enfield", "Vespa", "Zero"]
        case .rv, .camper:
            ["Winnebago", "Thor", "Jayco", "Airstream", "Forest River", "Keystone", "Grand Design", "Tiffin", "Coachmen", "Fleetwood", "Newmar", "Entegra"]
        case .trailer:
            ["Big Tex", "Carry-On", "Karavan", "Load Trail", "PJ Trailers", "Sure-Trac", "Featherlite", "Haulmark"]
        case .boat:
            ["Sea Ray", "Bayliner", "Boston Whaler", "Grady-White", "Chaparral", "Tracker", "Lund", "Malibu", "MasterCraft", "Bennington", "Regal", "Yamaha", "Ranger", "Alumacraft"]
        case .sailboat:
            ["Catalina", "Beneteau", "Jeanneau", "Hunter", "Hobie", "J/Boats", "Hallberg-Rassy", "Island Packet"]
        case .personalWatercraft:
            ["Sea-Doo", "Yamaha", "Kawasaki"]
        case .aircraft:
            ["Cessna", "Piper", "Beechcraft", "Cirrus", "Mooney", "Diamond", "Grumman", "Van's Aircraft", "Robinson"]
        case .atv:
            ["Polaris", "Can-Am", "Honda", "Yamaha", "Kawasaki", "Arctic Cat", "Kubota", "John Deere"]
        case .snowmobile:
            ["Ski-Doo", "Polaris", "Arctic Cat", "Yamaha"]
        case .tractor:
            ["John Deere", "Kubota", "Cub Cadet", "Husqvarna", "Toro", "Massey Ferguson", "New Holland", "Mahindra", "Craftsman", "Ego"]
        case .ebike:
            ["Rad Power Bikes", "Trek", "Specialized", "Aventon", "Lectric", "Giant", "Cannondale", "Gazelle", "Tern"]
        case .golfCart:
            ["Club Car", "E-Z-GO", "Yamaha", "Evolution", "Icon"]
        case .other:
            []
        }
    }

    /// A powertrain the make or model gives away: an all-electric brand, or a
    /// model or trim name only plug-ins and hybrids carry.
    static func inferredPowertrain(make: String, model: String, trim: String = "") -> Powertrain? {
        let brand = make.trimmingCharacters(in: .whitespaces).lowercased()
        if ["tesla", "polestar", "rivian", "lucid", "fisker", "zero", "vinfast", "scout"].contains(brand) { return .electric }
        let name = " \(model) \(trim) ".lowercased()
        let words = Set(name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let plugIn: Set<String> = ["prime", "phev", "4xe", "energi", "plugin", "ehybrid"]
        if !words.isDisjoint(with: plugIn) || name.contains("plug-in") || name.contains("e-hybrid") { return .plugInHybrid }
        let electric: Set<String> = ["ev", "bev", "electric", "lightning", "ioniq", "bolt", "leaf", "etron", "eqs", "eqe", "eqb", "i4", "ix", "i3", "i7", "ariya", "bz4x", "solterra", "ev6", "ev9", "lyriq", "prologue", "zdx", "taycan", "zoe"]
        if !words.isDisjoint(with: electric) || name.contains("mach-e") || name.contains("e-tron") || name.contains(" id.") { return .electric }
        if words.contains("hybrid") || words.contains("hev") { return .hybrid }
        return nil
    }
}
