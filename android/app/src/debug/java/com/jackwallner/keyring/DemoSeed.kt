package com.jackwallner.keyring

import com.jackwallner.keyring.data.GarageStore
import com.jackwallner.keyring.data.NewVehicle
import com.jackwallner.keyring.data.ServiceDraft
import com.jackwallner.keyring.data.ValuationKind
import com.jackwallner.keyring.data.Vehicle
import com.jackwallner.keyring.model.EntryKind
import com.jackwallner.keyring.model.MeterUnit
import com.jackwallner.keyring.model.Powertrain
import com.jackwallner.keyring.model.VehicleKind
import com.jackwallner.keyring.model.VehicleTint
import java.time.Instant

/**
 * A believable family garage for screenshots and tests, ported from
 * `DemoSeed.swift`: a truck, a hybrid, a motorcycle, a boat and a plane, each
 * with a couple of years of history. Debug builds only.
 */
object DemoSeed {
    private data class Visit(val daysAgo: Double, val keys: List<String>, val title: String, val cost: Double, val shop: String, val diy: Boolean)

    fun seed(store: GarageStore, now: Instant = Instant.now()) {
        if (store.data.vehicles.isNotEmpty()) return
        fun ago(days: Double): Instant = now.minusMillis((days * 86_400_000).toLong())

        val truck = store.addVehicle(NewVehicle(kind = VehicleKind.truck, powertrain = Powertrain.gasoline, meter = MeterUnit.miles, year = 2019,
            make = "Toyota", model = "Tacoma", trim = "TRD Off-Road", nickname = "The Tacoma", vin = "3TMCZ5AN2KM198431", plate = "CHX4120",
            reading = 48_210.0, tint = VehicleTint.racingGreen), ago(700.0))
        history(store, truck, now, start = 24_400.0, visits = listOf(
            Visit(680.0, listOf("oil", "rotate"), "Oil change and rotation", 89.95, "Lithia Toyota", false),
            Visit(520.0, listOf("oil"), "Oil change", 0.0, "", true),
            Visit(430.0, listOf("brakes"), "Front brake pads", 312.40, "Les Schwab", false),
            Visit(340.0, listOf("oil", "rotate", "cabinFilter"), "", 74.10, "", true),
            Visit(250.0, listOf("airFilter"), "", 28.99, "", true),
            Visit(160.0, listOf("oil", "rotate"), "", 94.50, "Lithia Toyota", false),
            Visit(45.0, listOf("battery"), "Battery test", 0.0, "Les Schwab", false),
        ))
        val fills = listOf(
            Triple(66.0, 46_000.0, 15.902 to 3.599), Triple(57.0, 46_310.0, 16.204 to 3.629), Triple(48.0, 46_605.0, 15.418 to 3.659),
            Triple(33.0, 47_120.0, 9.874 to 3.579), Triple(24.0, 47_430.0, 16.031 to 3.549), Triple(14.0, 47_760.0, 17.226 to 3.589),
            Triple(4.0, 48_090.0, 16.583 to 3.659),
        )
        for ((daysAgo, reading, fill) in fills) {
            val (gallons, price) = fill
            store.log(ServiceDraft(kind = EntryKind.fuel, date = ago(daysAgo), reading = reading, cost = Math.round(gallons * price * 100) / 100.0,
                shop = "Costco", fuelVolume = gallons * 3.785411784, fuelUnitPrice = price / 3.785411784), store.vehicle(truck.id)!!, now = now)
        }
        store.vehicle(truck.id)?.let { store.updateVehicle(it.copy(reading = 48_210.0, readingDate = now)) }

        val rav = store.addVehicle(NewVehicle(kind = VehicleKind.suv, powertrain = Powertrain.hybrid, meter = MeterUnit.miles, year = 2021,
            make = "Toyota", model = "RAV4", trim = "XLE Hybrid", nickname = "Sam's RAV4", vin = "2T3RWRFV4MW118204", plate = "CDK7781",
            reading = 31_402.0, tint = VehicleTint.sky), ago(600.0))
        history(store, rav, now, start = 9_200.0, visits = listOf(
            Visit(560.0, listOf("oil", "rotate"), "", 0.0, "Lithia Toyota", false),
            Visit(380.0, listOf("oil", "rotate"), "", 68.20, "Lithia Toyota", false),
            Visit(130.0, listOf("oil", "rotate", "cabinFilter"), "", 112.85, "Lithia Toyota", false),
            Visit(12.0, listOf("wipers"), "New wiper blades", 41.98, "", true),
        ))

        val bike = store.addVehicle(NewVehicle(kind = VehicleKind.motorcycle, powertrain = Powertrain.gasoline, meter = MeterUnit.miles, year = 2020,
            make = "Honda", model = "Rebel 500", nickname = "Rebel", reading = 6_118.0, tint = VehicleTint.oxblood), ago(500.0))
        history(store, bike, now, start = 3_100.0, visits = listOf(
            Visit(200.0, listOf("oil"), "Spring oil change", 0.0, "", true),
            Visit(90.0, listOf("chain"), "", 0.0, "", true),
            Visit(20.0, listOf("chain", "tires"), "", 18.99, "", true),
        ))

        val boat = store.addVehicle(NewVehicle(kind = VehicleKind.boat, powertrain = Powertrain.sterndrive, meter = MeterUnit.hours, year = 2016,
            make = "Sea Ray", model = "SPX 190", nickname = "Lake boat", plate = "WN 4471 RS", reading = 212.0, tint = VehicleTint.marine), ago(420.0))
        history(store, boat, now, start = 151.0, visits = listOf(
            Visit(345.0, listOf("winterize"), "Winterized", 389.00, "Clackamas Marine", false),
            Visit(230.0, listOf("impeller", "oil"), "Spring commissioning", 612.75, "Clackamas Marine", false),
        ))

        val plane = store.addVehicle(NewVehicle(kind = VehicleKind.aircraft, powertrain = Powertrain.piston, meter = MeterUnit.hours, year = 1978,
            make = "Cessna", model = "172N", nickname = "N734CP", plate = "N734CP", reading = 3_874.6, tint = VehicleTint.cream), ago(400.0))
        history(store, plane, now, start = 3_790.0, visits = listOf(
            Visit(330.0, listOf("annual", "elt"), "Annual inspection", 2_840.00, "Pearson Field Aviation", false),
            Visit(70.0, listOf("oil"), "", 164.20, "", true),
        ))

        // What the Tacoma is worth over time, and its title kept with it.
        store.vehicle(truck.id)?.let { tacoma ->
            store.addValuation(34_500.0, "KBB private party", ValuationKind.estimate, tacoma, ago(300.0))
            store.addValuation(33_200.0, "CarMax", ValuationKind.offer, tacoma, ago(120.0))
            store.addValuation(32_800.0, "KBB private party", ValuationKind.estimate, tacoma, ago(10.0))
            store.addDocument("Title", SAMPLE_PDF.toByteArray(Charsets.US_ASCII), tacoma, ago(650.0))
            store.addDocument("Window sticker", SAMPLE_PDF.toByteArray(Charsets.US_ASCII), tacoma, ago(640.0))
        }

        // The garage leads with one of each kind, so the first screen shows the range.
        listOf(truck, bike, boat, plane, rav).forEachIndexed { index, v -> store.vehicle(v.id)?.let { store.updateVehicle(it.copy(sortIndex = index)) } }
    }

