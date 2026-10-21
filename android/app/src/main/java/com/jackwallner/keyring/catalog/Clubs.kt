package com.jackwallner.keyring.catalog

import com.jackwallner.keyring.model.VehicleKind

@Suppress("EnumEntryName")
enum class ClubKind(val title: String, val symbol: String) {
    club("Owners club", "person.3.fill"),
    forum("Forum", "bubble.left.and.bubble.right.fill"),
    subreddit("Reddit", "text.bubble.fill"),
    organization("Organization", "building.columns.fill"),
}

/** Where owners of the same thing gather. Ported from `Shared/Catalog/Clubs.swift`; `ExploreParityTest` checks it. */
data class Club(val name: String, val detail: String, val kind: ClubKind, val url: String) {
    val id: String get() = url

    companion object {
        fun subreddit(name: String, detail: String = "") =
            Club("r/$name", detail.ifEmpty { "Owners trading tips, photos and fixes" }, ClubKind.subreddit, "https://www.reddit.com/r/$name/")
    }
}

object ClubDirectory {
    /** The best matches for a vehicle: model-specific places first, then the make, then the kind as a whole. */
    fun clubs(kind: VehicleKind, make: String?, model: String?): List<Club> {
        val list = mutableListOf<Club>()
        normalize(model)?.let { models[it] }?.let(list::addAll)
        normalize(make)?.let { makes[it] }?.let(list::addAll)
        list += byKind(kind)
        val seen = mutableSetOf<String>()
        return list.filter { seen.add(it.id) }
    }

    fun normalize(text: String?): String? {
        val trimmed = text?.lowercase()?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return trimmed.replace("-", " ").replace("mercedes benz", "mercedes").replace("chevy", "chevrolet").replace("vw", "volkswagen")
    }

