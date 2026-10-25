package com.jackwallner.keyring.catalog

import com.jackwallner.keyring.model.FinalDrive
import com.jackwallner.keyring.model.MeterUnit
import com.jackwallner.keyring.model.Powertrain
import com.jackwallner.keyring.model.UsageEvent
import com.jackwallner.keyring.model.VehicleKind
import com.jackwallner.keyring.model.VehicleTrait
import java.util.Locale

@Suppress("EnumEntryName")
enum class Difficulty(val title: String) {
    diy("Easy at home"), moderate("Handy owners"), shop("Usually a shop job")
}

data class GearSuggestion(val title: String, val query: String)

/**
 * One recommended job: what it is, how often, and what you'd need for it.
 * Intervals are conservative "normal use" figures, a starting point the owner
 * edits, never a claim about a specific model. Transcribed mechanically from
 * `Shared/Catalog/MaintenanceCatalog.swift`; `CatalogParityTest` checks every
 * Swift literal against this file.
 */
data class CatalogItem(
    val key: String,
    val name: String,
    val detail: String,
    val symbol: String,
    val miles: Double? = null,
    val hours: Double? = null,
    val months: Int? = null,
    val auxHours: Double? = null,
    val calendarMonths: Boolean = false,
    val trigger: UsageEvent? = null,
    val isCore: Boolean = true,
    val difficulty: Difficulty = Difficulty.diy,
    val gear: List<GearSuggestion> = emptyList(),
    val source: String? = null,
    /** A heading the schedule sorts the job under ("Brakes", "Chain"). */
    val group: String? = null,
) {
    /** The distance interval in the vehicle's own meter, or null when the job is time-only for it. */
    fun distanceInterval(meter: MeterUnit): Double? = when (meter) {
        MeterUnit.miles -> miles
        MeterUnit.kilometers -> miles?.let { meter.fromCatalogMiles(it) }
        MeterUnit.hours -> hours
        MeterUnit.none -> null
    }

    /** The detail text in the reader's unit. */
    fun detail(meter: MeterUnit): String = if (meter == MeterUnit.kilometers) metric(detail) else detail

    companion object {
        private val milesPattern = Regex("""(\d[\d,]*)(?: to (\d[\d,]*))? miles""")

        fun metric(text: String): String {
            fun km(raw: String?): String? {
                val miles = raw?.replace(",", "")?.toDoubleOrNull() ?: return null
                val value = miles * 1.609344
                val step = if (value >= 5_000) 1_000.0 else if (value >= 1_000) 500.0 else if (value >= 100) 50.0 else 10.0
                return "%,d".format(Locale.US, (Math.floor(value / step + 0.5) * step).toLong())
            }
            val replaced = milesPattern.replace(text) { match ->
                val first = km(match.groupValues[1]) ?: return@replace match.value
                val second = match.groups[2]?.value?.let(::km)
                if (second != null) "$first to $second km" else "$first km"
            }
            return replaced.replace("few thousand miles", "few thousand km")
        }
    }
}

object MaintenanceCatalog {
    /** Regions where winter tires go on every fall, so the swap starts on the schedule. */
    val winterTireRegions: Set<String> = setOf("CA", "NO", "SE", "FI", "IS", "EE", "LV", "LT", "AT", "CH", "DE", "CZ", "SK", "SI", "RU")

    /** Road cars built before about 1990: carbureted, mineral oil, grease fittings. */
    fun isClassic(kind: VehicleKind, year: Int): Boolean = kind.isRoad && year > 1885 && year < 1990

    fun defaultRegion(): String? = Locale.getDefault().country.ifEmpty { null }

    /** Every job that applies to a vehicle of this kind and powertrain, core items first. */
    fun items(
        kind: VehicleKind,
        powertrain: Powertrain,
        year: Int = 0,
        traits: Set<VehicleTrait> = emptySet(),
        drive: FinalDrive? = null,
        region: String? = defaultRegion(),
    ): List<CatalogItem> {
        var list = baseItems(kind, powertrain, region)
        val road = kind.isRoad
        if (road) list = list + winterTires(core = region in winterTireRegions)
        if (kind == VehicleKind.motorcycle && powertrain != Powertrain.electric) list = motorcycleDrive(list, drive)
        if (isClassic(kind, year) && powertrain.burnsFuel) list = list.map(::classicTuned) + classicExtras
        if (VehicleTrait.fourByFour in traits && (road || kind == VehicleKind.atv)) {
            list = list.map(::dustTuned) + fourByFour
        } else if ((kind == VehicleKind.truck || kind == VehicleKind.suv) && powertrain != Powertrain.electric) {
            list = list + rearDiff
        }
        if (VehicleTrait.track in traits && (road || kind == VehicleKind.motorcycle)) list = list.map(::trackTuned) + trackExtras
        if (VehicleTrait.collector in traits && (road || kind == VehicleKind.motorcycle)) {
            list = list.map(::collectorTuned) + collectorExtras(powertrain)
        }
        val unique = list.distinctBy { it.key }
        return unique.filter { it.isCore } + unique.filter { !it.isCore }
    }

    private fun baseItems(kind: VehicleKind, powertrain: Powertrain, region: String?): List<CatalogItem> {
        val list = when (kind) {
            VehicleKind.car, VehicleKind.suv, VehicleKind.van, VehicleKind.truck ->
                if (powertrain == Powertrain.electric) electricRoad else roadEngine(powertrain)
            VehicleKind.motorcycle -> if (powertrain == Powertrain.electric) electricMotorcycle else motorcycle
            VehicleKind.scooter -> if (powertrain == Powertrain.electric) electricMotorcycle else scooter
            VehicleKind.rv -> roadEngine(powertrain) + rvHouse
            VehicleKind.camper -> rvHouse + trailerRunningGear
            VehicleKind.trailer -> trailerRunningGear
            VehicleKind.boat -> boatEngine(powertrain) + boatCommon
            VehicleKind.sailboat -> sailboatRig + (if (powertrain == Powertrain.none) emptyList() else boatEngine(powertrain)) + boatCommon
            VehicleKind.personalWatercraft -> personalWatercraft
            VehicleKind.aircraft -> aircraft(powertrain)
            VehicleKind.atv -> atv
            VehicleKind.snowmobile -> snowmobile
            VehicleKind.tractor -> if (powertrain == Powertrain.electric) electricMower else tractor
            VehicleKind.ebike -> ebike
            VehicleKind.golfCart -> if (powertrain == Powertrain.gasoline) gasGolfCart else electricGolfCart
            VehicleKind.other -> generic
        }.toMutableList()
        val washKinds = setOf(VehicleKind.car, VehicleKind.suv, VehicleKind.van, VehicleKind.truck, VehicleKind.motorcycle, VehicleKind.scooter, VehicleKind.rv)
        if (kind in washKinds) list.add(wash)
        list += paperwork(kind, region)
        return list
    }

    fun usesCalendarMonths(key: String?, kind: VehicleKind): Boolean {
        if (key == null || kind != VehicleKind.aircraft) return false
        return aircraft(Powertrain.piston).firstOrNull { it.key == key }?.calendarMonths ?: false
    }

    fun item(key: String, kind: VehicleKind, powertrain: Powertrain, year: Int = 0): CatalogItem? =
        items(kind, powertrain, year).firstOrNull { it.key == key }

    val wash = CatalogItem(
        key = "wash", name = "Wash", detail = "No schedule, no nagging. Log a wash and the list shows how long it's been.",
        symbol = "bubbles.and.sparkles",
        gear = listOf(GearSuggestion(title = "Car wash soap", query = "car wash soap"),
               GearSuggestion(title = "Microfiber drying towels", query = "microfiber car drying towel"))
    )

