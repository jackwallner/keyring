package com.jackwallner.keyring.catalog

import com.jackwallner.keyring.data.Vehicle
import com.jackwallner.keyring.model.MeterUnit
import com.jackwallner.keyring.model.VehicleKind
import com.jackwallner.keyring.model.VehicleTrait
import java.net.URLEncoder
import java.time.LocalDate
import java.util.Locale

/** Percent-encodes one query value the way `URLComponents` does for spaces (`%20`, not `+`). */
fun queryValue(text: String): String = URLEncoder.encode(text, "UTF-8").replace("+", "%20")

/** Builds `base?name=value&...`, skipping nothing; values are encoded. */
fun withQuery(base: String, vararg items: Pair<String, String>): String =
    if (items.isEmpty()) base else base + "?" + items.joinToString("&") { "${it.first}=${queryValue(it.second)}" }

/**
 * Amazon search links for parts, tools and upgrades, ported from `AmazonLinks`.
 * The associate tag is empty until the Associates account is approved; links
 * are plain searches and the disclosure stays hidden until then.
 */
object AmazonLinks {
    const val ASSOCIATE_TAG = ""
    val isAffiliate: Boolean get() = ASSOCIATE_TAG.isNotEmpty()
    const val DISCLOSURE = "As an Amazon Associate, Vehicle Maintenance Log earns from qualifying purchases."

    /** The reader's own Amazon store, so prices and shipping are local. */
    fun host(region: String? = Locale.getDefault().country): String = when (region) {
        "CA" -> "www.amazon.ca"
        "GB", "IE" -> "www.amazon.co.uk"
        "AU", "NZ" -> "www.amazon.com.au"
        "DE", "AT", "CH" -> "www.amazon.de"
        "FR", "BE" -> "www.amazon.fr"
        "IT" -> "www.amazon.it"
        "ES" -> "www.amazon.es"
        "NL" -> "www.amazon.nl"
        "MX" -> "www.amazon.com.mx"
        "JP" -> "www.amazon.co.jp"
        "IN" -> "www.amazon.in"
        else -> "www.amazon.com"
    }

    fun search(query: String, region: String? = Locale.getDefault().country): String {
        val items = mutableListOf("k" to query)
        if (isAffiliate) items += "tag" to ASSOCIATE_TAG
        return withQuery("https://${host(region)}/s", *items.toTypedArray())
    }

    /** Fills `{vehicle}` and `{make}`; a vehicle with no make or model falls back to its kind. */
    fun resolve(template: String, vehicle: Vehicle): String {
        val full = vehicle.descriptor.ifEmpty { vehicle.kind.title.lowercase() }
        val make = vehicle.make?.takeIf { it.isNotEmpty() } ?: vehicle.kind.title.lowercase()
        return template.replace("{vehicle}", full).replace("{make}", make)
    }
}

