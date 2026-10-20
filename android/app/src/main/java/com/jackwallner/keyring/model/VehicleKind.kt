package com.jackwallner.keyring.model

/**
 * Every kind of thing a family keeps running. Entry names equal the iOS raw
 * values, so stored data and the catalog read the same on both platforms.
 */
@Suppress("EnumEntryName")
enum class VehicleKind(val title: String) {
    car("Car"), truck("Truck"), suv("SUV"), van("Van"), motorcycle("Motorcycle"), scooter("Scooter"),
    rv("Motorhome"), camper("Camper"), trailer("Trailer"),
    boat("Boat"), sailboat("Sailboat"), personalWatercraft("Personal watercraft"),
    aircraft("Aircraft"),
    atv("ATV / UTV"), snowmobile("Snowmobile"), tractor("Tractor / Mower"),
    ebike("Bike / E-bike"), golfCart("Golf Cart"),
    other("Other");

    val raw: String get() = name

    val defaultMeter: MeterUnit
        get() = when (this) {
            boat, sailboat, personalWatercraft, aircraft, tractor -> MeterUnit.hours
            camper, trailer -> MeterUnit.miles
            golfCart -> MeterUnit.none
            else -> MeterUnit.miles
        }

    val defaultPowertrain: Powertrain
        get() = when (this) {
            ebike, golfCart -> Powertrain.electric
            camper, trailer, sailboat -> Powertrain.none
            boat -> Powertrain.outboard
            aircraft -> Powertrain.piston
            else -> Powertrain.gasoline
        }

    val powertrainChoices: List<Powertrain>
        get() = when (this) {
            car, suv, van -> listOf(Powertrain.gasoline, Powertrain.hybrid, Powertrain.plugInHybrid, Powertrain.electric, Powertrain.diesel)
            truck -> listOf(Powertrain.gasoline, Powertrain.diesel, Powertrain.hybrid, Powertrain.electric)
            motorcycle, scooter -> listOf(Powertrain.gasoline, Powertrain.electric)
            rv -> listOf(Powertrain.gasoline, Powertrain.diesel)
            camper, trailer -> listOf(Powertrain.none)
            boat -> listOf(Powertrain.outboard, Powertrain.inboard, Powertrain.sterndrive, Powertrain.jetDrive, Powertrain.electric)
            sailboat -> listOf(Powertrain.none, Powertrain.outboard, Powertrain.inboard)
            personalWatercraft -> listOf(Powertrain.jetDrive)
            aircraft -> listOf(Powertrain.piston, Powertrain.turbine)
            atv, snowmobile -> listOf(Powertrain.gasoline, Powertrain.electric)
            tractor -> listOf(Powertrain.gasoline, Powertrain.diesel, Powertrain.electric)
            ebike -> listOf(Powertrain.electric, Powertrain.none)
            golfCart -> listOf(Powertrain.electric, Powertrain.gasoline)
            other -> Powertrain.entries
        }

    /** Typical use per day in the vehicle's own meter, until the owner's real pace is known. */
    val typicalDailyUse: Double
        get() = when (this) {
            car, suv, van -> 33.0
            truck -> 35.0
            motorcycle -> 10.0
            scooter -> 8.0
            rv -> 14.0
            camper, trailer -> 8.0
            boat, sailboat -> 0.15
            personalWatercraft -> 0.1
            aircraft -> 0.25
            atv -> 3.0
            snowmobile -> 4.0
            tractor -> 0.15
            ebike -> 6.0
            golfCart -> 0.0
            other -> 10.0
        }

    /** Road-registered kinds NHTSA covers for recalls and VIN decoding. */
    val hasNHTSARecords: Boolean
        get() = when (this) {
            car, truck, suv, van, motorcycle, scooter, rv, camper, trailer -> true
            else -> false
        }

    val identifierLabel: String
        get() = when (this) {
            boat, sailboat, personalWatercraft -> "Hull ID (HIN)"
            aircraft, ebike, golfCart, tractor -> "Serial number"
            else -> "VIN"
        }

