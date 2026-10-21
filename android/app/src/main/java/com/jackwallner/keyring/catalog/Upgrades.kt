package com.jackwallner.keyring.catalog

import com.jackwallner.keyring.model.Powertrain
import com.jackwallner.keyring.model.VehicleKind

@Suppress("EnumEntryName")
enum class UpgradeCategory(val title: String) {
    performance("Performance"), handling("Handling"), detailing("Detailing"), safety("Safety"),
    protection("Protection"), convenience("Convenience"), care("Care kit"),
}

/** An upgrade owners recommend to each other; `query` fills `{vehicle}` and `{make}` like catalog gear. */
data class Upgrade(val title: String, val why: String, val symbol: String, val category: UpgradeCategory, val query: String)

/** Ported from `Shared/Catalog/Upgrades.swift`; `ExploreParityTest` checks every literal. */
object UpgradeCatalog {
    fun upgrades(kind: VehicleKind, powertrain: Powertrain): List<Upgrade> = when (kind) {
        VehicleKind.car, VehicleKind.suv, VehicleKind.van, VehicleKind.truck -> road(kind, powertrain)
        VehicleKind.motorcycle, VehicleKind.scooter -> motorcycle
        VehicleKind.rv, VehicleKind.camper -> rv
        VehicleKind.trailer -> trailer
        VehicleKind.boat, VehicleKind.personalWatercraft, VehicleKind.sailboat -> boat
        VehicleKind.aircraft -> aircraft
        VehicleKind.atv, VehicleKind.snowmobile -> powersports
        VehicleKind.tractor -> tractor
        VehicleKind.ebike -> ebike
        VehicleKind.golfCart -> golfCart
        VehicleKind.other -> generic
    }

    /** An EV has no intake, exhaust or fluid to upgrade; trucks and SUVs level and go all-terrain instead of lowering. */
    fun road(kind: VehicleKind, powertrain: Powertrain): List<Upgrade> {
        val offRoad = kind == VehicleKind.truck || kind == VehicleKind.suv
        val list = if (powertrain == Powertrain.electric) mutableListOf() else performance.toMutableList()
        list += if (offRoad) allTerrainTires else performanceTires
        list += handling
        if (kind == VehicleKind.car) list += carHandling
        if (offRoad) list += levelingKit
        return list + detailing
    }

    val performance: List<Upgrade> = listOf(
        Upgrade(title = "Brake pads and rotors", why = "The upgrade you feel every drive: shorter stops and less fade than worn factory parts, for a little more dust or noise.", symbol = "exclamationmark.brakesignal", category = UpgradeCategory.performance, query = "{vehicle} brake pads and rotors"),
        Upgrade(title = "Cold air intake", why = "Mostly sound and throttle feel. Expect a few horsepower on a non-turbo engine and next to nothing on a stock turbo without a tune.", symbol = "wind", category = UpgradeCategory.performance, query = "{vehicle} cold air intake"),
        Upgrade(title = "Cat-back exhaust", why = "Bought for the sound, not the power. Listen to clips first, since drone on the highway is the common regret.", symbol = "speaker.wave.3.fill", category = UpgradeCategory.performance, query = "{vehicle} cat back exhaust"),
        Upgrade(title = "High-temp brake fluid", why = "Only worth it for mountain roads or track days. For commuting, fresh fluid at the factory spec does the job.", symbol = "drop.fill", category = UpgradeCategory.performance, query = "DOT 4 high temperature brake fluid"),
    )

    val performanceTires = Upgrade(title = "Performance tires", why = "The biggest handling gain for the money, everywhere owners compare notes. Match the size on the driver's door sticker and pick for your climate.", symbol = "steeringwheel", category = UpgradeCategory.handling, query = "{vehicle} performance tires")

    val allTerrainTires = Upgrade(title = "All-terrain tires", why = "More grip on gravel, mud and snow for a little road noise and mileage. Match the size on the driver's door sticker.", symbol = "steeringwheel", category = UpgradeCategory.handling, query = "{vehicle} all terrain tires")

