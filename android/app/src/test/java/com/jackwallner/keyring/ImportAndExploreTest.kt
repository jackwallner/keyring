package com.jackwallner.keyring

import com.jackwallner.keyring.catalog.AmazonLinks
import com.jackwallner.keyring.catalog.Club
import com.jackwallner.keyring.catalog.ClubDirectory
import com.jackwallner.keyring.catalog.ServiceFinder
import com.jackwallner.keyring.catalog.ServiceGroup
import com.jackwallner.keyring.catalog.Upgrade
import com.jackwallner.keyring.catalog.UpgradeCatalog
import com.jackwallner.keyring.catalog.UpgradeCategory
import com.jackwallner.keyring.catalog.ValueSource
import com.jackwallner.keyring.data.CSVExport
import com.jackwallner.keyring.data.FuelUnit
import com.jackwallner.keyring.data.GarageStore
import com.jackwallner.keyring.data.MemoryGarageFile
import com.jackwallner.keyring.data.NewVehicle
import com.jackwallner.keyring.data.Recall
import com.jackwallner.keyring.data.ServiceDraft
import com.jackwallner.keyring.data.ServiceImport
import com.jackwallner.keyring.data.VINRecallCheck
import com.jackwallner.keyring.model.EntryKind
import com.jackwallner.keyring.model.MeterUnit
import com.jackwallner.keyring.model.Powertrain
import com.jackwallner.keyring.model.VehicleKind
import java.time.ZoneId
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** `ImportTests`, `VINRecallCheckTests` and the explore catalog tests from KeyringTests.swift. */
class ImportAndExploreTest {
    private val us = Locale.US
    private fun store() = GarageStore(MemoryGarageFile())

    // MARK: - Import

    @Test fun fuellyStyleSplitsFillUpsFromServices() {
        val fuel = """
            car_name,model,mpg,odometer,miles,gallons,price,city_percentage,fuelup_date,date_added,tags,notes,missed_fuelup,partial_fuelup
            Tacoma,Tacoma,19.2,41200,288,15,3.49,50,2024-03-02,2024-03-02 10:00,,,0,0
            Tacoma,Tacoma,18.7,41510,310,16.6,3.59,50,2024-03-15,2024-03-15 09:00,,,0,0
        """.trimIndent()
        val result = ServiceImport.parse(fuel, us)
        assertEquals(ServiceImport.Source.FUELLY, result.source)
        assertEquals(2, result.fillUps.size)
        assertTrue(result.services.isEmpty())
        assertEquals(41_510.0, result.fillUps.last().reading!!, 0.0)
    }

    @Test fun stackedSectionsSkipExpensesAndReadEuropeanFigures() {
        val file = """
            ##Refuelling
            Date;Odometer;Liters;Total
            12/03/2024;45.120;40,2;71,50
            ##Service
            Date;Odometer;Service;Total cost;Place;Notes
            01/02/2024;44.900;Oil change, tire rotation;89,90;Midas;synthetic
            05/01/2024;44.100;Brake pads;240,00;;
            ##Expense
            Date;Odometer;Expense;Total
            06/01/2024;44.200;Insurance;600,00
        """.trimIndent()
        val result = ServiceImport.parse(file, Locale.UK)
        assertEquals(1, result.fillUps.size)
        assertEquals(2, result.services.size)
        assertEquals(1, result.skippedExpenses)
        val oil = result.services.last()
        assertEquals(44_900.0, oil.reading!!, 0.0)
        assertEquals(89.90, oil.cost, 0.001)
        assertEquals("Midas", oil.shop)
        // Day first: 1 February, not January 2.
        assertEquals(2, oil.date.atZone(ZoneId.systemDefault()).monthValue)
        assertEquals(listOf("rotate", "oil"), ServiceImport.catalogKeys(oil.work))
    }

    @Test fun ownExportRoundTrips() {
        val file = """
            Vehicle,Year,Make,Model,Date,Odometer,Unit,Type,Work,Covered jobs,Cost,Shop,DIY,Notes,Logged by
            Tacoma,2019,Toyota,Tacoma,2025-06-01,52000,mi,Repair,Water pump,,420.00,Dave's,,"Leaking, replaced",Dana
        """.trimIndent()
        val row = ServiceImport.parse(file, us).services[0]
        assertEquals(EntryKind.repair, row.kind)
        assertEquals(MeterUnit.miles, row.unit)
        assertEquals("Leaking, replaced", row.notes)
        assertEquals("Dana", row.loggedBy)
        assertEquals("Toyota", row.make)
    }