    val models: Map<String, List<Club>> = mapOf(
        "tacoma" to listOf(Club("Tacoma World", "The biggest Tacoma forum", ClubKind.forum, "https://www.tacomaworld.com/"), Club.subreddit("Tacoma")),
        "tundra" to listOf(Club("Tundras.com", "Tundra owners forum", ClubKind.forum, "https://www.tundras.com/"), Club.subreddit("ToyotaTundra")),
        "4runner" to listOf(Club.subreddit("4Runner")),
        "rav4" to listOf(Club.subreddit("rav4club")),
        "prius" to listOf(Club("PriusChat", "Hybrid owners since 2003", ClubKind.forum, "https://priuschat.com/"), Club.subreddit("prius")),
        "land cruiser" to listOf(Club("Toyota Land Cruiser Association", "Trails, events and tech since 1975", ClubKind.club, "https://tlca.org/")),
        "gr86" to listOf(Club("FT86Club", "86, BRZ and GR86 owners", ClubKind.forum, "https://www.ft86club.com/"), Club.subreddit("GR86")),
        "f 150" to listOf(Club("F150 Forum", "F-150 owners and tech", ClubKind.forum, "https://www.f150forum.com/"), Club.subreddit("f150")),
        "mustang" to listOf(Club("AllFordMustangs", "Every generation of Mustang", ClubKind.forum, "https://www.allfordmustangs.com/"), Club.subreddit("Mustang")),
        "bronco" to listOf(Club.subreddit("bronco")),
        "ranger" to listOf(Club("Ranger Forums", "Ford Ranger owners", ClubKind.forum, "https://www.rangerforums.net/")),
        "maverick" to listOf(Club.subreddit("FordMaverickTruck")),
        "mustang mach e" to listOf(Club("Mach-E Forum", "Mustang Mach-E owners", ClubKind.forum, "https://www.macheforum.com/"), Club.subreddit("MachE")),
        "corvette" to listOf(
            Club("National Corvette Restorers Society", "Judging, restoration and history", ClubKind.club, "https://www.ncrs.org/"),
            Club("National Council of Corvette Clubs", "Clubs, autocross and events", ClubKind.club, "https://www.corvettesnccc.org/"),
            Club("Corvette Forum", "Every generation, every question", ClubKind.forum, "https://www.corvetteforum.com/"),
            Club.subreddit("Corvette"),
        ),
        "camaro" to listOf(Club("Camaro6", "Sixth-gen Camaro owners", ClubKind.forum, "https://www.camaro6.com/"), Club.subreddit("camaro")),
        "silverado 1500" to listOf(Club.subreddit("Silverado")),
        "silverado" to listOf(Club.subreddit("Silverado")),
        "colorado" to listOf(Club.subreddit("chevycolorado")),
        "bolt ev" to listOf(Club.subreddit("BoltEV")),
        "civic" to listOf(Club("CivicX", "10th and 11th gen Civic owners", ClubKind.forum, "https://www.civicx.com/"), Club.subreddit("civic")),
        "accord" to listOf(Club.subreddit("accord")),
        "cr v" to listOf(Club.subreddit("crv")),
        "odyssey" to listOf(Club.subreddit("hondaodyssey")),
        "s2000" to listOf(Club("S2Ki", "The S2000 community", ClubKind.forum, "https://www.s2ki.com/")),
        "gold wing" to listOf(Club("Gold Wing Road Riders Association", "Chapters and rallies for Wing riders", ClubKind.club, "https://www.gwrra.org/"), Club.subreddit("GoldWing")),
        "350z" to listOf(Club("My350Z", "350Z owners", ClubKind.forum, "https://my350z.com/")),
        "370z" to listOf(Club("Z Car Club of America", "Every Z since the 240Z", ClubKind.club, "https://www.zcca.org/"), Club.subreddit("370z")),
        "frontier" to listOf(Club("Nissan Frontier Forum", "Frontier owners and tech", ClubKind.forum, "https://www.nissanfrontier.org/")),
        "rogue" to listOf(Club("Rogue Forums", "Nissan Rogue owners", ClubKind.forum, "https://www.rogueforums.com/")),
        "leaf" to listOf(Club.subreddit("nissanleaf")),
        "telluride" to listOf(Club("Kia Telluride Forum", "Telluride owners", ClubKind.forum, "https://www.kiatelluride.org/"), Club.subreddit("KiaTelluride")),
        "ev6" to listOf(Club("Kia EV6 Forum", "EV6 owners", ClubKind.forum, "https://www.kiaev6forum.com/"), Club.subreddit("KiaEV6")),
        "ioniq 5" to listOf(Club.subreddit("Ioniq5")),
        "wrangler" to listOf(Club.subreddit("JeepWrangler")),
        "grand cherokee" to listOf(Club.subreddit("GrandCherokee")),
        "cherokee" to listOf(Club("Cherokee Forum", "Jeep Cherokee owners", ClubKind.forum, "https://www.cherokeeforum.com/")),
        "1500" to listOf(Club("5th Gen Rams", "Ram truck owners", ClubKind.forum, "https://5thgenrams.com/")),
        "2500" to listOf(Club("5th Gen Rams", "Ram truck owners", ClubKind.forum, "https://5thgenrams.com/"), Club.subreddit("Cummins")),
        "challenger" to listOf(Club.subreddit("Challenger")),
        "wrx" to listOf(Club.subreddit("WRX")),
        "outback" to listOf(Club.subreddit("Subaru_Outback")),
        "forester" to listOf(Club.subreddit("SubaruForester")),
        "mx 5" to listOf(Club.subreddit("Miata")),
        "mx 5 miata" to listOf(Club.subreddit("Miata")),
        "miata" to listOf(Club.subreddit("Miata")),
        "cx 5" to listOf(Club.subreddit("CX5")),
        "model 3" to listOf(Club.subreddit("TeslaModel3")),
        "model y" to listOf(Club.subreddit("TeslaModelY")),
        "gti" to listOf(Club.subreddit("GolfGTI")),
        "golf gti" to listOf(Club.subreddit("GolfGTI")),
        "g37" to listOf(Club("MyG37", "Infiniti G37 owners", ClubKind.forum, "https://www.myg37.com/")),
        "g35" to listOf(Club("G35Driver", "Infiniti G35 owners", ClubKind.forum, "https://g35driver.com/")),
        "lancer evolution" to listOf(Club("EvolutionM", "Lancer Evolution owners", ClubKind.forum, "https://www.evolutionm.net/")),    )