    val handling: List<Upgrade> = listOf(
        Upgrade(title = "Shocks and struts", why = "Fresh dampers bring back the control worn ones lose so gradually you stop noticing. Usually done past 60,000 miles or with a lift.", symbol = "arrow.up.and.down.circle.fill", category = UpgradeCategory.handling, query = "{vehicle} shocks and struts"),
        Upgrade(title = "Rear sway bar", why = "Cuts body roll in corners and when towing without making the ride harsh. Check the listing includes the bar, not just end links.", symbol = "arrow.left.and.right.circle.fill", category = UpgradeCategory.handling, query = "{vehicle} rear sway bar"),
    )

    val carHandling: List<Upgrade> = listOf(
        Upgrade(title = "Lowering springs", why = "Less roll and a better stance for a firmer ride. Keep it under about two inches or stock shocks wear out fast.", symbol = "arrow.down.to.line", category = UpgradeCategory.handling, query = "{vehicle} lowering springs"),
        Upgrade(title = "Strut tower brace", why = "Cheap and a bolt-on, but owners call the gain small. Sharper turn-in more than lap times.", symbol = "wrench.adjustable.fill", category = UpgradeCategory.handling, query = "{vehicle} strut tower brace"),
    )

    val levelingKit = Upgrade(title = "Leveling kit", why = "Raises the front to match the rear and makes room for bigger tires. It's for looks and clearance, not handling.", symbol = "arrow.up.to.line", category = UpgradeCategory.handling, query = "{vehicle} leveling kit")

    val detailing: List<Upgrade> = listOf(
        Upgrade(title = "Two-bucket wash kit", why = "Grit guards keep dirt off the mitt, which is how most swirl marks get started.", symbol = "bubbles.and.sparkles.fill", category = UpgradeCategory.detailing, query = "car wash bucket kit grit guard"),
        Upgrade(title = "Microfiber drying towels", why = "A big plush towel dries without scratching and replaces the chamois.", symbol = "rectangle.stack.fill", category = UpgradeCategory.detailing, query = "microfiber car drying towel"),
        Upgrade(title = "Clay bar kit", why = "Pulls out the bonded grit washing leaves behind, so paint feels smooth and wax bonds. Start with a mild clay.", symbol = "circle.hexagongrid.fill", category = UpgradeCategory.detailing, query = "clay bar kit car"),
        Upgrade(title = "Ceramic spray sealant", why = "Months of gloss and water beading from a spray-on, wipe-off coat. Far easier than a full ceramic coating.", symbol = "sparkles", category = UpgradeCategory.detailing, query = "ceramic spray coating car"),
        Upgrade(title = "Trim restorer", why = "Brings faded black plastic back for months, the quickest way to make an older car look newer.", symbol = "paintbrush.fill", category = UpgradeCategory.detailing, query = "ceramic trim restorer"),
        Upgrade(title = "Dual action polisher", why = "The first real tool detailers suggest. It removes swirls safely, but plan on pads, polish and an afternoon of practice.", symbol = "circle.dashed.inset.filled", category = UpgradeCategory.detailing, query = "dual action polisher car"),
    )

    val motorcycle: List<Upgrade> = listOf(
        Upgrade(title = "Battery tender", why = "A maintainer through the off season is the difference between a spring start and a new battery.", symbol = "minus.plus.batteryblock.fill", category = UpgradeCategory.care, query = "motorcycle battery tender"),
        Upgrade(title = "Chain cleaning kit", why = "Brush, cleaner and lube in one kit makes the 500 mile chain job quick.", symbol = "link", category = UpgradeCategory.care, query = "motorcycle chain cleaning kit"),
        Upgrade(title = "Rear stand", why = "Lifts the back wheel for chain work and tire checks.", symbol = "arrow.up.to.line", category = UpgradeCategory.care, query = "motorcycle rear paddock stand"),
        Upgrade(title = "Helmet communicator", why = "Navigation and calls without taking a hand off the bars.", symbol = "headphones", category = UpgradeCategory.convenience, query = "motorcycle helmet bluetooth communicator"),
        Upgrade(title = "Frame sliders", why = "A tip-over in a parking lot stays a scuff instead of a cracked fairing.", symbol = "shield.fill", category = UpgradeCategory.protection, query = "{vehicle} frame sliders"),
        Upgrade(title = "Waterproof cover", why = "Keeps rain, sun and birds off between rides.", symbol = "cloud.rain.fill", category = UpgradeCategory.protection, query = "waterproof motorcycle cover"),
    )