    val registrationLabel: String
        get() = when (this) {
            aircraft -> "Tail number"
            boat, sailboat, personalWatercraft -> "Registration number"
            else -> "Plate"
        }

    val isRoad: Boolean get() = this == car || this == suv || this == van || this == truck

    companion object {
        fun fromRaw(raw: String?): VehicleKind = entries.firstOrNull { it.name == raw } ?: other

        /** Groupings for the kind picker, so nineteen choices read as four. */
        val pickerSections: List<Pair<String, List<VehicleKind>>> = listOf(
            "On the road" to listOf(car, suv, truck, van, motorcycle, scooter),
            "Camping and towing" to listOf(rv, camper, trailer),
            "On the water and in the air" to listOf(boat, sailboat, personalWatercraft, aircraft),
            "Off road and around home" to listOf(atv, snowmobile, tractor, ebike, golfCart, other),
        )
    }
}

@Suppress("EnumEntryName")
enum class MeterUnit(val title: String, val short: String) {
    miles("Miles", "mi"), kilometers("Kilometers", "km"), hours("Engine hours", "hrs"), none("No meter", "");

    val hasReading: Boolean get() = this != none

    val meterName: String
        get() = when (this) {
            miles, kilometers -> "Odometer"
            hours -> "Hour meter"
            none -> "Meter"
        }

    /** Choices for "How much is it used?", in this unit a year. */
    val yearlyUseChoices: List<Double>
        get() = when (this) {
            miles -> listOf(3_000.0, 7_500.0, 12_000.0, 18_000.0)
            kilometers -> listOf(5_000.0, 12_000.0, 20_000.0, 30_000.0)
            hours -> listOf(25.0, 50.0, 100.0, 200.0)
            none -> emptyList()
        }

    /** Room for an honest long trip before a new reading looks like a typo. */
    val typoSlack: Double
        get() = when (this) {
            miles -> 1_500.0
            kilometers -> 2_500.0
            hours -> 60.0
            none -> 0.0
        }

    fun convert(value: Double, to: MeterUnit): Double? = when {
        this == to -> value
        this == miles && to == kilometers -> value * 1.609344
        this == kilometers && to == miles -> value / 1.609344
        else -> null
    }

    /** Catalog distances are in miles. Kilometers convert and round to a figure a person would say. */
    fun fromCatalogMiles(miles: Double): Double {
        if (this != kilometers) return miles
        val km = miles * 1.609344
        val step = if (km >= 10_000) 1_000.0 else if (km >= 1_000) 500.0 else 50.0
        return swiftRound(km / step) * step
    }

    companion object {
        fun fromRaw(raw: String?): MeterUnit? = entries.firstOrNull { it.name == raw }
    }
}

@Suppress("EnumEntryName")
enum class Powertrain(val title: String) {
    gasoline("Gas"), diesel("Diesel"), hybrid("Hybrid"), plugInHybrid("Plug-in hybrid"), electric("Electric"),
    outboard("Outboard"), inboard("Inboard"), sterndrive("Sterndrive"), jetDrive("Jet drive"),
    piston("Piston"), turbine("Turbine"),
    none("No engine");

    val burnsFuel: Boolean get() = this != electric && this != none

    companion object {
        fun fromRaw(raw: String?): Powertrain? = entries.firstOrNull { it.name == raw }
    }
}

/** What a logged visit was. Kept apart so the real cost of owning something shows. */
@Suppress("EnumEntryName")
enum class EntryKind(val title: String) {
    service("Maintenance"), repair("Repair"), recall("Recall"), fuel("Fill-up"), mod("Mod"), event("Event");

    /** Counted in what it costs to keep running. */
    val isUpkeep: Boolean get() = this == service || this == repair || this == recall

    companion object {
        fun fromRaw(raw: String?): EntryKind = entries.firstOrNull { it.name == raw } ?: service
    }
}