/** Where to check what a vehicle is worth. The app never shows a third-party value as its own. */
data class ValueSource(val name: String, val detail: String, val url: String) {
    companion object {
        private val roadKinds = setOf(VehicleKind.car, VehicleKind.suv, VehicleKind.truck, VehicleKind.van)

        fun sources(vehicle: Vehicle, region: String? = Locale.getDefault().country, thisYear: Int = LocalDate.now().year): List<ValueSource> {
            val collector = collectorSources(vehicle, thisYear)
            val local = if (vehicle.kind in roadKinds) localCarSources(vehicle, region) else null
            return collector + (local ?: usSources(vehicle)) + listOfNotNull(ebaySold(vehicle, region))
        }

        /** Collector cars and bikes trade on condition, not book value. */
        private fun collectorSources(vehicle: Vehicle, thisYear: Int): List<ValueSource> {
            val road = vehicle.kind in roadKinds || vehicle.kind == VehicleKind.motorcycle
            val old = vehicle.year > 1885 && vehicle.year <= thisYear - 25
            if (!road || !(old || VehicleTrait.collector in vehicle.traits)) return emptyList()
            return listOf(ValueSource("Hagerty Valuation Tools", "Collector values by condition", "https://www.hagerty.com/valuation-tools"))
        }

        private fun localCarSources(vehicle: Vehicle, region: String?): List<ValueSource>? {
            val query = vehicle.makeAndModel
            return when (region) {
                "CA" -> listOf(
                    ValueSource("Canadian Black Book", "Trade-in and retail values", "https://www.canadianblackbook.com/"),
                    ValueSource("AutoTrader.ca", "Asking prices for similar cars",
                        if (query.isEmpty()) "https://www.autotrader.ca/cars/" else withQuery("https://www.autotrader.ca/cars/", "kwd" to query)),
                )
                "GB", "IE" -> listOf(
                    ValueSource("Auto Trader", "Free car valuation", "https://www.autotrader.co.uk/car-valuation"),
                    ValueSource("Parkers", "Price guide", "https://www.parkers.co.uk/car-valuation/"),
                )
                "AU", "NZ" -> listOf(
                    ValueSource("RedBook", "Car values", "https://www.redbook.com.au/"),
                    ValueSource("carsales", "Asking prices for similar cars", "https://www.carsales.com.au/"),
                )
                else -> null
            }
        }

        private fun ebaySold(vehicle: Vehicle, region: String?): ValueSource? {
            val query = listOfNotNull(vehicle.year.takeIf { it > 0 }?.toString(), vehicle.make, vehicle.model).filter { it.isNotEmpty() }.joinToString(" ")
            if (query.isEmpty()) return null
            val host = when (region) {
                "CA" -> "www.ebay.ca"
                "GB", "IE" -> "www.ebay.co.uk"
                "AU", "NZ" -> "www.ebay.com.au"
                "DE", "AT", "CH" -> "www.ebay.de"
                else -> "www.ebay.com"
            }
            val url = withQuery("https://$host/sch/i.html", "_nkw" to query, "LH_Sold" to "1", "LH_Complete" to "1")
            return ValueSource("eBay sold listings", "What similar ones sold for (sign in to eBay)", url)
        }

        private fun usSources(vehicle: Vehicle): List<ValueSource> {
            val make = slug(vehicle.make)
            val model = slug(vehicle.model)
            val year = vehicle.year.takeIf { it > 0 }?.toString()
            val mileage = if (vehicle.meter == MeterUnit.miles && vehicle.reading > 0) vehicle.reading.toLong() else null
            return when (vehicle.kind) {
                VehicleKind.car, VehicleKind.suv, VehicleKind.truck, VehicleKind.van -> {
                    var kbb = "https://www.kbb.com/"
                    if (make != null) kbb += "$make/"
                    if (make != null && model != null) kbb += "$model/"
                    if (make != null && model != null && year != null) kbb += "$year/"
                    val items = mutableListOf("intent" to "trade-in-sell")
                    if (mileage != null) items += "mileage" to mileage.toString()
                    val edmunds = if (make != null && model != null && year != null) "https://www.edmunds.com/$make/$model/$year/appraisal-value/"
                    else "https://www.edmunds.com/appraisal/"
                    listOf(
                        ValueSource("Kelley Blue Book", "Trade-in and private party values", withQuery(kbb, *items.toTypedArray())),
                        ValueSource("Edmunds", "True Market Value appraisal", edmunds),
                    )
                }
                VehicleKind.motorcycle, VehicleKind.scooter -> listOf(
                    ValueSource("Kelley Blue Book", "Motorcycle values", "https://www.kbb.com/motorcycles/"),
                    ValueSource("J.D. Power", "Motorcycle values", "https://www.jdpower.com/motorcycles"),
                )
                VehicleKind.rv, VehicleKind.camper -> listOf(ValueSource("J.D. Power", "RV and camper values", "https://www.jdpower.com/rvs"))
                VehicleKind.boat, VehicleKind.sailboat, VehicleKind.personalWatercraft ->
                    listOf(ValueSource("J.D. Power", "Boat and engine values", "https://www.jdpower.com/boats"))
                VehicleKind.aircraft -> listOf(
                    ValueSource("Aircraft Bluebook", "The aircraft industry's price guide", "https://www.aircraftbluebook.com/"),
                    ValueSource("Controller", "Listings for similar aircraft", withQuery("https://www.controller.com/listings/search", "keywords" to vehicle.makeAndModel)),
                )
                VehicleKind.atv, VehicleKind.snowmobile -> listOf(ValueSource("J.D. Power", "Powersports values", "https://www.jdpower.com/motorcycles"))
                else -> emptyList()
            }
        }

        fun slug(text: String?): String? {
            val trimmed = text?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            val lowered = trimmed.lowercase().replace("&", "and").split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }.joinToString("-")
            return lowered.ifEmpty { null }
        }
    }
}