    val rv: List<Upgrade> = listOf(
        Upgrade(title = "Surge protector", why = "One bad campground pedestal can fry the converter and every appliance aboard.", symbol = "bolt.shield.fill", category = UpgradeCategory.safety, query = "rv surge protector 30 amp"),
        Upgrade(title = "Water pressure regulator", why = "Protects your plumbing from high pressure park water.", symbol = "drop.degreesign.fill", category = UpgradeCategory.protection, query = "rv water pressure regulator with gauge"),
        Upgrade(title = "Tire pressure monitor", why = "RV blowouts are expensive and dangerous; a monitor shows trouble on the dash.", symbol = "gauge.with.dots.needle.33percent", category = UpgradeCategory.safety, query = "rv tire pressure monitoring system"),
        Upgrade(title = "Leveling blocks", why = "Fast, stackable leveling on uneven sites.", symbol = "square.3.layers.3d", category = UpgradeCategory.convenience, query = "rv leveling blocks"),
        Upgrade(title = "Drinking water hose and filter", why = "A dedicated hose and inline filter for the fresh tank.", symbol = "drop.fill", category = UpgradeCategory.care, query = "rv drinking water hose filter"),
        Upgrade(title = "Sewer hose kit", why = "A good kit makes the least favorite job quick and clean.", symbol = "arrow.down.to.line", category = UpgradeCategory.care, query = "rv sewer hose kit"),
    )

    val trailer: List<Upgrade> = listOf(
        Upgrade(title = "Bearing grease gun", why = "Repacking bearings yourself is the cheapest way to avoid a roadside failure.", symbol = "gearshape.2.fill", category = UpgradeCategory.care, query = "grease gun trailer bearings"),
        Upgrade(title = "Spare tire and mount", why = "Trailer tire sizes are hard to find on a Sunday.", symbol = "circle.circle.fill", category = UpgradeCategory.safety, query = "{vehicle} trailer spare tire"),
        Upgrade(title = "LED trailer lights", why = "LEDs outlast bulbs and survive dunking at the ramp.", symbol = "lightbulb.fill", category = UpgradeCategory.safety, query = "led trailer light kit"),
        Upgrade(title = "Coupler lock", why = "Stops someone from hitching up and driving away.", symbol = "lock.fill", category = UpgradeCategory.safety, query = "trailer coupler lock"),
    )

    val boat: List<Upgrade> = listOf(
        Upgrade(title = "Onboard battery charger", why = "Keeps batteries topped up at the dock or in storage.", symbol = "minus.plus.batteryblock.fill", category = UpgradeCategory.care, query = "marine onboard battery charger"),
        Upgrade(title = "Fuel stabilizer", why = "Ethanol fuel goes stale fast; stabilizer is the cheapest winterizing step.", symbol = "fuelpump.fill", category = UpgradeCategory.care, query = "marine fuel stabilizer"),
        Upgrade(title = "Inflatable life jackets", why = "Comfortable enough that people actually wear them.", symbol = "lifepreserver.fill", category = UpgradeCategory.safety, query = "inflatable life jacket"),
        Upgrade(title = "Bilge pump backup", why = "A second automatic pump is cheap insurance on a mooring.", symbol = "water.waves.and.arrow.down", category = UpgradeCategory.safety, query = "automatic bilge pump"),
        Upgrade(title = "Boat cover", why = "Sun and rain wear out vinyl and canvas fastest.", symbol = "umbrella.fill", category = UpgradeCategory.protection, query = "{vehicle} boat cover"),
        Upgrade(title = "Flush muffs", why = "Rinse an outboard with fresh water after every salt run.", symbol = "drop.triangle.fill", category = UpgradeCategory.care, query = "outboard motor flush muffs"),
    )

    val aircraft: List<Upgrade> = listOf(
        Upgrade(title = "Engine monitor", why = "Per-cylinder temperatures catch trouble long before an annual does.", symbol = "waveform.path.ecg", category = UpgradeCategory.safety, query = "aircraft engine monitor"),
        Upgrade(title = "Carbon monoxide detector", why = "A cracked exhaust can poison a cabin without any smell.", symbol = "sensor.fill", category = UpgradeCategory.safety, query = "aviation carbon monoxide detector"),
        Upgrade(title = "Sun shade and cowl plugs", why = "Keeps the panel cool and birds out of the cowling.", symbol = "sun.max.fill", category = UpgradeCategory.protection, query = "{make} aircraft sunshade cowl plugs"),
        Upgrade(title = "Preheater", why = "Cold starts are the hardest minutes on an engine.", symbol = "thermometer.sun.fill", category = UpgradeCategory.care, query = "aircraft engine preheater"),
        Upgrade(title = "Fuel tester", why = "Sump every tank, every preflight.", symbol = "testtube.2", category = UpgradeCategory.safety, query = "aircraft fuel sampler tester"),
    )