    fun winterTires(core: Boolean): CatalogItem =
        CatalogItem(
            key = "winterTires", name = "Winter tire swap",
            detail = "On when it stays below about 7°C (45°F), off again in spring. A good moment to check pressure and tread on the set coming off.",
            symbol = "snowflake", months = 6, isCore = core,
            gear = listOf(GearSuggestion(title = "Tire storage bags", query = "tire storage bags"),
                   GearSuggestion(title = "Impact wrench", query = "cordless impact wrench lug nuts"))
        )

    /** Shorter intervals for a classic: mineral oil, older plugs and coolant. */
    private fun classicTuned(item: CatalogItem): CatalogItem = when (item.key) {
        "oil" -> item.copy(miles = 3_000.0, months = 6,
            detail = "Older engines on conventional oil want it every 3,000 miles or six months, and a zinc additive or high-zinc oil for flat-tappet cams.")
        "plugs" -> item.copy(miles = 30_000.0, isCore = true)
        "coolant" -> item.copy(miles = 30_000.0, months = 24, isCore = true)
        else -> item
    }

    private val classicExtras: List<CatalogItem> = listOf(
        CatalogItem(
            key = "chassisLube", name = "Grease the chassis", detail = "Older cars have grease fittings on the steering and suspension. A few pumps each at every oil change.",
            symbol = "wrench.adjustable", miles = 3_000.0, months = 6, difficulty = Difficulty.moderate,
            gear = listOf(GearSuggestion(title = "Grease gun", query = "grease gun chassis"))
        ),
        CatalogItem(
            key = "tuneUp", name = "Tune-up", detail = "Points, condenser, timing and carb adjustment on cars that have them.",
            symbol = "slider.horizontal.3", miles = 12_000.0, months = 12, isCore = false, difficulty = Difficulty.moderate
        ),
    )


    /** The chain job for a chain, a belt or final-drive job otherwise. */
    private fun motorcycleDrive(list: List<CatalogItem>, drive: FinalDrive?): List<CatalogItem> = when (drive) {
        FinalDrive.belt -> list.filter { it.key != "chain" } + CatalogItem(
            key = "driveBelt", name = "Drive belt inspection", detail = "Check tension, cracks and stone damage. Most belts go 5,000 miles between checks and many tens of thousands between replacements.",
            symbol = "circle.dashed", miles = 5_000.0, months = 12, difficulty = Difficulty.moderate
        )
        FinalDrive.shaft -> list.filter { it.key != "chain" } + CatalogItem(
            key = "finalDrive", name = "Final drive oil", detail = "Shaft drives carry their own gear oil. Most call for it every 12,000 to 24,000 miles or two years.",
            symbol = "gearshape.2", miles = 18_000.0, months = 24, difficulty = Difficulty.moderate
        )
        else -> list
    }

    private val rearDiff = CatalogItem(
        key = "rearDiff", name = "Rear differential fluid", detail = "Often skipped and often called lifetime. Every 30,000 to 60,000 miles, sooner if you tow.",
        symbol = "gearshape.2", miles = 50_000.0, months = 60, isCore = false, difficulty = Difficulty.moderate
    )

    private val fourByFour: List<CatalogItem> = listOf(
        CatalogItem(
            key = "frontDiff", name = "Front differential fluid", detail = "Every 30,000 miles, and after any crossing deep enough to reach the axle. Milky fluid means water got in.",
            symbol = "gearshape.2", miles = 30_000.0, months = 36, trigger = UsageEvent.waterCrossing, difficulty = Difficulty.moderate,
            gear = listOf(GearSuggestion(title = "Gear oil", query = "75w90 gear oil"))
        ),
        CatalogItem(
            key = "rearDiff", name = "Rear differential fluid", detail = "Every 30,000 miles, sooner if you tow or wheel hard, and after deep water. Lockers may want a friction additive or not; check yours.",
            symbol = "gearshape.2", miles = 30_000.0, months = 36, trigger = UsageEvent.waterCrossing, difficulty = Difficulty.moderate,
            gear = listOf(GearSuggestion(title = "Gear oil", query = "75w90 gear oil"), GearSuggestion(title = "Fluid pump", query = "gear oil transfer pump"))
        ),
        CatalogItem(
            key = "transferCase", name = "Transfer case fluid", detail = "Every 30,000 to 60,000 miles, and after water crossings that cover it.",
            symbol = "arrow.triangle.branch", miles = 30_000.0, months = 48, trigger = UsageEvent.waterCrossing, difficulty = Difficulty.moderate
        ),
        CatalogItem(
            key = "driveline", name = "Driveline grease", detail = "U-joints, slip yoke and any zerks on the suspension. Water and mud push the old grease out.",
            symbol = "drop.triangle", miles = 5_000.0, months = 6, trigger = UsageEvent.waterCrossing, difficulty = Difficulty.moderate,
            gear = listOf(GearSuggestion(title = "Grease gun", query = "grease gun chassis"))
        ),
        CatalogItem(
            key = "cvBoots", name = "CV boots, ball joints and tie rods", detail = "Lifts and big tires work the front end hard. A torn boot is cheap; a dry CV joint isn't.",
            symbol = "wrench.adjustable", miles = 10_000.0, months = 12, isCore = false, difficulty = Difficulty.moderate
        ),
        CatalogItem(
            key = "spareTire", name = "Spare tire check", detail = "Pressure and age on the spare, and work it into the rotation if it's a full-size match.",
            symbol = "circle.circle", months = 6, isCore = false
        ),
    )

    /** Off road, the air filter is a dusty-ride job, not a mileage one. */
    private fun dustTuned(item: CatalogItem): CatalogItem =
        if (item.key != "airFilter") item
        else item.copy(trigger = UsageEvent.dust, detail = "Check it after every dusty trail; replace sooner than the book says.")

    /** Brakes and fluids around every event, not every few years. */
    private fun trackTuned(item: CatalogItem): CatalogItem = when (item.key) {
        "brakeFluid" -> item.copy(months = 6, trigger = UsageEvent.trackDay, isCore = true,
            detail = "Bleed before each event with high-temp fluid; a full flush at least twice a season. Boiled fluid is a long pedal on lap three.")
        "brakes" -> item.copy(trigger = UsageEvent.trackDay,
            detail = "Pads, rotors and lines before every event. Swap to track pads and back again if you run two sets.")
        "oil" -> item.copy(miles = 3_000.0, months = 6,
            detail = "Track heat shears oil fast. Many change it every two or three events or 3,000 miles, and send a sample for analysis.")
        "alignment" -> item.copy(months = 12, isCore = true)
        else -> item
    }

    private val trackExtras: List<CatalogItem> = listOf(
        CatalogItem(
            key = "trackPrep", name = "Torque wheels and nut-and-bolt", detail = "Lug nuts to spec, suspension and caliper bolts checked, nothing loose in the cabin. Before the first session and after the last.",
            symbol = "checklist", trigger = UsageEvent.trackDay,
            gear = listOf(GearSuggestion(title = "Torque wrench", query = "1/2 inch torque wrench"))
        ),
        CatalogItem(
            key = "trackTires", name = "Tire pressures and wear", detail = "Cold pressures before, hot pressures after each session, and a look for cording. Note heat cycles on track tires.",
            symbol = "gauge.with.dots.needle.33percent", trigger = UsageEvent.trackDay,
            gear = listOf(GearSuggestion(title = "Tire pyrometer", query = "tire pyrometer"))
        ),
        CatalogItem(
            key = "oilAnalysis", name = "Oil analysis", detail = "A sample at each change shows bearing and ring wear before it's a noise. Log the numbers to watch the trend.",
            symbol = "testtube.2", months = 6, isCore = false
        ),
    )