@Suppress("EnumEntryName")
enum class VehicleTrait(val title: String, val detail: String) {
    fourByFour("4x4 or transfer case", "Front and rear diffs, transfer case, driveline grease"),
    track("Track days", "Brake fluid, pads and torque checks around every event"),
    collector("Collector, driven little", "Fluids and tires by age, a monthly drive, battery tender");

    companion object {
        fun choices(kind: VehicleKind): List<VehicleTrait> = when (kind) {
            VehicleKind.car, VehicleKind.van -> listOf(track, collector)
            VehicleKind.truck, VehicleKind.suv -> listOf(fourByFour, track, collector)
            VehicleKind.motorcycle -> listOf(track, collector)
            else -> emptyList()
        }
    }
}

@Suppress("EnumEntryName")
enum class FinalDrive(val title: String) { chain("Chain"), belt("Belt"), shaft("Shaft") }

@Suppress("EnumEntryName")
enum class UsageEvent(val title: String, val dueRule: String) {
    trackDay("Track day", "Every track day"),
    waterCrossing("Water crossing", "After a water crossing"),
    dust("Dusty ride", "After a dusty ride"),
    saltwater("Saltwater run", "After a saltwater run");

    companion object {
        fun fromRaw(raw: String?): UsageEvent? = entries.firstOrNull { it.name == raw }

        fun choices(kind: VehicleKind): List<UsageEvent> = when (kind) {
            VehicleKind.car, VehicleKind.van, VehicleKind.motorcycle -> listOf(trackDay, waterCrossing, dust)
            VehicleKind.truck, VehicleKind.suv, VehicleKind.atv -> listOf(waterCrossing, dust, trackDay)
            VehicleKind.boat, VehicleKind.sailboat, VehicleKind.personalWatercraft -> listOf(saltwater)
            VehicleKind.snowmobile, VehicleKind.scooter -> listOf(dust)
            else -> listOf(waterCrossing, dust)
        }
    }
}

/** A vehicle's own color, like a key tag. */
@Suppress("EnumEntryName")
enum class VehicleTint(val hex: Long, val title: String) {
    racingGreen(0x1F4D3A, "Racing green"), navy(0x1E3A5F, "Navy"), oxblood(0x6B1E24, "Oxblood"),
    graphite(0x2E3136, "Graphite"), marine(0x0F5E66, "Marine"), sky(0x3B76A8, "Sky"), plum(0x4A2C4F, "Plum"),
    olive(0x565D31, "Olive"), orange(0xC2551A, "Safety orange"), sand(0xB69E76, "Sand"),
    silver(0x8C939A, "Silver"), cream(0xE6DCC4, "Cream"), white(0xFFFFFF, "White");

    val isLight: Boolean get() = this == cream || this == sand || this == white

    companion object {
        fun fromRaw(raw: String?): VehicleTint? = entries.firstOrNull { it.name == raw }

        fun defaultTint(kind: VehicleKind): VehicleTint = when (kind) {
            VehicleKind.car -> navy
            VehicleKind.suv -> racingGreen
            VehicleKind.truck -> graphite
            VehicleKind.van -> sky
            VehicleKind.motorcycle, VehicleKind.scooter -> oxblood
            VehicleKind.rv, VehicleKind.camper -> sand
            VehicleKind.trailer -> silver
            VehicleKind.boat, VehicleKind.personalWatercraft -> marine
            VehicleKind.sailboat -> navy
            VehicleKind.aircraft -> sky
            VehicleKind.atv, VehicleKind.snowmobile -> orange
            VehicleKind.tractor -> olive
            VehicleKind.ebike, VehicleKind.golfCart -> plum
            VehicleKind.other -> graphite
        }
    }
}

/** Swift's `rounded()`: half away from zero, unlike Kotlin's banker's `roundToInt` on .5 edge cases. */
fun swiftRound(value: Double): Double = if (value < 0) -Math.round(-value).toDouble() else Math.floor(value + 0.5)