    val powersports: List<Upgrade> = listOf(
        Upgrade(title = "Battery tender", why = "Seasonal machines kill batteries in storage.", symbol = "minus.plus.batteryblock.fill", category = UpgradeCategory.care, query = "powersports battery tender"),
        Upgrade(title = "Winch", why = "Self-recovery when the trail gets the better of you.", symbol = "arrow.uturn.backward.circle.fill", category = UpgradeCategory.safety, query = "{vehicle} winch"),
        Upgrade(title = "Skid plates", why = "Protects the underside from rocks and stumps.", symbol = "shield.lefthalf.filled", category = UpgradeCategory.protection, query = "{vehicle} skid plate"),
        Upgrade(title = "Storage cover", why = "Keeps rodents and sun off between seasons.", symbol = "umbrella.fill", category = UpgradeCategory.protection, query = "{vehicle} cover"),
    )

    val tractor: List<Upgrade> = listOf(
        Upgrade(title = "Blade sharpener", why = "A sharp blade cuts cleaner and saves fuel.", symbol = "scissors", category = UpgradeCategory.care, query = "lawn mower blade sharpener"),
        Upgrade(title = "Seat cover", why = "Saves a cracked seat and a sore back.", symbol = "chair.fill", category = UpgradeCategory.protection, query = "tractor seat cover"),
        Upgrade(title = "Battery tender", why = "Winter storage is hard on small batteries.", symbol = "minus.plus.batteryblock.fill", category = UpgradeCategory.care, query = "lawn tractor battery maintainer"),
        Upgrade(title = "Grease gun", why = "Most tractor wear starts at a dry fitting.", symbol = "gearshape.2.fill", category = UpgradeCategory.care, query = "grease gun"),
    )

    val ebike: List<Upgrade> = listOf(
        Upgrade(title = "Heavy-duty lock", why = "E-bikes are top theft targets; a rated U-lock or chain matters.", symbol = "lock.fill", category = UpgradeCategory.safety, query = "ebike heavy duty lock"),
        Upgrade(title = "Floor pump with gauge", why = "Correct pressure is free range and fewer flats.", symbol = "gauge.with.dots.needle.50percent", category = UpgradeCategory.care, query = "bike floor pump with gauge"),
        Upgrade(title = "Bright lights", why = "Be seen at e-bike speeds, day and night.", symbol = "flashlight.on.fill", category = UpgradeCategory.safety, query = "ebike front rear light set"),
        Upgrade(title = "GPS tracker", why = "A hidden tracker helps recover a stolen bike.", symbol = "location.fill", category = UpgradeCategory.safety, query = "bike gps tracker hidden"),
    )

    val golfCart: List<Upgrade> = listOf(
        Upgrade(title = "Battery watering system", why = "Fills every cell at once, which keeps lead-acid packs alive longer.", symbol = "drop.fill", category = UpgradeCategory.care, query = "golf cart battery watering system"),
        Upgrade(title = "Enclosure", why = "Turns a fair-weather cart into a year-round one.", symbol = "cloud.rain.fill", category = UpgradeCategory.protection, query = "{make} golf cart enclosure"),
        Upgrade(title = "LED light kit", why = "Safer driving at dusk around the neighborhood.", symbol = "lightbulb.fill", category = UpgradeCategory.safety, query = "golf cart led light kit"),
    )

    val generic: List<Upgrade> = listOf(
        Upgrade(title = "Battery maintainer", why = "Anything that sits needs one.", symbol = "minus.plus.batteryblock.fill", category = UpgradeCategory.care, query = "battery maintainer"),
        Upgrade(title = "Cover", why = "Sun and weather wear out everything faster.", symbol = "umbrella.fill", category = UpgradeCategory.protection, query = "{vehicle} cover"),
    )
}