    /** A car that sits ages faster than it wears: time decides, not miles. */
    private fun collectorTuned(item: CatalogItem): CatalogItem = when (item.key) {
        "oil" -> item.copy(months = 12,
            detail = "Change it once a year even at a few hundred miles. Acids and moisture build up in oil that sits.")
        "brakeFluid" -> item.copy(isCore = true, months = 24)
        "tires", "trailerTires" -> item.copy(isCore = true, months = 72,
            detail = "Replace by the date code, around six years, whatever the tread says. Old rubber looks fine until it lets go.")
        "coolant" -> item.copy(isCore = true, months = 36)
        else -> item
    }

    private fun collectorExtras(powertrain: Powertrain): List<CatalogItem> {
        val items = mutableListOf(
            CatalogItem(
                key = "exercise", name = "Drive it", detail = "Twenty minutes to full temperature keeps seals wet, brakes free and the battery up.",
                symbol = "steeringwheel", months = 1
            ),
            CatalogItem(
                key = "tender", name = "Battery tender check", detail = "On a maintainer between drives, and the water checked on a flooded battery.",
                symbol = "minus.plus.batteryblock", months = 3,
                gear = listOf(GearSuggestion(title = "Battery maintainer", query = "smart battery maintainer"))
            ),
        )
        if (powertrain.burnsFuel) {
            items.add(CatalogItem(
                key = "layup", name = "Layup for winter", detail = "Fuel stabilized and topped up, fresh oil, tires up a few psi, mice kept out.",
                symbol = "moon.zzz", months = 12,
                gear = listOf(GearSuggestion(title = "Fuel stabilizer", query = "fuel stabilizer"))
            ))
        }
        return items
    }

    // MARK: - Road vehicles

    fun roadEngine(powertrain: Powertrain): List<CatalogItem> {
        val items = mutableListOf(
            CatalogItem(
                key = "oil", name = "Oil and filter", detail = "Fresh oil is the cheapest engine insurance there is. Most modern engines on synthetic run 5,000 to 10,000 miles; check your manual for yours.",
                symbol = "drop.fill", miles = 7_500.0, months = 12,
                gear = listOf(GearSuggestion(title = "Oil filter for your vehicle", query = "{vehicle} oil filter"),
                       GearSuggestion(title = "Drain pan", query = "oil drain pan"),
                       GearSuggestion(title = "Filter wrench", query = "oil filter wrench")),
                source = "Owner's manual norm; AAA"
            ),
            CatalogItem(
                key = "rotate", name = "Tire rotation", detail = "Moving tires front to back evens out wear, and most shops do it with the oil change.",
                symbol = "arrow.triangle.2.circlepath", miles = 7_500.0, months = 12,
                gear = listOf(GearSuggestion(title = "Torque wrench", query = "1/2 inch torque wrench"),
                       GearSuggestion(title = "Floor jack and stands", query = "floor jack and jack stands"))
            ),
            CatalogItem(
                key = "cabinFilter", name = "Cabin air filter", detail = "Keeps dust and pollen out of the air you breathe. Usually a five minute job behind the glovebox.",
                symbol = "wind", miles = 15_000.0, months = 12,
                gear = listOf(GearSuggestion(title = "Cabin filter for your vehicle", query = "{vehicle} cabin air filter"))
            ),
            CatalogItem(
                key = "airFilter", name = "Engine air filter", detail = "A clogged filter costs power and fuel. Replace sooner on dusty roads.",
                symbol = "aqi.medium", miles = 30_000.0, months = 36,
                gear = listOf(GearSuggestion(title = "Engine air filter", query = "{vehicle} engine air filter"))
            ),
            CatalogItem(
                key = "brakes", name = "Brake inspection", detail = "Pads, rotors and lines checked before they're a problem.",
                symbol = "exclamationmark.octagon", miles = 15_000.0, months = 12, difficulty = Difficulty.moderate,
                gear = listOf(GearSuggestion(title = "Brake pads", query = "{vehicle} brake pads"))
            ),
            CatalogItem(
                key = "wipers", name = "Wiper blades", detail = "Streaking or chattering means they're done. Sun kills them faster than use.",
                symbol = "windshield.front.and.wiper", months = 12,
                gear = listOf(GearSuggestion(title = "Wiper blades for your vehicle", query = "{vehicle} wiper blades"))
            ),
            CatalogItem(
                key = "battery", name = "Battery test", detail = "Most 12-volt batteries last three to five years. A free test at a parts store spots a weak one before a cold morning does.",
                symbol = "minus.plus.batteryblock", months = 12,
                gear = listOf(GearSuggestion(title = "Portable jump starter", query = "portable car jump starter"),
                       GearSuggestion(title = "Battery tester", query = "12v battery load tester"))
            ),
            CatalogItem(
                key = "brakeFluid", name = "Brake fluid", detail = "Brake fluid absorbs water over time, which lowers its boiling point. Most makers say every two to three years.",
                symbol = "drop.triangle", months = 36, difficulty = Difficulty.moderate,
                gear = listOf(GearSuggestion(title = "Brake bleeder kit", query = "one person brake bleeder kit"))
            ),
            CatalogItem(
                key = "coolant", name = "Coolant", detail = "Long-life coolant often goes 100,000 miles or more; older formulas need it sooner.",
                symbol = "thermometer.snowflake", miles = 100_000.0, months = 60, isCore = false, difficulty = Difficulty.moderate
            ),
            CatalogItem(
                key = "transmission", name = "Transmission fluid", detail = "Even 'lifetime' fluid benefits from a change around 60,000 miles, more if you tow.",
                symbol = "gearshape.2", miles = 60_000.0, months = 60, isCore = false, difficulty = Difficulty.shop
            ),
            CatalogItem(
                key = "alignment", name = "Wheel alignment", detail = "Pulling to one side or uneven tire wear are the tells. Check after hitting something hard.",
                symbol = "arrow.left.and.right", months = 24, isCore = false, difficulty = Difficulty.shop
            ),
            CatalogItem(
                key = "belt", name = "Drive belt inspection", detail = "Cracks or squeals mean it's time.",
                symbol = "circle.dashed", miles = 60_000.0, months = 60, isCore = false, difficulty = Difficulty.moderate
            ),
            CatalogItem(
                key = "tires", name = "New tires", detail = "Replace at 2/32 inch of tread, or about six years old whatever the tread says.",
                symbol = "circle.circle", miles = 50_000.0, months = 72, isCore = false, difficulty = Difficulty.shop,
                gear = listOf(GearSuggestion(title = "Tread depth gauge", query = "tire tread depth gauge"),
                       GearSuggestion(title = "Tire inflator", query = "portable tire inflator"))
            ),
        )
        if (powertrain == Powertrain.gasoline || powertrain == Powertrain.hybrid || powertrain == Powertrain.plugInHybrid) {
            items.add(CatalogItem(
                key = "plugs", name = "Spark plugs", detail = "Iridium plugs typically last around 100,000 miles.",
                symbol = "bolt.fill", miles = 100_000.0, isCore = false, difficulty = Difficulty.moderate,
                gear = listOf(GearSuggestion(title = "Spark plugs", query = "{vehicle} spark plugs"))
            ))
        }
        if (powertrain == Powertrain.hybrid || powertrain == Powertrain.plugInHybrid) {
            items.add(CatalogItem(
                key = "brakes", name = "Brake clean and lube", detail = "Regenerative braking spares the pads, so they can seize from disuse where roads are salted. Once a year in winter climates.",
                symbol = "exclamationmark.octagon", months = 12, isCore = powertrain == Powertrain.plugInHybrid, difficulty = Difficulty.shop
            ))
            items.add(CatalogItem(
                key = "hybridBattery", name = "Hybrid battery cooling filter", detail = "Many hybrids pull cabin air over the battery through a small filter, often under the rear seat. Pet hair clogs it.",
                symbol = "fan", months = 24, isCore = false, difficulty = Difficulty.moderate
            ))
        }
        if (powertrain == Powertrain.plugInHybrid) {
            items.add(CatalogItem(
                key = "charger", name = "Charging cable check", detail = "Look over the cable and plug for wear or heat marks.",
                symbol = "powerplug", months = 12, isCore = false
            ))
        }
        if (powertrain == Powertrain.diesel) {
            items.add(CatalogItem(
                key = "fuelFilter", name = "Fuel filter", detail = "Diesels are picky about clean fuel. Drain the water separator between changes.",
                symbol = "fuelpump", miles = 15_000.0, months = 12, difficulty = Difficulty.moderate,
                gear = listOf(GearSuggestion(title = "Fuel filter", query = "{vehicle} fuel filter"))
            ))
            items.add(CatalogItem(
                key = "def", name = "DEF top-up", detail = "Diesel exhaust fluid runs out roughly every few thousand miles.",
                symbol = "drop.halffull", miles = 5_000.0, isCore = false,
                gear = listOf(GearSuggestion(title = "Diesel exhaust fluid", query = "diesel exhaust fluid 2.5 gallon"))
            ))
        }
        return items
    }

