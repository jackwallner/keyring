package com.jackwallner.keyring

import com.jackwallner.keyring.data.CSVExport
import com.jackwallner.keyring.data.CostInsights
import com.jackwallner.keyring.data.DueCopy
import com.jackwallner.keyring.data.GarageCodec
import com.jackwallner.keyring.data.GarageStore
import com.jackwallner.keyring.data.MemoryGarageFile
import com.jackwallner.keyring.data.NewVehicle
import com.jackwallner.keyring.data.ServiceDraft
import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.EntryKind
import com.jackwallner.keyring.model.MeterUnit
import com.jackwallner.keyring.model.Powertrain
import com.jackwallner.keyring.model.ProFeature
import com.jackwallner.keyring.model.UsageEvent
import com.jackwallner.keyring.model.VehicleKind
import com.jackwallner.keyring.model.VehicleTrait
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** `GarageStoreTests` and friends from KeyringTests.swift, against the JSON store. */
class GarageStoreTest {
    private val file = MemoryGarageFile()
    private fun store() = GarageStore(file)

    @Test fun addingAVehicleBuildsItsSchedule() {
        val store = store()
        val vehicle = store.addVehicle(NewVehicle(kind = VehicleKind.truck, powertrain = Powertrain.gasoline, meter = MeterUnit.miles, year = 2019,
            make = "Toyota", model = "Tacoma", reading = 40_000.0, lastDone = mapOf("oil" to Instant.now().minusSeconds(10 * 86_400))))
        assertTrue(store.enabledTasks(vehicle).isNotEmpty())
        val oil = store.dues(vehicle).first { it.task.catalogKey == "oil" }
        assertEquals(40_000.0, oil.lastReading!!, 0.0)
        assertNotEquals(DueStatus.NO_RECORD, oil.result.status)
        assertEquals(1, store.activeVehicles.size)
        // Core jobs only: optional ones wait in the catalog.
        val keys = store.enabledTasks(vehicle).mapNotNull { it.catalogKey }.toSet()
        assertEquals(vehicle.catalogItems.filter { it.isCore }.map { it.key }.toSet(), keys)
        assertTrue(store.availableCatalogItems(vehicle).none { it.key in keys })
    }

    @Test fun loggingRestartsTheCountdown() {
        val store = store()
        val vehicle = store.addVehicle(NewVehicle(kind = VehicleKind.car, make = "Honda", model = "Civic", reading = 50_000.0))
        val oil = store.enabledTasks(vehicle).first { it.catalogKey == "oil" }
        assertEquals(DueStatus.NO_RECORD, store.dues(vehicle).first { it.task.catalogKey == "oil" }.result.status)
        val entry = store.log(ServiceDraft(reading = 50_200.0, taskIds = listOf(oil.id), cost = 59.99), vehicle)
        assertEquals("Oil and filter", entry.title)
        val updated = store.vehicle(vehicle.id)!!
        assertEquals(50_200.0, updated.reading, 0.0)
        val due = store.dues(updated).first { it.task.catalogKey == "oil" }
        assertEquals(DueStatus.OK, due.result.status)
        assertEquals(57_700.0, due.result.dueReading!!, 0.0)
    }

    @Test fun loggingWithoutAReadingUsesTodaysMeter() {
        val store = store()
        val vehicle = store.addVehicle(NewVehicle(kind = VehicleKind.car, make = "Honda", model = "Civic", reading = 50_000.0))
        val oil = store.enabledTasks(vehicle).first { it.catalogKey == "oil" }
        store.log(ServiceDraft(date = Instant.now().minusSeconds(400L * 86_400), reading = 30_000.0, taskIds = listOf(oil.id)), vehicle)
        assertEquals(DueStatus.OVERDUE, store.dues(store.vehicle(vehicle.id)!!).first { it.task.catalogKey == "oil" }.result.status)
        store.log(ServiceDraft(taskIds = listOf(oil.id)), store.vehicle(vehicle.id)!!)
        val due = store.dues(store.vehicle(vehicle.id)!!).first { it.task.catalogKey == "oil" }
        assertEquals(50_000.0, due.lastReading!!, 0.0)
        assertEquals(DueStatus.OK, due.result.status)
    }

    @Test fun repairsAndRecallFixesAreKeptApart() {
        val store = store()
        val vehicle = store.addVehicle(NewVehicle(kind = VehicleKind.car, year = 2019, make = "Honda", model = "Civic", reading = 50_000.0))
        val repair = store.log(ServiceDraft(kind = EntryKind.repair, cost = 640.0), vehicle)
        assertEquals(EntryKind.repair, repair.kind)
        assertEquals("Repair", repair.title)
        val oil = store.enabledTasks(vehicle).first { it.catalogKey == "oil" }
        store.log(ServiceDraft(taskIds = listOf(oil.id), cost = 90.0), store.vehicle(vehicle.id)!!)
        store.log(ServiceDraft(kind = EntryKind.recall, recallCampaign = "24V001000", title = "Recall: air bags"), store.vehicle(vehicle.id)!!)
        assertEquals(730.0, CostInsights.summary(store, store.vehicle(vehicle.id)!!).upkeep, 0.0)
        assertTrue(CSVExport.csv(store, listOf(store.vehicle(vehicle.id)!!)).contains(",Recall,Recall: air bags,"))
    }