    private fun history(store: GarageStore, added: Vehicle, now: Instant, start: Double, visits: List<Visit>) {
        val current = added.reading
        // The reading saved when the vehicle was added is the one it had then.
        store.replaceAll(store.data.copy(readings = store.data.readings.map { if (it.vehicleId == added.id) it.copy(value = start) else it }))
        val oldest = visits.maxOf { it.daysAgo }.coerceAtLeast(1.0)
        for (visit in visits) {
            val vehicle = store.vehicle(added.id) ?: return
            val date = now.minusMillis((visit.daysAgo * 86_400_000).toLong())
            val reading = if (vehicle.meter.hasReading) minOf(current, start + (current - start) * (1 - visit.daysAgo / oldest)) else null
            val ids = visit.keys.mapNotNull { key ->
                store.tasks(vehicle).firstOrNull { it.catalogKey == key }?.let { task ->
                    if (!task.isEnabled) store.addCatalogItems(listOfNotNull(vehicle.catalogItem(key)), vehicle)
                    task.id
                } ?: vehicle.catalogItem(key)?.let { item ->
                    store.addCatalogItems(listOf(item), vehicle)
                    store.tasks(vehicle).firstOrNull { it.catalogKey == key }?.id
                }
            }
            val rounded = reading?.let { Math.floor(it / 10 + 0.5) * 10 }
            store.log(ServiceDraft(date = date, reading = rounded, taskIds = ids, title = visit.title, cost = visit.cost,
                shop = visit.shop, isDIY = visit.diy), vehicle, now = now)
        }
        store.vehicle(added.id)?.let { store.updateVehicle(it.copy(reading = current, readingDate = now)) }
    }

    /** A one-page blank PDF, enough for a document row to open. */
    const val SAMPLE_PDF = "%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n" +
        "3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n"

    /** A small Fuelly-style export for the import screen in screenshots and tests. */
    const val SAMPLE_CSV = "Date,Odometer,Service,Cost,Shop\n2023-04-12,38110,Oil change,64.99,Jiffy Lube\n" +
        "2023-09-30,41020,Tire rotation,25.00,Les Schwab\n2024-02-18,43900,Brake pads,289.50,Les Schwab\n2024-06-02,45210,Insurance,600.00,\n"
}