    val electricRoad: List<CatalogItem> = listOf(
        CatalogItem(
            key = "rotate", name = "Tire rotation", detail = "EVs are heavy and quick, so tires wear faster. Rotation matters more than it does on a gas car.",
            symbol = "arrow.triangle.2.circlepath", miles = 6_500.0, months = 12,
            gear = listOf(GearSuggestion(title = "Torque wrench", query = "1/2 inch torque wrench"),
                   GearSuggestion(title = "Tire inflator", query = "portable tire inflator"))
        ),
        CatalogItem(
            key = "cabinFilter", name = "Cabin air filter", detail = "The filter that keeps the cabin air clean. Every one to two years.",
            symbol = "wind", months = 24,
            gear = listOf(GearSuggestion(title = "Cabin filter for your vehicle", query = "{vehicle} cabin air filter"))
        ),
        CatalogItem(
            key = "brakeFluid", name = "Brake fluid check", detail = "Regenerative braking means the pads rarely work, but the fluid still ages.",
            symbol = "drop.triangle", months = 48, difficulty = Difficulty.moderate
        ),
        CatalogItem(
            key = "brakes", name = "Brake clean and lube", detail = "Pads that rarely get used can seize, especially where roads are salted. Once a year in winter climates.",
            symbol = "exclamationmark.octagon", miles = 12_500.0, months = 12, difficulty = Difficulty.shop
        ),
        CatalogItem(
            key = "wipers", name = "Wiper blades", detail = "Streaking or chattering means they're done.",
            symbol = "windshield.front.and.wiper", months = 12,
            gear = listOf(GearSuggestion(title = "Wiper blades for your vehicle", query = "{vehicle} wiper blades"))
        ),
        CatalogItem(
            key = "battery12v", name = "12-volt battery", detail = "The small battery that wakes the car still wears out, usually in four to six years.",
            symbol = "minus.plus.batteryblock", months = 48, isCore = false, difficulty = Difficulty.moderate
        ),
        CatalogItem(
            key = "acDesiccant", name = "A/C desiccant", detail = "Some makers replace the A/C drying bag about every six years.",
            symbol = "snowflake", months = 72, isCore = false, difficulty = Difficulty.shop
        ),
        CatalogItem(
            key = "tires", name = "New tires", detail = "Replace at 2/32 inch of tread. EV-rated tires are quieter and carry the weight.",
            symbol = "circle.circle", miles = 40_000.0, months = 72, isCore = false, difficulty = Difficulty.shop,
            gear = listOf(GearSuggestion(title = "Tread depth gauge", query = "tire tread depth gauge"))
        ),
        CatalogItem(
            key = "charger", name = "Charging cable check", detail = "Look over the cable and plug for wear or heat marks.",
            symbol = "powerplug", months = 12, isCore = false
        ),
    )

    // MARK: - Two wheels

    val motorcycle: List<CatalogItem> = listOf(
        CatalogItem(
            key = "oil", name = "Oil and filter", detail = "Bikes work their oil hard, often sharing it with the clutch and gearbox. Most call for 3,000 to 6,000 miles.",
            symbol = "drop.fill", miles = 4_000.0, months = 12,
            gear = listOf(GearSuggestion(title = "Oil filter", query = "{vehicle} oil filter"),
                   GearSuggestion(title = "Motorcycle oil", query = "motorcycle oil 10w40 synthetic"))
        ),
        CatalogItem(
            key = "chain", name = "Chain clean, lube and adjust", detail = "Every 300 to 600 miles and after riding in the rain. Skip it if you ride a belt or shaft drive.",
            symbol = "link", miles = 500.0, months = 1,
            gear = listOf(GearSuggestion(title = "Chain lube", query = "motorcycle chain lube"),
                   GearSuggestion(title = "Chain brush", query = "motorcycle chain cleaning brush"),
                   GearSuggestion(title = "Rear stand", query = "motorcycle rear paddock stand"))
        ),
        CatalogItem(
            key = "tires", name = "Tire check", detail = "Pressure, tread and age. Two contact patches the size of a credit card hold you up.",
            symbol = "circle.circle", months = 6,
            gear = listOf(GearSuggestion(title = "Tire pressure gauge", query = "motorcycle tire pressure gauge"))
        ),
        CatalogItem(
            key = "brakeFluid", name = "Brake fluid", detail = "Every two years. Clutch fluid too if the clutch is hydraulic.",
            symbol = "drop.triangle", months = 24, difficulty = Difficulty.moderate
        ),
        CatalogItem(
            key = "airFilter", name = "Air filter", detail = "Sooner if you ride dusty roads.",
            symbol = "aqi.medium", miles = 8_000.0, months = 24,
            gear = listOf(GearSuggestion(title = "Air filter", query = "{vehicle} air filter"))
        ),
        CatalogItem(
            key = "plugs", name = "Spark plugs", detail = "Typically 8,000 to 16,000 miles depending on the engine.",
            symbol = "bolt.fill", miles = 12_000.0, isCore = false, difficulty = Difficulty.moderate
        ),
        CatalogItem(
            key = "coolant", name = "Coolant", detail = "Liquid-cooled bikes, every two to three years.",
            symbol = "thermometer.snowflake", months = 24, isCore = false, difficulty = Difficulty.moderate
        ),
        CatalogItem(
            key = "valves", name = "Valve clearance check", detail = "The big service. Intervals vary widely, so check your manual.",
            symbol = "gearshape.2", miles = 15_000.0, isCore = false, difficulty = Difficulty.shop
        ),
        CatalogItem(
            key = "forks", name = "Fork oil", detail = "Fresh fork oil brings back the front end.",
            symbol = "arrow.up.and.down", miles = 20_000.0, months = 36, isCore = false, difficulty = Difficulty.shop
        ),
        CatalogItem(
            key = "primary", name = "Primary and transmission oil", detail = "V-twins like Harleys keep separate primary and gearbox oil. Usually every 10,000 miles or so.",
            symbol = "gearshape.2", miles = 10_000.0, months = 24, isCore = false, difficulty = Difficulty.moderate
        ),
        CatalogItem(
            key = "timingBelts", name = "Timing belts", detail = "Belt-driven cams (most older Ducatis) want new belts every two years or so, whatever the miles. A snapped belt bends valves.",
            symbol = "circle.dashed", miles = 15_000.0, months = 24, isCore = false, difficulty = Difficulty.shop
        ),
        CatalogItem(
            key = "battery", name = "Battery tender over winter", detail = "A smart charger through the off season saves a dead battery in spring.",
            symbol = "minus.plus.batteryblock", months = 12, isCore = false,
            gear = listOf(GearSuggestion(title = "Battery tender", query = "motorcycle battery tender"))
        ),
    )