    val makes: Map<String, List<Club>> = mapOf(
        "toyota" to listOf(Club.subreddit("Toyota")),
        "lexus" to listOf(Club("ClubLexus", "Lexus owners forum", ClubKind.forum, "https://www.clublexus.com/"), Club.subreddit("Lexus")),
        "ford" to listOf(Club("Ford-Trucks.com", "Ford truck owners", ClubKind.forum, "https://www.ford-trucks.com/"), Club.subreddit("Ford")),
        "shelby" to listOf(Club("Shelby American Automobile Club", "Shelby registry and events", ClubKind.club, "https://www.saac.com/")),
        "chevrolet" to listOf(Club.subreddit("Chevrolet")),
        "gmc" to listOf(Club("GMC Forum", "GMC truck and SUV owners", ClubKind.forum, "https://www.gmcforum.com/"), Club.subreddit("gmc")),
        "honda" to listOf(Club.subreddit("Honda")),
        "acura" to listOf(Club("AcuraZine", "Acura owners", ClubKind.forum, "https://acurazine.com/"), Club.subreddit("Acura")),
        "nissan" to listOf(Club.subreddit("Nissan")),
        "infiniti" to listOf(Club.subreddit("infiniti")),
        "hyundai" to listOf(Club.subreddit("Hyundai")),
        "kia" to listOf(Club.subreddit("kia")),
        "genesis" to listOf(Club.subreddit("GenesisMotors")),
        "jeep" to listOf(Club("Jeep Jamboree USA", "Guided off-road weekends", ClubKind.club, "https://www.jeepjamboreeusa.com/"), Club.subreddit("Jeep")),
        "ram" to listOf(Club.subreddit("ramtrucks")),
        "dodge" to listOf(Club.subreddit("Dodge")),
        "chrysler" to listOf(Club("Chrysler 300 Club", "Letter-car history and events", ClubKind.club, "https://www.chrysler300club.com/"), Club.subreddit("Chrysler")),
        "subaru" to listOf(Club.subreddit("subaru")),
        "mazda" to listOf(Club("Mazdas247", "Every Mazda model", ClubKind.forum, "https://www.mazdas247.com/"), Club.subreddit("mazda")),
        "tesla" to listOf(Club("Tesla Owners Clubs", "Tesla's official directory of local clubs", ClubKind.club, "https://engage.tesla.com/pages/clubs"), Club.subreddit("teslamotors")),
        "volkswagen" to listOf(Club("VW Club of America", "Chapters, events and the Vintage Volkswagen community", ClubKind.club, "https://www.vwclub.org/"), Club.subreddit("Volkswagen")),
        "audi" to listOf(Club("Audi Club North America", "Driving schools and chapters", ClubKind.club, "https://www.audiclubna.org/"), Club("AudiWorld", "Audi owners forum", ClubKind.forum, "https://www.audiworld.com/"), Club.subreddit("Audi")),
        "bmw" to listOf(Club("BMW Car Club of America", "Chapters, track days and Roundel", ClubKind.club, "https://www.bmwcca.org/"), Club("Bimmerfest", "BMW owners forum", ClubKind.forum, "https://www.bimmerfest.com/"), Club.subreddit("BMW")),
        "mercedes" to listOf(Club("MBWorld", "Mercedes-Benz owners", ClubKind.forum, "https://mbworld.org/"), Club.subreddit("mercedes_benz")),
        "porsche" to listOf(Club("Porsche Club of America", "The largest single-marque club in the world", ClubKind.club, "https://www.pca.org/"), Club("Rennlist", "Porsche owners forum", ClubKind.forum, "https://rennlist.com/"), Club.subreddit("Porsche")),
        "volvo" to listOf(Club("Volvo Club of America", "Chapters and the Rolling magazine", ClubKind.club, "https://vcoa.org/"), Club.subreddit("Volvo")),
        "cadillac" to listOf(Club("Cadillac & LaSalle Club", "Since 1958", ClubKind.club, "https://www.cadillaclasalleclub.org/"), Club.subreddit("Cadillac")),
        "buick" to listOf(Club("Buick Club of America", "Chapters and national meets", ClubKind.club, "https://www.buickclub.org/"), Club.subreddit("Buick")),
        "lincoln" to listOf(Club("Lincoln & Continental Owners Club", "Lincoln history and meets", ClubKind.club, "https://www.lincolnclub.org/"), Club("Lincoln Forum", "Lincoln owners", ClubKind.forum, "https://www.lincolnforum.com/"), Club.subreddit("lincoln")),
        "mitsubishi" to listOf(Club.subreddit("mitsubishi")),
        "land rover" to listOf(Club.subreddit("landrover")),
        "jaguar" to listOf(Club("Jaguar Clubs of North America", "Concours, rallies and chapters", ClubKind.club, "https://www.jcna.com/"), Club.subreddit("Jaguar")),
        "mini" to listOf(Club("North American Motoring", "MINI owners forum", ClubKind.forum, "https://www.northamericanmotoring.com/"), Club.subreddit("MINI")),
        "alfa romeo" to listOf(Club("Alfa Romeo Owners Club", "Since 1957", ClubKind.club, "https://www.aroc-usa.org/"), Club.subreddit("alfaromeo")),
        "fiat" to listOf(Club.subreddit("fiat")),
        "rivian" to listOf(Club("Rivian Forums", "Rivian owners", ClubKind.forum, "https://www.rivianforums.com/"), Club.subreddit("Rivian")),
        "lucid" to listOf(Club("Lucid Owners", "Lucid Air and Gravity owners", ClubKind.forum, "https://lucidowners.com/"), Club.subreddit("LUCID")),
        "polestar" to listOf(Club.subreddit("Polestar")),
        "saab" to listOf(Club("Saab Club of North America", "Keeping Saabs on the road", ClubKind.club, "https://www.saabclub.com/"), Club.subreddit("saab")),
        "amc" to listOf(Club("AMC Rambler Club", "American Motors history", ClubKind.club, "https://www.amcrc.com/")),
        "harley davidson" to listOf(Club("Harley Owners Group", "Chapters and rides worldwide", ClubKind.club, "https://www.harley-davidson.com/us/en/content/hog.html"), Club("HDForums", "Harley owners forum", ClubKind.forum, "https://www.hdforums.com/"), Club.subreddit("harley")),
        "ducati" to listOf(Club.subreddit("Ducati")),
        "triumph" to listOf(Club.subreddit("Triumph")),    )

