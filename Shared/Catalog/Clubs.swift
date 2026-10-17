import Foundation

/// Where owners of the same thing gather: national clubs, the forums people
/// actually search for answers, and the subreddit. Every domain was checked
/// live on 2026-10-17; parked or dead ones were left out.
struct Club: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case club, forum, subreddit, organization

        var title: String {
            switch self {
            case .club: "Owners club"
            case .forum: "Forum"
            case .subreddit: "Reddit"
            case .organization: "Organization"
            }
        }

        var symbol: String {
            switch self {
            case .club: "person.3.fill"
            case .forum: "bubble.left.and.bubble.right.fill"
            case .subreddit: "text.bubble.fill"
            case .organization: "building.columns.fill"
            }
        }
    }

    let name: String
    let detail: String
    let kind: Kind
    let url: URL

    var id: String { url.absoluteString }

    init(_ name: String, _ detail: String, _ kind: Kind, _ url: String) {
        self.name = name
        self.detail = detail
        self.kind = kind
        self.url = URL(string: url)!
    }

    static func subreddit(_ name: String, _ detail: String = "") -> Club {
        Club("r/\(name)", detail.isEmpty ? "Owners trading tips, photos and fixes" : detail, .subreddit, "https://www.reddit.com/r/\(name)/")
    }
}

enum ClubDirectory {
    /// The best matches for a vehicle: model-specific places first, then the
    /// make, then the kind of vehicle as a whole.
    static func clubs(for vehicle: Vehicle) -> [Club] {
        clubs(kind: vehicle.kind, make: vehicle.make, model: vehicle.model)
    }