    @Test fun specificJobsWinOverEngineOil() {
        assertEquals(listOf("gearOil", "diffs"), ServiceImport.catalogKeys("Lower unit gear oil"))
        assertEquals(listOf("transmission", "transmissionFluid", "hydraulic"), ServiceImport.catalogKeys("Transmission oil"))
        assertEquals(emptyList<String>(), ServiceImport.catalogKeys("Fixed oil leak"))
        assertEquals(listOf("oil"), ServiceImport.catalogKeys("LOF"))
    }

    @Test fun numbers() {
        assertEquals(1_234.5, ServiceImport.number("$1,234.50")!!, 0.0)
        assertEquals(1_234.5, ServiceImport.number("1.234,50 €")!!, 0.0)
        assertEquals(45_000.0, ServiceImport.number("45,000")!!, 0.0)
        assertEquals(12.5, ServiceImport.number("12,5")!!, 0.0)
        assertNull(ServiceImport.number("n/a"))
    }

    @Test fun extraColumnsLandInNotesAndSameDayJobsAtDifferentPricesStay() {
        val file = """
            Date,Odometer,Work,Cost,Part #,Oil weight
            2024-03-02,41200,Brake pads,180,HB453G,
            2024-03-02,41200,Brake pads,160,HB454F,
            2024-04-10,42100,Oil change,60,,5W-30
        """.trimIndent()
        val result = ServiceImport.parse(file, us)
        assertEquals(listOf("Part #", "Oil weight"), result.foldedHeaders)
        assertEquals("Part #: HB453G", result.services.first().notes)
        assertEquals("Oil weight: 5W-30", result.services.last().notes)
        val store = store()
        val car = store.addVehicle(NewVehicle(kind = VehicleKind.car, make = "Mazda", model = "3", year = 2014, reading = 40_000.0))
        assertEquals(3, store.importHistory(result.services, car).added)
        assertEquals(3, store.importHistory(result.services, store.vehicle(car.id)!!).duplicates)
    }

    @Test fun importingTwiceAddsNothingAndRestartsTheSchedule() {
        val store = store()
        val vehicle = store.addVehicle(NewVehicle(reading = 30_000.0))
        val rows = ServiceImport.parse("Date,Odometer,Service,Cost\n2025-01-10,28000,Oil change,59.99", us).services
        val first = store.importHistory(rows, vehicle)
        assertEquals(1, first.added)
        assertEquals(1, first.jobsUpdated)
        assertEquals(1, store.importHistory(rows, store.vehicle(vehicle.id)!!).duplicates)
        assertEquals(28_000.0, store.dues(store.vehicle(vehicle.id)!!).first { it.task.catalogKey == "oil" }.lastReading!!, 0.0)
    }

    @Test fun fuellyFillUpsArriveWithGallonsAndPrice() {
        val store = store()
        val truck = store.addVehicle(NewVehicle(kind = VehicleKind.truck, powertrain = Powertrain.gasoline, meter = MeterUnit.miles, make = "Toyota", model = "Tacoma", reading = 41_000.0))
        val fuel = """
            car_name,model,mpg,odometer,miles,gallons,price,city_percentage,fuelup_date,date_added,tags,notes,missed_fuelup,partial_fuelup
            Tacoma,Tacoma,19.2,41200,288,15,3.49,50,2024-03-02,2024-03-02 10:00,,,0,0
            Tacoma,Tacoma,18.7,41510,310,16.6,3.59,50,2024-03-15,2024-03-15 09:00,,,0,1
        """.trimIndent()
        val rows = ServiceImport.parse(fuel, us).fillUps
        assertEquals(3.49, rows.first().unitPrice!!, 0.0)
        assertEquals(FuelUnit.GALLONS, rows.first().volumeUnit)
        assertTrue(rows.last().partial)
        assertEquals(2, store.importHistory(rows, truck).fillUps)
        val fills = store.entries(store.vehicle(truck.id)!!).filter { it.kind == EntryKind.fuel }
        assertEquals(2, fills.size)
        val first = fills.last()
        assertEquals(52.35, first.cost, 0.001)
        assertEquals(15.0, FuelUnit.GALLONS.fromLiters(first.fuelVolume), 0.0001)
        assertEquals(2, store.importHistory(rows, store.vehicle(truck.id)!!).duplicates)
        assertEquals(41_510.0, store.vehicle(truck.id)!!.reading, 0.0)
    }

