import Foundation

/// The common makes for each kind, for quick picking. Anything else can be
/// typed; this list only saves keystrokes.
enum Makes {
    static func common(for kind: VehicleKind) -> [String] {
        switch kind {
        case .car, .suv, .van, .truck:
            ["Toyota", "Ford", "Chevrolet", "Honda", "Nissan", "Jeep", "Hyundai", "Kia", "Subaru", "Ram", "GMC", "Tesla", "Mazda", "Volkswagen", "BMW", "Mercedes-Benz", "Lexus", "Audi", "Dodge", "Acura", "Cadillac", "Buick", "Volvo", "Porsche", "Rivian", "Lincoln", "Mitsubishi", "Chrysler", "Genesis", "Infiniti", "Land Rover", "MINI"]
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
}