    val scooter: List<CatalogItem> = listOf(
        CatalogItem(key = "oil", name = "Oil change", detail = "Small engines, small oil capacity: change it often.", symbol = "drop.fill", miles = 2_000.0, months = 12,
                    gear = listOf(GearSuggestion(title = "Scooter oil", query = "4 stroke scooter oil 10w40"))),
        CatalogItem(key = "cvt", name = "Drive belt", detail = "The CVT belt is the part that strands scooters. Inspect it regularly.", symbol = "circle.dashed", miles = 6_000.0, difficulty = Difficulty.moderate),
        CatalogItem(key = "tires", name = "Tire check", detail = "Pressure, tread and age.", symbol = "circle.circle", months = 6),
        CatalogItem(key = "plugs", name = "Spark plug", detail = "A cheap part that makes cold starts easy.", symbol = "bolt.fill", miles = 4_000.0, months = 24),
        CatalogItem(key = "airFilter", name = "Air filter", detail = "Clean or replace.", symbol = "aqi.medium", miles = 4_000.0, months = 24, isCore = false),
        CatalogItem(key = "brakes", name = "Brake check", detail = "Pads and fluid.", symbol = "exclamationmark.octagon", months = 12, isCore = false),
    )

    val electricMotorcycle: List<CatalogItem> = listOf(
        CatalogItem(key = "tires", name = "Tire check", detail = "Instant torque eats rear tires. Check pressure and tread.", symbol = "circle.circle", months = 3),
        CatalogItem(key = "belt", name = "Drive belt or chain", detail = "Inspect tension and wear.", symbol = "link", miles = 3_000.0, months = 6),
        CatalogItem(key = "brakeFluid", name = "Brake fluid", detail = "Every two years.", symbol = "drop.triangle", months = 24, difficulty = Difficulty.moderate),
        CatalogItem(key = "storageCharge", name = "Storage charge", detail = "Park it between about 30 and 60 percent for long storage.", symbol = "battery.50", months = 6, isCore = false),
    )

    // MARK: - RVs, campers and trailers

    val rvHouse: List<CatalogItem> = listOf(
        CatalogItem(
            key = "roofSeals", name = "Roof and seal inspection", detail = "Water is the thing that kills RVs. Check roof sealant and every seam twice a year.",
            symbol = "house.fill", months = 6,
            gear = listOf(GearSuggestion(title = "Self-leveling sealant", query = "rv self leveling lap sealant"),
                   GearSuggestion(title = "Eternabond tape", query = "eternabond rv roof tape"))
        ),
        CatalogItem(
            key = "propane", name = "Propane system and detectors", detail = "Leak check the LP system, and test the LP, CO and smoke detectors.",
            symbol = "flame", months = 12, difficulty = Difficulty.moderate,
            gear = listOf(GearSuggestion(title = "LP leak detector", query = "propane leak detector rv"))
        ),
        CatalogItem(
            key = "waterHeater", name = "Water heater flush and anode", detail = "Flush the sediment and check the anode rod each season.",
            symbol = "drop.degreesign", months = 12,
            gear = listOf(GearSuggestion(title = "Anode rod", query = "rv water heater anode rod"),
                   GearSuggestion(title = "Tank flush wand", query = "rv water heater flush wand"))
        ),
        CatalogItem(
            key = "freshWater", name = "Sanitize fresh water", detail = "Sanitize the tank and lines at the start of each season.",
            symbol = "drop", months = 12,
            gear = listOf(GearSuggestion(title = "Water pressure regulator", query = "rv water pressure regulator"),
                   GearSuggestion(title = "Inline water filter", query = "rv inline water filter"))
        ),
        CatalogItem(
            key = "winterize", name = "Winterize", detail = "Blow out or antifreeze the plumbing before the first freeze.",
            symbol = "snowflake", months = 12,
            gear = listOf(GearSuggestion(title = "RV antifreeze", query = "rv plumbing antifreeze"),
                   GearSuggestion(title = "Blowout plug", query = "rv winterizing blowout plug"))
        ),
        CatalogItem(key = "slides", name = "Slide-out seals and lube", detail = "Clean, condition and lube the slide mechanism.", symbol = "rectangle.expand.vertical", months = 12, isCore = false),
        CatalogItem(key = "houseBattery", name = "House batteries", detail = "Check water levels on flooded batteries, and terminals on all of them.", symbol = "battery.75", months = 3, isCore = false),
        CatalogItem(key = "generator", name = "Generator service", detail = "Oil and filter about every 150 hours or once a year, plus a monthly exercise run. Generators hate sitting.", symbol = "bolt.circle", months = 12, auxHours = 150.0, isCore = false, difficulty = Difficulty.moderate,
                    gear = listOf(GearSuggestion(title = "Generator oil filter", query = "RV generator oil filter"))),
        CatalogItem(key = "acFilters", name = "A/C filters", detail = "Wash the roof unit filters.", symbol = "air.conditioner.horizontal", months = 6, isCore = false),
    )

    val trailerRunningGear: List<CatalogItem> = listOf(
        CatalogItem(
            key = "bearings", name = "Wheel bearings", detail = "Repack or check bearings once a year or every 12,000 miles. Boat trailers that get dunked need them more.",
            symbol = "gearshape", miles = 12_000.0, months = 12, difficulty = Difficulty.moderate,
            gear = listOf(GearSuggestion(title = "Bearing kit", query = "trailer wheel bearing kit"),
                   GearSuggestion(title = "Marine grease", query = "marine wheel bearing grease"))
        ),
        CatalogItem(
            key = "trailerTires", name = "Tire age and pressure", detail = "Trailer tires age out before they wear out. Replace around five to six years from the date code.",
            symbol = "circle.circle", months = 60,
            gear = listOf(GearSuggestion(title = "Tire pressure gauge", query = "tire pressure gauge"),
                   GearSuggestion(title = "Spare tire", query = "trailer spare tire"))
        ),
        CatalogItem(
            key = "lights", name = "Lights and wiring", detail = "Check every light and the plug before a trip.",
            symbol = "lightbulb", months = 12,
            gear = listOf(GearSuggestion(title = "Trailer wiring tester", query = "trailer light tester"),
                   GearSuggestion(title = "LED trailer lights", query = "led trailer light kit"))
        ),
        CatalogItem(key = "trailerBrakes", name = "Trailer brakes", detail = "Adjust and inspect electric or surge brakes.", symbol = "exclamationmark.octagon", months = 12, isCore = false, difficulty = Difficulty.moderate),
        CatalogItem(key = "coupler", name = "Coupler, chains and jack", detail = "Lube the coupler and jack, and check the safety chains.", symbol = "link", months = 12, isCore = false),
    )

    // MARK: - Water