    static func clubs(kind: VehicleKind, make: String?, model: String?) -> [Club] {
        let makeKey = normalize(make)
        let modelKey = normalize(model)
        var list: [Club] = []
        if let modelKey, let specific = models[modelKey] { list += specific }
        if let makeKey, let byMake = makes[makeKey] { list += byMake }
        list += byKind(kind)
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }
    }

    static func normalize(_ text: String?) -> String? {
        guard let text = text?.lowercased().trimmed, !text.isEmpty else { return nil }
        return text
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "mercedes benz", with: "mercedes")
            .replacingOccurrences(of: "chevy", with: "chevrolet")
            .replacingOccurrences(of: "vw", with: "volkswagen")
    }

    // MARK: - By model

    static let models: [String: [Club]] = [
        "tacoma": [Club("Tacoma World", "The biggest Tacoma forum", .forum, "https://www.tacomaworld.com/"), .subreddit("Tacoma")],
        "tundra": [Club("Tundras.com", "Tundra owners forum", .forum, "https://www.tundras.com/"), .subreddit("ToyotaTundra")],
        "4runner": [.subreddit("4Runner")],
        "rav4": [.subreddit("rav4club")],
        "prius": [Club("PriusChat", "Hybrid owners since 2003", .forum, "https://priuschat.com/"), .subreddit("prius")],
        "land cruiser": [Club("Toyota Land Cruiser Association", "Trails, events and tech since 1975", .club, "https://tlca.org/")],
        "gr86": [Club("FT86Club", "86, BRZ and GR86 owners", .forum, "https://www.ft86club.com/"), .subreddit("GR86")],
        "f 150": [Club("F150 Forum", "F-150 owners and tech", .forum, "https://www.f150forum.com/"), .subreddit("f150")],
        "mustang": [Club("AllFordMustangs", "Every generation of Mustang", .forum, "https://www.allfordmustangs.com/"), .subreddit("Mustang")],
        "bronco": [.subreddit("bronco")],
        "ranger": [Club("Ranger Forums", "Ford Ranger owners", .forum, "https://www.rangerforums.net/")],
        "maverick": [.subreddit("FordMaverickTruck")],
        "mustang mach e": [Club("Mach-E Forum", "Mustang Mach-E owners", .forum, "https://www.macheforum.com/"), .subreddit("MachE")],
        "corvette": [
            Club("National Corvette Restorers Society", "Judging, restoration and history", .club, "https://www.ncrs.org/"),
            Club("National Council of Corvette Clubs", "Clubs, autocross and events", .club, "https://www.corvettesnccc.org/"),
            Club("Corvette Forum", "Every generation, every question", .forum, "https://www.corvetteforum.com/"),
            .subreddit("Corvette"),
        ],
        "camaro": [Club("Camaro6", "Sixth-gen Camaro owners", .forum, "https://www.camaro6.com/"), .subreddit("camaro")],
        "silverado 1500": [.subreddit("Silverado")],
        "silverado": [.subreddit("Silverado")],
        "colorado": [.subreddit("chevycolorado")],
        "bolt ev": [.subreddit("BoltEV")],
        "civic": [Club("CivicX", "10th and 11th gen Civic owners", .forum, "https://www.civicx.com/"), .subreddit("civic")],
        "accord": [.subreddit("accord")],
        "cr v": [.subreddit("crv")],
        "odyssey": [.subreddit("hondaodyssey")],
        "s2000": [Club("S2Ki", "The S2000 community", .forum, "https://www.s2ki.com/")],
        "gold wing": [Club("Gold Wing Road Riders Association", "Chapters and rallies for Wing riders", .club, "https://www.gwrra.org/"), .subreddit("GoldWing")],
        "350z": [Club("My350Z", "350Z owners", .forum, "https://my350z.com/")],
        "370z": [Club("Z Car Club of America", "Every Z since the 240Z", .club, "https://www.zcca.org/"), .subreddit("370z")],
        "frontier": [Club("Nissan Frontier Forum", "Frontier owners and tech", .forum, "https://www.nissanfrontier.org/")],
        "rogue": [Club("Rogue Forums", "Nissan Rogue owners", .forum, "https://www.rogueforums.com/")],
        "leaf": [.subreddit("nissanleaf")],
        "telluride": [Club("Kia Telluride Forum", "Telluride owners", .forum, "https://www.kiatelluride.org/"), .subreddit("KiaTelluride")],
        "ev6": [Club("Kia EV6 Forum", "EV6 owners", .forum, "https://www.kiaev6forum.com/"), .subreddit("KiaEV6")],
        "ioniq 5": [.subreddit("Ioniq5")],
        "wrangler": [.subreddit("JeepWrangler")],
        "grand cherokee": [.subreddit("GrandCherokee")],
        "cherokee": [Club("Cherokee Forum", "Jeep Cherokee owners", .forum, "https://www.cherokeeforum.com/")],
        "1500": [Club("5th Gen Rams", "Ram truck owners", .forum, "https://5thgenrams.com/")],
        "2500": [Club("5th Gen Rams", "Ram truck owners", .forum, "https://5thgenrams.com/"), .subreddit("Cummins")],
        "challenger": [.subreddit("Challenger")],
        "wrx": [.subreddit("WRX")],
        "outback": [.subreddit("Subaru_Outback")],
        "forester": [.subreddit("SubaruForester")],
        "mx 5": [.subreddit("Miata")],
        "mx 5 miata": [.subreddit("Miata")],
        "miata": [.subreddit("Miata")],
        "cx 5": [.subreddit("CX5")],
        "model 3": [.subreddit("TeslaModel3")],
        "model y": [.subreddit("TeslaModelY")],
        "gti": [.subreddit("GolfGTI")],
        "golf gti": [.subreddit("GolfGTI")],
        "g37": [Club("MyG37", "Infiniti G37 owners", .forum, "https://www.myg37.com/")],
        "g35": [Club("G35Driver", "Infiniti G35 owners", .forum, "https://g35driver.com/")],
        "lancer evolution": [Club("EvolutionM", "Lancer Evolution owners", .forum, "https://www.evolutionm.net/")],
    ]

    // MARK: - By make

    static let makes: [String: [Club]] = [
        "toyota": [.subreddit("Toyota")],
        "lexus": [Club("ClubLexus", "Lexus owners forum", .forum, "https://www.clublexus.com/"), .subreddit("Lexus")],
        "ford": [Club("Ford-Trucks.com", "Ford truck owners", .forum, "https://www.ford-trucks.com/"), .subreddit("Ford")],
        "shelby": [Club("Shelby American Automobile Club", "Shelby registry and events", .club, "https://www.saac.com/")],
        "chevrolet": [.subreddit("Chevrolet")],
        "gmc": [Club("GMC Forum", "GMC truck and SUV owners", .forum, "https://www.gmcforum.com/"), .subreddit("gmc")],
        "honda": [.subreddit("Honda")],
        "acura": [Club("AcuraZine", "Acura owners", .forum, "https://acurazine.com/"), .subreddit("Acura")],
        "nissan": [.subreddit("Nissan")],
        "infiniti": [.subreddit("infiniti")],
        "hyundai": [.subreddit("Hyundai")],
        "kia": [.subreddit("kia")],
        "genesis": [.subreddit("GenesisMotors")],
        "jeep": [Club("Jeep Jamboree USA", "Guided off-road weekends", .club, "https://www.jeepjamboreeusa.com/"), .subreddit("Jeep")],
        "ram": [.subreddit("ramtrucks")],
        "dodge": [.subreddit("Dodge")],
        "chrysler": [Club("Chrysler 300 Club", "Letter-car history and events", .club, "https://www.chrysler300club.com/"), .subreddit("Chrysler")],
        "subaru": [.subreddit("subaru")],
        "mazda": [Club("Mazdas247", "Every Mazda model", .forum, "https://www.mazdas247.com/"), .subreddit("mazda")],
        "tesla": [Club("Tesla Owners Clubs", "Tesla's official directory of local clubs", .club, "https://engage.tesla.com/pages/clubs"), .subreddit("teslamotors")],
        "volkswagen": [Club("VW Club of America", "Chapters, events and the Vintage Volkswagen community", .club, "https://www.vwclub.org/"), .subreddit("Volkswagen")],
        "audi": [Club("Audi Club North America", "Driving schools and chapters", .club, "https://www.audiclubna.org/"), Club("AudiWorld", "Audi owners forum", .forum, "https://www.audiworld.com/"), .subreddit("Audi")],
        "bmw": [Club("BMW Car Club of America", "Chapters, track days and Roundel", .club, "https://www.bmwcca.org/"), Club("Bimmerfest", "BMW owners forum", .forum, "https://www.bimmerfest.com/"), .subreddit("BMW")],
        "mercedes": [Club("MBWorld", "Mercedes-Benz owners", .forum, "https://mbworld.org/"), .subreddit("mercedes_benz")],
        "porsche": [Club("Porsche Club of America", "The largest single-marque club in the world", .club, "https://www.pca.org/"), Club("Rennlist", "Porsche owners forum", .forum, "https://rennlist.com/"), .subreddit("Porsche")],
        "volvo": [Club("Volvo Club of America", "Chapters and the Rolling magazine", .club, "https://vcoa.org/"), .subreddit("Volvo")],
        "cadillac": [Club("Cadillac & LaSalle Club", "Since 1958", .club, "https://www.cadillaclasalleclub.org/"), .subreddit("Cadillac")],
        "buick": [Club("Buick Club of America", "Chapters and national meets", .club, "https://www.buickclub.org/"), .subreddit("Buick")],
        "lincoln": [Club("Lincoln & Continental Owners Club", "Lincoln history and meets", .club, "https://www.lincolnclub.org/"), Club("Lincoln Forum", "Lincoln owners", .forum, "https://www.lincolnforum.com/"), .subreddit("lincoln")],
        "mitsubishi": [.subreddit("mitsubishi")],
        "land rover": [.subreddit("landrover")],
        "jaguar": [Club("Jaguar Clubs of North America", "Concours, rallies and chapters", .club, "https://www.jcna.com/"), .subreddit("Jaguar")],
        "mini": [Club("North American Motoring", "MINI owners forum", .forum, "https://www.northamericanmotoring.com/"), .subreddit("MINI")],
        "alfa romeo": [Club("Alfa Romeo Owners Club", "Since 1957", .club, "https://www.aroc-usa.org/"), .subreddit("alfaromeo")],
        "fiat": [.subreddit("fiat")],
        "rivian": [Club("Rivian Forums", "Rivian owners", .forum, "https://www.rivianforums.com/"), .subreddit("Rivian")],
        "lucid": [Club("Lucid Owners", "Lucid Air and Gravity owners", .forum, "https://lucidowners.com/"), .subreddit("LUCID")],
        "polestar": [.subreddit("Polestar")],
        "saab": [Club("Saab Club of North America", "Keeping Saabs on the road", .club, "https://www.saabclub.com/"), .subreddit("saab")],
        "amc": [Club("AMC Rambler Club", "American Motors history", .club, "https://www.amcrc.com/")],
        "harley davidson": [Club("Harley Owners Group", "Chapters and rides worldwide", .club, "https://www.harley-davidson.com/us/en/content/hog.html"), Club("HDForums", "Harley owners forum", .forum, "https://www.hdforums.com/"), .subreddit("harley")],
        "ducati": [.subreddit("Ducati")],
        "triumph": [.subreddit("Triumph")],
    ]

    // MARK: - By kind

    static func byKind(_ kind: VehicleKind) -> [Club] {
        switch kind {
        case .car, .suv, .truck, .van:
            [
                Club("Antique Automobile Club of America", "For anything 25 years and older", .organization, "https://www.aaca.org/"),
                Club("SCCA", "Autocross and track days for any car", .organization, "https://www.scca.com/"),
                .subreddit("MechanicAdvice", "Ask a mechanic, free"),
                .subreddit("Cartalk"),
            ]
        case .motorcycle, .scooter:
            [
                Club("American Motorcyclist Association", "Rider rights, events and roadside help", .organization, "https://americanmotorcyclist.com/"),
                Club("BMW Motorcycle Owners of America", "Rallies and tech days, any bike welcome", .club, "https://www.bmwmoa.org/"),
                .subreddit("motorcycles"),
                .subreddit("motorcyclemaintenance", "Wrenching help for every bike"),
            ]
        case .rv, .camper:
            [
                Club("Good Sam", "Campground discounts and roadside help", .organization, "https://www.goodsam.com/"),
                Club("Escapees RV Club", "Full-timer community, mail service and parks", .club, "https://www.escapees.com/"),
                Club("FRVA", "The Family RV Association, formerly FMCA", .club, "https://www.frva.com/"),
                .subreddit("RVLiving"),
            ]
        case .trailer:
            [.subreddit("trailers", "Hitching, wiring and bearings")]
        case .boat, .personalWatercraft:
            [
                Club("BoatUS", "Towing on the water, insurance and advocacy", .organization, "https://www.boatus.com/"),
                Club("U.S. Coast Guard Auxiliary", "Free vessel safety checks", .organization, "https://cgaux.org/vsc/"),
                .subreddit("boating"),
            ]
        case .sailboat:
            [
                Club("US Sailing", "Training, racing and local clubs", .organization, "https://www.ussailing.org/"),
                Club("BoatUS", "Towing on the water, insurance and advocacy", .organization, "https://www.boatus.com/"),
                .subreddit("sailing"),
            ]
        case .aircraft:
            [
                Club("AOPA", "Pilot advocacy, legal plans and the Pilot magazine", .organization, "https://www.aopa.org/"),
                Club("EAA", "Chapters, Young Eagles and AirVenture Oshkosh", .club, "https://www.eaa.org/"),
                .subreddit("flying"),
            ]
        case .atv:
            [Club("National Off-Highway Vehicle Conservation Council", "Trails and riding areas", .organization, "https://nohvcc.org/"), .subreddit("ATV"), .subreddit("SXSCommunity")]
        case .snowmobile:
            [Club("American Council of Snowmobile Associations", "Find your state association and trail maps", .organization, "https://www.snowmobilers.org/"), .subreddit("snowmobiling")]
        case .tractor:
            [.subreddit("tractors"), .subreddit("lawncare")]
        case .ebike:
            [Club("League of American Bicyclists", "Bike-friendly advocacy and classes", .organization, "https://bikeleague.org/"), .subreddit("ebikes")]
        case .golfCart:
            [.subreddit("golfcarts")]
        case .other:
            [.subreddit("MechanicAdvice", "Ask a mechanic, free")]
        }
    }
}