    @Test fun ownExportKeepsFillUps() {
        val store = store()
        val car = store.addVehicle(NewVehicle(kind = VehicleKind.car, make = "Honda", model = "Civic", reading = 50_000.0))
        store.log(ServiceDraft(kind = EntryKind.fuel, reading = 50_300.0, cost = 38.42,
            fuelVolume = FuelUnit.GALLONS.toLiters(10.5), fuelUnitPrice = FuelUnit.GALLONS.toPerLiter(3.659)), car)
        val csv = CSVExport.csv(store, listOf(store.vehicle(car.id)!!), unit = FuelUnit.GALLONS)
        val rows = ServiceImport.parse(csv, us).fillUps
        assertEquals(1, rows.size)
        assertEquals(EntryKind.fuel, rows[0].kind)
        assertEquals(3.659, rows[0].unitPrice!!, 0.0)
        assertEquals(38.42, rows[0].cost, 0.001)
    }

    // MARK: - VIN check

    private fun recall(campaign: String) = Recall(campaign, "FUEL SYSTEM", "", "", "", null, false, false)

    @Test fun campaignKeysMatchAcrossForms() {
        assertEquals("25V455", VINRecallCheck.key("25V455000"))
        assertEquals("25V455", VINRecallCheck.key("25v-455"))
        assertEquals("26V1230", VINRecallCheck.key("26V1230"))
    }

    @Test fun onlyOpenAndNewerRecallsShow() {
        val listed = listOf(recall("25V455000"), recall("24V100000"), recall("23V010000"))
        val json = """{"state":"ok","vin":"1FM5K8LC8MGC14943","count":2,"recalls":[{"maker":"25S75","nhtsa":"25V455","status":"Recall Incomplete","summary":"IT IS POSSIBLE"},{"maker":"26S14","nhtsa":"26V117","status":"Recall Incomplete, remedy not yet available","summary":"THE REAR CAMERA"}]}"""
        val check = VINRecallCheck.parse(json, "1fm5k8lc8mgc14943", listed)!!
        assertTrue(check.covered)
        assertEquals(listOf("25V455000"), listed.filter(check::shows).map { it.campaign })
        val extra = check.unlisted(listed)
        assertEquals(listOf("26V117"), extra.map { it.campaign })
        assertEquals("The rear camera", extra.first().summary)
        assertTrue(check.shows(recall("26V900000")))
        assertEquals(check.encode(), VINRecallCheck.decode(check.encode())!!.encode())
    }

    @Test fun otherVINAndNoDataResults() {
        assertNull(VINRecallCheck.parse("""{"state":"ok","vin":"1HGCM82633A004352","count":0,"recalls":[]}""", "1FM5K8LC8MGC14943", emptyList()))
        val none = VINRecallCheck.parse("""{"state":"none"}""", "1FM5K8LC8MGC14943", listOf(recall("25V455000")))
        assertEquals(false, none?.covered)
        assertEquals(1, listOf(recall("25V455000")).count { none!!.shows(it) })
        val clear = VINRecallCheck.parse("""{"state":"ok","count":0,"recalls":[]}""", "1FM5K8LC8MGC14943", listOf(recall("25V455000")))
        assertEquals(0, listOf(recall("25V455000")).count { clear!!.shows(it) })
        assertTrue(VINRecallCheck.pageScript("1fm5k8lc8mgc14943").contains("const vin = \"1FM5K8LC8MGC14943\""))
        assertTrue(VINRecallCheck.pageScript("x").contains("window.KeyringRecalls.postMessage"))
    }

    // MARK: - Explore