    fun boatEngine(powertrain: Powertrain): List<CatalogItem> {
        if (powertrain == Powertrain.electric) {
            return listOf(
                CatalogItem(key = "boatBattery", name = "Battery care", detail = "Charge after every outing and store charged.", symbol = "battery.75", months = 6),
                CatalogItem(key = "prop", name = "Propeller inspection", detail = "Pull it, check for dings and fishing line, grease the shaft.", symbol = "fanblades", hours = 100.0, months = 12),
            )
        }
        val items = mutableListOf(
            CatalogItem(
                key = "oil", name = "Engine oil and filter", detail = "Most marine four-strokes call for 100 hours or once a season, whichever comes first.",
                symbol = "drop.fill", hours = 100.0, months = 12, difficulty = Difficulty.moderate,
                gear = listOf(GearSuggestion(title = "Marine oil change kit", query = "{make} marine oil change kit"))
            ),
            CatalogItem(
                key = "impeller", name = "Water pump impeller", detail = "A cracked impeller overheats the engine fast. Most makers say every two to three years.",
                symbol = "fanblades.fill", hours = 300.0, months = 24, difficulty = Difficulty.shop,
                gear = listOf(GearSuggestion(title = "Impeller kit", query = "{make} water pump impeller kit"))
            ),
            CatalogItem(
                key = "fuelSeparator", name = "Fuel/water separator", detail = "Ethanol fuel picks up water. A fresh filter protects the injectors.",
                symbol = "fuelpump", hours = 100.0, months = 12,
                gear = listOf(GearSuggestion(title = "Separator filter", query = "marine fuel water separator filter"))
            ),
            CatalogItem(
                key = "plugs", name = "Spark plugs", detail = "Once a season on most gas engines.",
                symbol = "bolt.fill", hours = 100.0, months = 12, isCore = false, difficulty = Difficulty.moderate
            ),
            CatalogItem(
                key = "winterize", name = "Winterize or layup", detail = "Stabilize the fuel, fog the engine, drain or antifreeze, and change the oil before storage.",
                symbol = "snowflake", months = 12,
                gear = listOf(GearSuggestion(title = "Fuel stabilizer", query = "marine fuel stabilizer"),
                       GearSuggestion(title = "Fogging oil", query = "engine fogging oil"))
            ),
            CatalogItem(
                key = "commission", name = "Spring commissioning", detail = "Batteries charged and connected, hoses and clamps checked, bilge and blower tested, engine run on the hose before launch.",
                symbol = "sun.max", months = 12
            ),
        )
        if (powertrain == Powertrain.outboard || powertrain == Powertrain.sterndrive) {
            items.add(1, CatalogItem(
                key = "gearOil", name = "Lower unit gear oil", detail = "Milky gear oil means water got in. Change it every season.",
                symbol = "drop.halffull", hours = 100.0, months = 12,
                gear = listOf(GearSuggestion(title = "Gear lube and pump", query = "{make} lower unit gear lube pump"))
            ))
            items.add(CatalogItem(
                key = "prop", name = "Propeller and shaft", detail = "Pull the prop, check for damage and fishing line, grease the shaft.",
                symbol = "fanblades", hours = 100.0, months = 12,
                gear = listOf(GearSuggestion(title = "Prop wrench", query = "boat propeller wrench"))
            ))
        }
        if (powertrain == Powertrain.sterndrive) {
            items.add(CatalogItem(key = "bellows", name = "Bellows and gimbal bearing", detail = "Torn bellows sink boats. Inspect them every season.", symbol = "arrow.up.and.down.and.sparkles", months = 24, difficulty = Difficulty.shop))
        }
        if (powertrain == Powertrain.inboard) {
            items.add(CatalogItem(key = "transmissionFluid", name = "Transmission fluid", detail = "Marine gear oil, usually each season.", symbol = "gearshape.2", hours = 100.0, months = 12, difficulty = Difficulty.moderate))
            items.add(CatalogItem(key = "alignment", name = "Shaft alignment and packing", detail = "Check the stuffing box drip and engine alignment.", symbol = "arrow.left.and.right", months = 24, isCore = false, difficulty = Difficulty.shop))
        }
        if (powertrain == Powertrain.jetDrive) {
            items.add(CatalogItem(key = "wearRing", name = "Wear ring and impeller", detail = "A worn ring costs top speed and holeshot.", symbol = "circle.dashed", hours = 100.0, months = 24, difficulty = Difficulty.shop))
        }
        return items
    }

    val boatCommon: List<CatalogItem> = listOf(
        CatalogItem(
            key = "anodes", name = "Anodes (zincs)", detail = "Sacrificial anodes protect the metal underwater. Replace at about half gone.",
            symbol = "hexagon", months = 12,
            gear = listOf(GearSuggestion(title = "Anode kit", query = "{make} anode kit"))
        ),
        CatalogItem(
            key = "safety", name = "Safety gear check", detail = "Life jackets, fire extinguisher, flare dates, horn and nav lights.",
            symbol = "lifepreserver", months = 12,
            gear = listOf(GearSuggestion(title = "Inflatable life jackets", query = "inflatable life jacket uscg approved"),
                   GearSuggestion(title = "Marine extinguisher", query = "marine fire extinguisher"))
        ),
        CatalogItem(
            key = "bilge", name = "Bilge pump and float switch", detail = "Test it before you need it.",
            symbol = "drop.circle", months = 12
        ),
        CatalogItem(key = "boatBattery", name = "Batteries", detail = "Clean terminals, check charge, and keep them on a maintainer in storage.", symbol = "battery.75", months = 12, isCore = false,
                    gear = listOf(GearSuggestion(title = "Marine battery charger", query = "onboard marine battery charger"))),
        CatalogItem(key = "bottom", name = "Bottom paint and hull", detail = "Boats kept in the water need fresh antifouling every year or two.", symbol = "paintbrush", months = 24, isCore = false, difficulty = Difficulty.shop),
        CatalogItem(key = "wax", name = "Wash and wax", detail = "Gelcoat oxidizes in the sun. Wax twice a season.", symbol = "sparkles", months = 6, isCore = false,
                    gear = listOf(GearSuggestion(title = "Marine wax", query = "marine gelcoat wax"))),
        CatalogItem(key = "generator", name = "Generator service", detail = "Oil, impeller and zinc about every 150 hours or once a season.", symbol = "bolt.circle", months = 12, auxHours = 150.0, isCore = false, difficulty = Difficulty.moderate),
    )

    val sailboatRig: List<CatalogItem> = listOf(
        CatalogItem(key = "rigging", name = "Standing rigging inspection", detail = "Look for cracked swages, broken strands and loose pins. Many surveyors suggest replacing wire at ten to fifteen years.", symbol = "triangle", months = 12, difficulty = Difficulty.moderate),
        CatalogItem(key = "sails", name = "Sails and running rigging", detail = "Check stitching, chafe and UV covers.", symbol = "sailboat", months = 12),
        CatalogItem(key = "winches", name = "Winch service", detail = "Strip, clean and grease each winch.", symbol = "gearshape", months = 12, isCore = false,
                    gear = listOf(GearSuggestion(title = "Winch service kit", query = "sailboat winch service kit"))),
    )

    val personalWatercraft: List<CatalogItem> = listOf(
        CatalogItem(key = "oil", name = "Oil and filter", detail = "About every 50 hours or each season.", symbol = "drop.fill", hours = 50.0, months = 12,
                    gear = listOf(GearSuggestion(title = "PWC oil change kit", query = "{make} pwc oil change kit"))),
        CatalogItem(key = "flush", name = "Freshwater flush", detail = "After every saltwater ride.", symbol = "drop", trigger = UsageEvent.saltwater, isCore = false),
        CatalogItem(key = "wearRing", name = "Wear ring and impeller", detail = "Check for nicks and wear.", symbol = "circle.dashed", hours = 100.0, months = 24, difficulty = Difficulty.shop),
        CatalogItem(key = "plugs", name = "Spark plugs", detail = "Every 100 hours or two seasons.", symbol = "bolt.fill", hours = 100.0, months = 24),
        CatalogItem(key = "winterize", name = "Winterize", detail = "Stabilize fuel, fog, drain the exhaust, and pull the battery.", symbol = "snowflake", months = 12,
                    gear = listOf(GearSuggestion(title = "Fuel stabilizer", query = "marine fuel stabilizer"))),
        CatalogItem(key = "safety", name = "Safety gear check", detail = "Life jackets, extinguisher and the kill switch lanyard.", symbol = "lifepreserver", months = 12),
    )