@Suppress("EnumEntryName")
enum class ServiceGroup(val title: String) { shops("Shops near you"), mobile("Comes to you"), detailing("Detailing") }

/** A shop, mobile mechanic or detailer search. Map searches open the maps app around wherever the owner is. */
data class LocalService(val title: String, val detail: String, val symbol: String, val group: ServiceGroup, val url: String) {
    companion object {
        /** Google's universal Maps link: the Maps app when installed, the browser otherwise, searching near the reader. */
        fun maps(query: String): String = withQuery("https://www.google.com/maps/search/", "api" to "1", "query" to query)
    }
}

/** Ported from `Shared/Catalog/ServiceFinder.swift`. National booking sites are US only and road vehicles only. */
object ServiceFinder {
    data class Terms(val shop: String, val mobile: String?, val detail: String?)

    fun terms(kind: VehicleKind): Terms = when (kind) {
        VehicleKind.car, VehicleKind.suv, VehicleKind.van, VehicleKind.truck -> Terms("auto repair", "mobile mechanic", "mobile car detailing")
        VehicleKind.motorcycle, VehicleKind.scooter -> Terms("motorcycle repair", "mobile motorcycle mechanic", "motorcycle detailing")
        VehicleKind.rv, VehicleKind.camper -> Terms("RV repair", "mobile RV repair", "mobile RV detailing")
        VehicleKind.trailer -> Terms("trailer repair", "mobile trailer repair", null)
        VehicleKind.boat, VehicleKind.personalWatercraft, VehicleKind.sailboat -> Terms("marine mechanic", "mobile marine mechanic", "mobile boat detailing")
        VehicleKind.aircraft -> Terms("aircraft maintenance", null, "aircraft detailing")
        VehicleKind.atv, VehicleKind.snowmobile -> Terms("powersports repair", "mobile powersports repair", null)
        VehicleKind.tractor -> Terms("small engine repair", "mobile small engine repair", null)
        VehicleKind.ebike -> Terms("ebike repair", "mobile bike repair", null)
        VehicleKind.golfCart -> Terms("golf cart repair", "mobile golf cart repair", null)
        VehicleKind.other -> Terms("repair shop", null, null)
    }

    fun services(kind: VehicleKind, make: String?, us: Boolean): List<LocalService> {
        val terms = terms(kind)
        val road = kind.isRoad
        val list = mutableListOf(LocalService("Repair shops", "Independent shops nearby in Maps, with hours and reviews.", "wrench.and.screwdriver.fill", ServiceGroup.shops, LocalService.maps(terms.shop)))
        val brand = make?.trim()
        if (!brand.isNullOrEmpty() && (road || kind == VehicleKind.motorcycle || kind == VehicleKind.boat)) {
            list += LocalService("$brand dealer service", "Factory-trained techs and recall work, which is free at a dealer.", "building.2.fill", ServiceGroup.shops, LocalService.maps("$brand dealer service"))
        }
        if (road && us) {
            list += LocalService("RepairPal", "Certified shops that honor RepairPal's fair price estimate.", "checkmark.seal.fill", ServiceGroup.shops, "https://repairpal.com/auto-repair-near-me")
        }
        terms.mobile?.let {
            list += LocalService(if (road) "Mobile mechanics" else "Mobile repair", "Local mechanics who do the job in your driveway or at work.", "car.side.fill", ServiceGroup.mobile, LocalService.maps(it))
        }
        if (road && us) {
            list += LocalService("YourMechanic", "Book a mobile mechanic online with an upfront quote.", "calendar.badge.clock", ServiceGroup.mobile, "https://www.yourmechanic.com/")
            list += LocalService("Wrench", "Mobile repair, diagnostics and brakes in many US cities.", "calendar.badge.clock", ServiceGroup.mobile, "https://wrench.com/")
        }
        terms.detail?.let {
            list += LocalService(if (road) "Mobile car detailing" else "Detailing", "Detailers who wash, polish and clean the interior wherever it's parked.", "sparkles", ServiceGroup.detailing, LocalService.maps(it))
        }
        if (road) list += LocalService("Detail shops", "Shops for paint correction, ceramic coating and tint.", "drop.fill", ServiceGroup.detailing, LocalService.maps("auto detailing"))
        return list
    }
}