    @Test fun csvExportEscapesAndBlocksFormulas() {
        assertEquals("\"a,b\"", CSVExport.escape("a,b"))
        assertEquals("'=SUM(A1)", CSVExport.escape("=SUM(A1)"))
        assertEquals("\"say \"\"hi\"\"\"", CSVExport.escape("say \"hi\""))
        val store = store()
        val vehicle = store.addVehicle(NewVehicle(kind = VehicleKind.car, make = "Ford", model = "F-150", reading = 1_000.0))
        store.log(ServiceDraft(title = "Brakes, front", cost = 300.0), vehicle)
        val csv = CSVExport.csv(store, listOf(vehicle))
        assertTrue(csv.contains("\"Brakes, front\""))
        assertTrue(csv.contains("300.00"))
        assertEquals(CSVExport.header.joinToString(","), csv.lineSequence().first())
    }

    @Test fun titlesNameTheJobs() {
        val store = store()
        val vehicle = store.addVehicle(NewVehicle(kind = VehicleKind.car, make = "Honda", model = "Civic", reading = 50_000.0))
        val tasks = store.enabledTasks(vehicle)
        assertEquals("Service", store.title(emptyList(), vehicle))
        assertEquals("Oil and filter and tire rotation", store.title(tasks.take(2).map { it.id }, vehicle))
        assertEquals("Oil and filter and 2 more", store.title(tasks.take(3).map { it.id }, vehicle))
    }

    @Test fun eventsBringTheirJobsDue() {
        val store = store()
        val vehicle = store.addVehicle(NewVehicle(kind = VehicleKind.car, make = "Mazda", model = "Miata", reading = 20_000.0, traits = setOf(VehicleTrait.track)))
        val prep = store.enabledTasks(vehicle).first { it.catalogKey == "trackPrep" }
        assertEquals(UsageEvent.trackDay, prep.trigger)
        store.log(ServiceDraft(kind = EntryKind.event, event = UsageEvent.trackDay, date = Instant.now().plusSeconds(5 * 86_400)), vehicle)
        val due = store.dues(store.vehicle(vehicle.id)!!).first { it.task.id == prep.id }
        assertEquals(DueStatus.DUE_SOON, due.result.status)
        assertTrue(DueCopy.dueLine(due).startsWith("Due before the track day"))
    }

    @Test fun suspiciousJumpCatchesAnExtraDigit() {
        val store = store()
        val vehicle = store.addVehicle(NewVehicle(kind = VehicleKind.car, make = "Honda", model = "Civic", reading = 50_000.0))
        assertTrue(store.isSuspiciousJump(500_000.0, vehicle))
        assertFalse(store.isSuspiciousJump(50_400.0, vehicle))
        store.updateReading(vehicle, 50_400.0)
        assertEquals(50_400.0, store.vehicle(vehicle.id)!!.reading, 0.0)
        assertEquals(2, store.readings(vehicle).size)
    }

    @Test fun theLogSurvivesARelaunch() {
        val store = store()
        val vehicle = store.addVehicle(NewVehicle(kind = VehicleKind.boat, powertrain = Powertrain.sterndrive, meter = MeterUnit.hours,
            make = "Sea Ray", model = "SPX 190", reading = 212.0, traits = emptySet()))
        store.log(ServiceDraft(kind = EntryKind.fuel, reading = 214.0, cost = 80.0, fuelVolume = 60.0, fuelUnitPrice = 1.3), vehicle)
        val reopened = GarageStore(MemoryGarageFile(file.text))
        val encoded = GarageCodec.encode(store.data)
        assertEquals(encoded, GarageCodec.encode(reopened.data))
        assertEquals(encoded, GarageCodec.encode(GarageCodec.decode(encoded)))
        assertEquals(store.data.entries.single().fuelVolume, reopened.data.entries.single().fuelVolume, 0.0)
        // A broken file opens empty instead of crashing.
        assertTrue(GarageCodec.decode("{not json").vehicles.isEmpty())
    }

    @Test fun freeTierAllowsTwoActiveVehicles() {
        assertTrue(ProFeature.canAddVehicle(0, isPro = false))
        assertTrue(ProFeature.canAddVehicle(1, isPro = false))
        assertFalse(ProFeature.canAddVehicle(2, isPro = false))
        assertTrue(ProFeature.canAddVehicle(9, isPro = true))
        val store = store()
        val a = store.addVehicle(NewVehicle(kind = VehicleKind.car, model = "A"))
        store.addVehicle(NewVehicle(kind = VehicleKind.car, model = "B"))
        assertFalse(ProFeature.canAddVehicle(store.activeVehicles.size, isPro = false))
        // Retired vehicles don't count toward the free limit.
        store.retire(a)
        assertTrue(ProFeature.canAddVehicle(store.activeVehicles.size, isPro = false))
    }

    @Test fun demoSeedCoversEveryCardKind() {
        val store = store()
        DemoSeed.seed(store)
        assertEquals(listOf("The Tacoma", "Rebel", "Lake boat", "N734CP", "Sam's RAV4"), store.activeVehicles.map { it.displayName })
        val statuses = store.activeVehicles.flatMap { store.dues(it) }.map { it.result.status }.toSet()
        assertTrue(statuses.containsAll(listOf(DueStatus.OK, DueStatus.DUE_SOON)))
        assertTrue(store.entries(store.activeVehicles.first()).any { it.kind == EntryKind.fuel })
        assertTrue(store.activeVehicles.all { v -> store.dues(v).isNotEmpty() })
    }
}