    // MARK: - Air

    fun aircraft(powertrain: Powertrain): List<CatalogItem> {
        val items = mutableListOf(
            CatalogItem(
                key = "annual", name = "Annual inspection", detail = "Required every 12 calendar months under 14 CFR 91.409.",
                symbol = "checkmark.seal", months = 12, calendarMonths = true, difficulty = Difficulty.shop, source = "14 CFR 91.409"
            ),
            CatalogItem(
                key = "elt", name = "ELT inspection", detail = "Required every 12 calendar months under 14 CFR 91.207(d). Check the battery expiration too.",
                symbol = "antenna.radiowaves.left.and.right", months = 12, calendarMonths = true, difficulty = Difficulty.shop, source = "14 CFR 91.207"
            ),
            CatalogItem(
                key = "transponder", name = "Transponder check", detail = "Every 24 calendar months under 14 CFR 91.413.",
                symbol = "dot.radiowaves.right", months = 24, calendarMonths = true, difficulty = Difficulty.shop, source = "14 CFR 91.413"
            ),
            CatalogItem(
                key = "pitotStatic", name = "Pitot-static and altimeter", detail = "Every 24 calendar months for IFR flight under 14 CFR 91.411.",
                symbol = "gauge.with.dots.needle.33percent", months = 24, calendarMonths = true, difficulty = Difficulty.shop, source = "14 CFR 91.411"
            ),
            CatalogItem(
                key = "registration", name = "Registration renewal", detail = "FAA aircraft registration runs seven years.",
                symbol = "doc.text", months = 84, source = "14 CFR 47.40"
            ),
            CatalogItem(
                key = "hundredHour", name = "100-hour inspection", detail = "Required when the aircraft is used for hire or flight instruction.",
                symbol = "clock.badge.checkmark", hours = 100.0, isCore = false, difficulty = Difficulty.shop, source = "14 CFR 91.409(b)"
            ),
            CatalogItem(
                key = "vor", name = "VOR check", detail = "Within the preceding 30 days for IFR under 14 CFR 91.171.",
                symbol = "location.north.line", months = 1, isCore = false, source = "14 CFR 91.171"
            ),
        )
        if (powertrain == Powertrain.piston) {
            items.add(1, CatalogItem(
                key = "oil", name = "Oil change", detail = "Commonly 50 hours with a full-flow filter, or every four months, whichever comes first.",
                symbol = "drop.fill", hours = 50.0, months = 4, difficulty = Difficulty.moderate, source = "Engine maker guidance"
            ))
            items.add(CatalogItem(key = "plugs", name = "Spark plug rotation", detail = "Clean, gap and rotate top to bottom.", symbol = "bolt.fill", hours = 100.0, isCore = false, difficulty = Difficulty.shop))
        }
        return items
    }

    // MARK: - Off road and around home

    val atv: List<CatalogItem> = listOf(
        CatalogItem(key = "oil", name = "Oil and filter", detail = "Dust and heat are hard on small engines. Every 100 hours, 1,000 miles or once a season.", symbol = "drop.fill", miles = 1_000.0, hours = 100.0, months = 12,
                    gear = listOf(GearSuggestion(title = "Oil change kit", query = "{vehicle} oil change kit"))),
        CatalogItem(key = "airFilter", name = "Air filter clean", detail = "After every dusty ride. A dirty filter is how ATV engines die.", symbol = "aqi.medium", miles = 250.0, hours = 25.0, months = 6, trigger = UsageEvent.dust,
                    gear = listOf(GearSuggestion(title = "Air filter", query = "{vehicle} air filter"))),
        CatalogItem(key = "cvt", name = "CVT belt inspection", detail = "Glazing or cracks mean replace it before it lets go on the trail.", symbol = "circle.dashed", miles = 1_000.0, hours = 50.0, months = 12, difficulty = Difficulty.moderate,
                    gear = listOf(GearSuggestion(title = "Spare drive belt", query = "{vehicle} drive belt"))),
        CatalogItem(key = "diffs", name = "Differential and gearcase fluid", detail = "Front and rear differentials, once a year for most.", symbol = "gearshape.2", miles = 2_000.0, hours = 100.0, months = 24, difficulty = Difficulty.moderate),
        CatalogItem(key = "grease", name = "Grease fittings", detail = "Suspension pivots and driveline.", symbol = "drop.triangle", miles = 250.0, hours = 25.0, months = 3, isCore = false,
                    gear = listOf(GearSuggestion(title = "Grease gun", query = "grease gun cordless"))),
        CatalogItem(key = "coolant", name = "Coolant", detail = "Every two years on liquid-cooled machines.", symbol = "thermometer.snowflake", months = 24, isCore = false),
    )

    val snowmobile: List<CatalogItem> = listOf(
        CatalogItem(key = "preseason", name = "Preseason check", detail = "Track, hyfax, carbides, belt and lights before the first ride.", symbol = "checklist", months = 12),
        CatalogItem(key = "chaincase", name = "Chaincase oil", detail = "Once a season.", symbol = "drop.halffull", months = 12),
        CatalogItem(key = "belt", name = "Drive belt", detail = "Carry a spare. Replace when glazed or narrow.", symbol = "circle.dashed", miles = 1_500.0, months = 12,
                    gear = listOf(GearSuggestion(title = "Spare drive belt", query = "{vehicle} drive belt"))),
        CatalogItem(key = "plugs", name = "Spark plugs", detail = "Once a season.", symbol = "bolt.fill", months = 12),
        CatalogItem(key = "storage", name = "Summer storage", detail = "Stabilize the fuel, fog the engine, and loosen the track.", symbol = "sun.max", months = 12,
                    gear = listOf(GearSuggestion(title = "Fuel stabilizer", query = "fuel stabilizer"))),
    )

    val tractor: List<CatalogItem> = listOf(
        CatalogItem(key = "oil", name = "Engine oil and filter", detail = "Most small engines call for 50 to 100 hours, or every season.", symbol = "drop.fill", hours = 50.0, months = 12,
                    gear = listOf(GearSuggestion(title = "Oil filter", query = "{vehicle} oil filter"))),
        CatalogItem(key = "airFilter", name = "Air filter", detail = "Clean often, replace yearly.", symbol = "aqi.medium", hours = 100.0, months = 12,
                    gear = listOf(GearSuggestion(title = "Air filter", query = "{vehicle} air filter"))),
        CatalogItem(key = "blades", name = "Sharpen blades", detail = "A sharp blade cuts grass cleanly instead of tearing it. About every 25 hours.", symbol = "scissors", hours = 25.0, months = 12,
                    gear = listOf(GearSuggestion(title = "Blade sharpener", query = "lawn mower blade sharpener"),
                           GearSuggestion(title = "Replacement blades", query = "{vehicle} mower blades"))),
        CatalogItem(key = "plugs", name = "Spark plug", detail = "Once a season.", symbol = "bolt.fill", hours = 100.0, months = 12),
        CatalogItem(key = "grease", name = "Grease fittings", detail = "Spindles and pivots.", symbol = "drop.triangle", hours = 25.0, months = 6, isCore = false),
        CatalogItem(key = "hydraulic", name = "Hydraulic and transmission fluid", detail = "Compact tractors usually every 300 to 400 hours.", symbol = "gearshape.2", hours = 300.0, months = 24, isCore = false, difficulty = Difficulty.moderate),
        CatalogItem(key = "storage", name = "Off-season storage", detail = "Stabilize or drain the fuel and keep the battery charged.", symbol = "snowflake", months = 12),
    )