    @Test fun clubsResolveForCommonVehicles() {
        val tacoma = ClubDirectory.clubs(VehicleKind.truck, "Toyota", "Tacoma")
        assertEquals("Tacoma World", tacoma.first().name)
        assertTrue(ClubDirectory.clubs(VehicleKind.aircraft, "Cessna", "172").any { it.name == "AOPA" })
        assertTrue(ClubDirectory.clubs(VehicleKind.car, "Mercedes-Benz", null).any { it.name == "MBWorld" })
        for (kind in VehicleKind.entries) assertFalse("$kind has no clubs", ClubDirectory.byKind(kind).isEmpty())
    }

    @Test fun upgradesForEveryKind() {
        for (kind in VehicleKind.entries) assertFalse("$kind has no upgrades", UpgradeCatalog.upgrades(kind, kind.defaultPowertrain).isEmpty())
        fun titles(kind: VehicleKind, powertrain: Powertrain) = UpgradeCatalog.upgrades(kind, powertrain).map { it.title }.toSet()
        assertEquals(setOf(UpgradeCategory.performance, UpgradeCategory.handling, UpgradeCategory.detailing),
            UpgradeCatalog.upgrades(VehicleKind.car, Powertrain.gasoline).map { it.category }.toSet())
        assertTrue(titles(VehicleKind.car, Powertrain.gasoline).containsAll(listOf("Cold air intake", "Lowering springs", "Performance tires", "Clay bar kit")))
        assertFalse(titles(VehicleKind.car, Powertrain.electric).contains("Cold air intake"))
        assertFalse(titles(VehicleKind.car, Powertrain.electric).contains("Brake pads and rotors"))
        assertTrue(titles(VehicleKind.car, Powertrain.electric).contains("Shocks and struts"))
        assertTrue(titles(VehicleKind.truck, Powertrain.gasoline).containsAll(listOf("Leveling kit", "All-terrain tires")))
    }

    @Test fun serviceNearbyFitsTheVehicle() {
        val truck = ServiceFinder.services(VehicleKind.truck, "Toyota", true)
        assertEquals(setOf(ServiceGroup.shops, ServiceGroup.mobile, ServiceGroup.detailing), truck.map { it.group }.toSet())
        assertTrue(truck.any { it.title == "Toyota dealer service" })
        // Google's universal Maps link instead of Apple Maps.
        assertEquals("https://www.google.com/maps/search/?api=1&query=mobile%20mechanic", truck.first { it.title == "Mobile mechanics" }.url)
        assertFalse(ServiceFinder.services(VehicleKind.truck, "Toyota", false).any { it.title == "YourMechanic" })
        val boat = ServiceFinder.services(VehicleKind.boat, null, true)
        assertTrue(boat.any { it.url.contains("marine%20mechanic") })
        assertFalse(boat.any { it.title == "Wrench" })
        for (kind in VehicleKind.entries) assertFalse("$kind has no services", ServiceFinder.services(kind, null, true).isEmpty())
    }

    @Test fun valueLinksCarryTheVehicle() {
        assertEquals("mercedes-benz", ValueSource.slug("Mercedes-Benz"))
        assertEquals("f-150", ValueSource.slug("F-150"))
        assertNull(ValueSource.slug("  "))
        val store = store()
        val car = store.addVehicle(NewVehicle(kind = VehicleKind.car, meter = MeterUnit.kilometers, year = 2019, make = "Honda", model = "Civic"))
        val canada = ValueSource.sources(car, "CA").map { it.name }
        assertEquals("Canadian Black Book", canada.first())
        assertFalse(canada.contains("Kelley Blue Book"))
        assertTrue(ValueSource.sources(car, "CA").last().url.startsWith("https://www.ebay.ca/"))
        assertEquals("Kelley Blue Book", ValueSource.sources(car, "US").first().name)
        val truck = store.addVehicle(NewVehicle(kind = VehicleKind.truck, meter = MeterUnit.miles, year = 2018, make = "Ford", model = "F-150"))
        val urls = ValueSource.sources(truck, "US").associate { it.name to it.url }
        assertEquals("https://www.edmunds.com/ford/f-150/2018/appraisal-value/", urls["Edmunds"])
        assertEquals("https://www.kbb.com/ford/f-150/2018/?intent=trade-in-sell", urls["Kelley Blue Book"])
        val bare = store.addVehicle(NewVehicle(kind = VehicleKind.car, make = "Ford", model = ""))
        assertEquals("https://www.edmunds.com/appraisal/", ValueSource.sources(bare, "US").associate { it.name to it.url }["Edmunds"])
        val classic = store.addVehicle(NewVehicle(kind = VehicleKind.car, year = 1967, make = "Ford", model = "Mustang"))
        assertEquals("Hagerty Valuation Tools", ValueSource.sources(classic, "US", 2026).first().name)
    }