    fun byKind(kind: VehicleKind): List<Club> = when (kind) {
        VehicleKind.car, VehicleKind.suv, VehicleKind.truck, VehicleKind.van ->
            listOf(
                Club("Antique Automobile Club of America", "For anything 25 years and older", ClubKind.organization, "https://www.aaca.org/"),
                Club("SCCA", "Autocross and track days for any car", ClubKind.organization, "https://www.scca.com/"),
                Club.subreddit("MechanicAdvice", "Ask a mechanic, free"),
                Club.subreddit("Cartalk"),
            )
        VehicleKind.motorcycle, VehicleKind.scooter ->
            listOf(
                Club("American Motorcyclist Association", "Rider rights, events and roadside help", ClubKind.organization, "https://americanmotorcyclist.com/"),
                Club("BMW Motorcycle Owners of America", "Rallies and tech days, any bike welcome", ClubKind.club, "https://www.bmwmoa.org/"),
                Club.subreddit("motorcycles"),
                Club.subreddit("motorcyclemaintenance", "Wrenching help for every bike"),
            )
        VehicleKind.rv, VehicleKind.camper ->
            listOf(
                Club("Good Sam", "Campground discounts and roadside help", ClubKind.organization, "https://www.goodsam.com/"),
                Club("Escapees RV Club", "Full-timer community, mail service and parks", ClubKind.club, "https://www.escapees.com/"),
                Club("FRVA", "The Family RV Association, formerly FMCA", ClubKind.club, "https://www.frva.com/"),
                Club.subreddit("RVLiving"),
            )
        VehicleKind.trailer ->
            listOf(Club.subreddit("trailers", "Hitching, wiring and bearings"))
        VehicleKind.boat, VehicleKind.personalWatercraft ->
            listOf(
                Club("BoatUS", "Towing on the water, insurance and advocacy", ClubKind.organization, "https://www.boatus.com/"),
                Club("U.S. Coast Guard Auxiliary", "Free vessel safety checks", ClubKind.organization, "https://cgaux.org/vsc/"),
                Club.subreddit("boating"),
            )
        VehicleKind.sailboat ->
            listOf(
                Club("US Sailing", "Training, racing and local clubs", ClubKind.organization, "https://www.ussailing.org/"),
                Club("BoatUS", "Towing on the water, insurance and advocacy", ClubKind.organization, "https://www.boatus.com/"),
                Club.subreddit("sailing"),
            )
        VehicleKind.aircraft ->
            listOf(
                Club("AOPA", "Pilot advocacy, legal plans and the Pilot magazine", ClubKind.organization, "https://www.aopa.org/"),
                Club("EAA", "Chapters, Young Eagles and AirVenture Oshkosh", ClubKind.club, "https://www.eaa.org/"),
                Club.subreddit("flying"),
            )
        VehicleKind.atv ->
            listOf(Club("National Off-Highway Vehicle Conservation Council", "Trails and riding areas", ClubKind.organization, "https://nohvcc.org/"), Club.subreddit("ATV"), Club.subreddit("SXSCommunity"))
        VehicleKind.snowmobile ->
            listOf(Club("American Council of Snowmobile Associations", "Find your state association and trail maps", ClubKind.organization, "https://www.snowmobilers.org/"), Club.subreddit("snowmobiling"))
        VehicleKind.tractor ->
            listOf(Club.subreddit("tractors"), Club.subreddit("lawncare"))
        VehicleKind.ebike ->
            listOf(Club("League of American Bicyclists", "Bike-friendly advocacy and classes", ClubKind.organization, "https://bikeleague.org/"), Club.subreddit("ebikes"))
        VehicleKind.golfCart ->
            listOf(Club.subreddit("golfcarts"))
        VehicleKind.other ->
            listOf(Club.subreddit("MechanicAdvice", "Ask a mechanic, free"))
    }
}