    val electricMower: List<CatalogItem> = listOf(
        CatalogItem(key = "blades", name = "Sharpen blades", detail = "A sharp blade also stretches the battery.", symbol = "scissors", hours = 25.0, months = 12),
        CatalogItem(key = "deck", name = "Clean the deck", detail = "Caked grass costs runtime.", symbol = "sparkles", months = 3),
        CatalogItem(key = "storageCharge", name = "Storage charge", detail = "Store the battery partly charged somewhere cool and dry.", symbol = "battery.50", months = 12),
    )

    val ebike: List<CatalogItem> = listOf(
        CatalogItem(key = "brakes", name = "Brake pads", detail = "Check the pad thickness. E-bikes are heavy and fast, so pads go quicker.", symbol = "exclamationmark.octagon", miles = 500.0, months = 6,
                    gear = listOf(GearSuggestion(title = "Disc brake pads", query = "bike disc brake pads")), group = "Brakes"),
        CatalogItem(key = "brakeFluid", name = "Hydraulic brake fluid", detail = "Check the level, and bleed it if the lever feels soft. Cable brakes skip this.", symbol = "drop.halffull", months = 12, isCore = false, difficulty = Difficulty.moderate,
                    gear = listOf(GearSuggestion(title = "Brake bleed kit", query = "bike hydraulic brake bleed kit")), group = "Brakes"),
        CatalogItem(key = "chain", name = "Chain clean and lube", detail = "A clean chain shifts better and lasts longer. More often in the wet.", symbol = "link", miles = 200.0, months = 1,
                    gear = listOf(GearSuggestion(title = "Chain lube", query = "bike chain lube")), group = "Chain"),
        CatalogItem(key = "chainWear", name = "Check chain wear", detail = "A stretched chain wears out the cassette and chainrings. A checker tool takes seconds.", symbol = "ruler", miles = 500.0, months = 3,
                    gear = listOf(GearSuggestion(title = "Chain checker", query = "bike chain wear checker")), group = "Chain"),
        CatalogItem(key = "chainReplace", name = "New chain", detail = "Typically every 2,000 to 3,000 miles, sooner on an e-bike. Go by the wear check.", symbol = "link.badge.plus", miles = 2_500.0, isCore = false, difficulty = Difficulty.moderate,
                    gear = listOf(GearSuggestion(title = "Chain", query = "bike chain")), group = "Chain"),
        CatalogItem(key = "tires", name = "Tire pressure and wear", detail = "Low pressure costs range and invites flats.", symbol = "circle.circle", months = 1,
                    gear = listOf(GearSuggestion(title = "Floor pump with gauge", query = "bike floor pump with gauge")), group = "Tires"),
        CatalogItem(key = "battery", name = "E-bike battery care", detail = "Store around half charge in the cool and dry, and check the contacts.", symbol = "battery.75", months = 6, isCore = false, group = "Battery"),
        CatalogItem(key = "powerMeter", name = "Charge the power meter", detail = "Or swap its coin cell. A dead one drops out mid-ride.", symbol = "bolt.circle", months = 1, isCore = false, group = "Battery"),
        CatalogItem(key = "shifting", name = "Charge electronic shifting", detail = "Di2, AXS and the like. A flat battery leaves you in one gear.", symbol = "battery.100.bolt", months = 1, isCore = false, group = "Battery"),
        CatalogItem(key = "tune", name = "Tune-up and safety check", detail = "Gears, cables, bolts, spokes and bearings checked over, by you or a mechanic.", symbol = "wrench.adjustable", miles = 1_000.0, months = 12, difficulty = Difficulty.moderate, group = "Checkup"),
        CatalogItem(key = "firmware", name = "Update firmware", detail = "Motors, displays, shifting and power meters all get updates through their apps.", symbol = "arrow.down.circle", months = 6, isCore = false, group = "Checkup"),
        CatalogItem(key = "barTape", name = "Replace bar tape", detail = "Drop bars only. Worn tape gets slippery in the wet.", symbol = "hand.raised", months = 12, isCore = false,
                    gear = listOf(GearSuggestion(title = "Bar tape", query = "bike handlebar tape")), group = "Other"),
        CatalogItem(key = "bottomBracket", name = "Grease the bottom bracket", detail = "Creaks or grit at the cranks mean it's due.", symbol = "gearshape", miles = 3_000.0, months = 12, isCore = false, difficulty = Difficulty.moderate, group = "Other"),
    )

    val electricGolfCart: List<CatalogItem> = listOf(
        CatalogItem(key = "waterLevel", name = "Battery water (lead-acid)", detail = "Flooded lead-acid batteries need distilled water topped up monthly. Lithium packs never do, so switch this off if yours is lithium.", symbol = "drop", months = 1,
                    gear = listOf(GearSuggestion(title = "Battery watering system", query = "golf cart battery watering system"))),
        CatalogItem(key = "terminals", name = "Clean battery terminals", detail = "Corrosion steals range.", symbol = "minus.plus.batteryblock", months = 6),
        CatalogItem(key = "tires", name = "Tire pressure", detail = "Soft tires cost range and wear unevenly.", symbol = "circle.circle", months = 3),
        CatalogItem(key = "annual", name = "Annual service", detail = "Brakes, steering, suspension and charger checked over.", symbol = "wrench.adjustable", months = 12, difficulty = Difficulty.shop),
    )

    val gasGolfCart: List<CatalogItem> = listOf(
        CatalogItem(key = "oil", name = "Oil change", detail = "Every 100 hours or once a year.", symbol = "drop.fill", months = 12),
        CatalogItem(key = "airFilter", name = "Air filter", detail = "Once a year.", symbol = "aqi.medium", months = 12),
        CatalogItem(key = "tires", name = "Tire pressure", detail = "Check quarterly.", symbol = "circle.circle", months = 3),
        CatalogItem(key = "annual", name = "Annual service", detail = "Belt, brakes and steering checked over.", symbol = "wrench.adjustable", months = 12, difficulty = Difficulty.shop),
    )

    val generic: List<CatalogItem> = listOf(
        CatalogItem(key = "service", name = "General service", detail = "The yearly once-over.", symbol = "wrench.adjustable", months = 12),
        CatalogItem(key = "oil", name = "Oil change", detail = "If it has an engine, it has oil.", symbol = "drop.fill", months = 12),
    )


    // MARK: - Paperwork

    /** Renewals, kept off by default because the dates are personal. */
    fun paperwork(kind: VehicleKind, region: String? = defaultRegion()): List<CatalogItem> {
        val items = mutableListOf<CatalogItem>()
        if (kind != VehicleKind.aircraft && kind != VehicleKind.ebike) {
            items.add(CatalogItem(key = "registration", name = "Registration renewal", detail = "Set it to the month your registration expires.", symbol = "doc.text", months = 12, isCore = false))
        }
        if (kind != VehicleKind.ebike && kind != VehicleKind.trailer) {
            items.add(CatalogItem(key = "insurance", name = "Insurance renewal", detail = "A reminder to shop your rate before it renews.", symbol = "shield.lefthalf.filled", months = 12, isCore = false))
        }
        if (kind.hasNHTSARecords && kind != VehicleKind.trailer && kind != VehicleKind.camper) {
            val (name, detail) = when (region) {
                "GB" -> "MOT test" to "Due every year once a car is three years old."
                "IE" -> "NCT test" to "Due every two years from four years old, then yearly after ten."
                "CA" -> "Safety or emissions inspection" to "Only where your province requires it, often when the vehicle is sold."
                "AU", "NZ" -> "Roadworthy or WOF check" to "Only where your state requires it."
                "US", null -> "State inspection or emissions" to "Only where your state requires it."
                else -> "Roadworthiness inspection" to "Set it to your country's schedule."
            }
            items.add(CatalogItem(key = "inspection", name = name, detail = detail, symbol = "checkmark.seal", months = 12, isCore = false))
        }
        return items
    }
}