    @Test fun amazonLinks() {
        val url = AmazonLinks.search("2019 Toyota Tacoma oil filter", "US")
        assertTrue(url.startsWith("https://www.amazon.com/s?"))
        assertTrue(AmazonLinks.search("wipers", "CA").startsWith("https://www.amazon.ca/"))
        assertTrue(url.contains("k=2019%20Toyota%20Tacoma%20oil%20filter"))
        assertFalse(AmazonLinks.isAffiliate)
        val store = store()
        val tacoma = store.addVehicle(NewVehicle(kind = VehicleKind.truck, year = 2019, make = "Toyota", model = "Tacoma"))
        assertEquals("2019 Toyota Tacoma oil filter (Toyota)", AmazonLinks.resolve("{vehicle} oil filter ({make})", tacoma))
        val bare = store.addVehicle(NewVehicle(kind = VehicleKind.boat))
        assertEquals("boat cover", AmazonLinks.resolve("{vehicle} cover", bare))
    }

    // MARK: - Parity with the Swift literals

    private val swift: JSONObject by lazy {
        JSONObject(javaClass.classLoader!!.getResource("explore_literals_swift.json")!!.readText())
    }

    private fun clubsJson(array: JSONArray) = (0 until array.length()).map { array.getJSONObject(it) }
        .map { Club(it.getString("name"), it.getString("detail"), com.jackwallner.keyring.catalog.ClubKind.valueOf(it.getString("kind")), it.getString("url")) }

    @Test fun clubsMatchTheSwiftLiterals() {
        val models = swift.getJSONObject("models")
        assertEquals(models.length(), ClubDirectory.models.size)
        for (key in models.keys()) assertEquals(key, clubsJson(models.getJSONArray(key)), ClubDirectory.models[key])
        val makes = swift.getJSONObject("makes")
        assertEquals(makes.length(), ClubDirectory.makes.size)
        for (key in makes.keys()) assertEquals(key, clubsJson(makes.getJSONArray(key)), ClubDirectory.makes[key])
        val byKind = swift.getJSONObject("byKind")
        assertEquals(VehicleKind.entries.size, byKind.length())
        for (kind in VehicleKind.entries) assertEquals(kind.name, clubsJson(byKind.getJSONArray(kind.name)), ClubDirectory.byKind(kind))
    }

    @Test fun upgradesMatchTheSwiftLiterals() {
        val lists = swift.getJSONObject("upgrades")
        val kotlin = mapOf(
            "performance" to UpgradeCatalog.performance, "performanceTires" to listOf(UpgradeCatalog.performanceTires),
            "allTerrainTires" to listOf(UpgradeCatalog.allTerrainTires), "handling" to UpgradeCatalog.handling,
            "carHandling" to UpgradeCatalog.carHandling, "levelingKit" to listOf(UpgradeCatalog.levelingKit),
            "detailing" to UpgradeCatalog.detailing, "motorcycle" to UpgradeCatalog.motorcycle, "rv" to UpgradeCatalog.rv,
            "trailer" to UpgradeCatalog.trailer, "boat" to UpgradeCatalog.boat, "aircraft" to UpgradeCatalog.aircraft,
            "powersports" to UpgradeCatalog.powersports, "tractor" to UpgradeCatalog.tractor, "ebike" to UpgradeCatalog.ebike,
            "golfCart" to UpgradeCatalog.golfCart, "generic" to UpgradeCatalog.generic,
        )
        assertEquals(lists.keys().asSequence().toSet(), kotlin.keys)
        var count = 0
        for ((name, items) in kotlin) {
            val array = lists.getJSONArray(name)
            val expected = (0 until array.length()).map { array.getJSONObject(it) }.map {
                Upgrade(it.getString("title"), it.getString("why"), it.getString("symbol"), UpgradeCategory.valueOf(it.getString("category")), it.getString("query"))
            }
            assertEquals(name, expected, items)
            count += expected.size
        }
        assertNotNull(count.takeIf { it == 61 })
    }
}
