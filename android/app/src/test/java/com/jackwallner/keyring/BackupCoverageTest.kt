package com.jackwallner.keyring

import com.jackwallner.keyring.data.CSVExport
import com.jackwallner.keyring.data.FuelUnit
import com.jackwallner.keyring.data.GarageStore
import com.jackwallner.keyring.data.MemoryGarageFile
import com.jackwallner.keyring.data.NewVehicle
import com.jackwallner.keyring.data.ServiceDraft
import com.jackwallner.keyring.data.ServiceImport
import com.jackwallner.keyring.data.Vehicle
import com.jackwallner.keyring.model.EntryKind
import com.jackwallner.keyring.model.VehicleKind
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** `BackupCoverageTests` in the iOS app: the backup names the jobs each visit covered, and a restore restarts those and only those. */
class BackupCoverageTest {
    private val us = Locale.US
    private fun store() = GarageStore(MemoryGarageFile())
    private fun daysAgo(days: Long): Instant = Instant.now().minus(days, ChronoUnit.DAYS)

    private fun civic(store: GarageStore, reading: Double = 50_000.0) =
        store.addVehicle(NewVehicle(kind = VehicleKind.car, year = 2019, make = "Honda", model = "Civic", reading = reading))

    private fun task(store: GarageStore, car: Vehicle, key: String): String =
        store.tasks(store.vehicle(car.id)!!).first { it.catalogKey == key }.id

    /** `source`'s backup, restored into a new Civic in a new store. */
    private fun restored(source: GarageStore, car: Vehicle): Pair<GarageStore, Vehicle> {
        val csv = CSVExport.csv(source, listOf(source.vehicle(car.id)!!), unit = FuelUnit.GALLONS)
        val fresh = store()
        val target = civic(fresh, 50_300.0)
        val result = ServiceImport.parse(csv, us)
        fresh.importHistory(result.services + result.fillUps, target)
        return fresh to fresh.vehicle(target.id)!!
    }

    private fun due(back: Pair<GarageStore, Vehicle>, key: String) = back.first.dues(back.second).first { it.task.catalogKey == key }

    @Test fun aVisitThatCoveredThreeJobsRestartsAllThree() {
        val source = store()
        val car = civic(source)
        source.log(ServiceDraft(
            date = daysAgo(40), reading = 49_800.0,
            taskIds = listOf(task(source, car, "oil"), task(source, car, "rotate"), task(source, car, "cabinFilter")),
        ), source.vehicle(car.id)!!)
        val back = restored(source, car)
        for (key in listOf("oil", "rotate", "cabinFilter")) assertEquals("$key was done on that visit", 49_800.0, due(back, key).lastReading!!, 0.0)
    }

    @Test fun aVisitWithItsOwnTitleRestartsTheJobsItCovered() {
        val source = store()
        val car = civic(source)
        source.log(ServiceDraft(
            date = daysAgo(40), reading = 49_800.0, title = "Dealer 30k service",
            taskIds = listOf(task(source, car, "oil"), task(source, car, "rotate")),
        ), source.vehicle(car.id)!!)
        val back = restored(source, car)
        assertEquals("Dealer 30k service", back.first.entries(back.second).first().title)
        for (key in listOf("oil", "rotate")) assertEquals("$key was done on that visit", 49_800.0, due(back, key).lastReading!!, 0.0)
    }

    @Test fun aRecallOrRepairThatNamesBrakesDoesNotCountAsTheBrakeInspection() {
        val source = store()
        val car = civic(source)
        source.log(ServiceDraft(kind = EntryKind.recall, recallCampaign = "24V123000", title = "Recall: service brakes, hydraulic", date = daysAgo(30)), source.vehicle(car.id)!!)
        source.log(ServiceDraft(kind = EntryKind.repair, title = "Brake line replacement", reading = 49_900.0, date = daysAgo(20)), source.vehicle(car.id)!!)
        assertNull("nothing in the log covered the inspection", source.dues(source.vehicle(car.id)!!).first { it.task.catalogKey == "brakes" }.lastDate)
        assertNull("the restored log says the same", due(restored(source, car), "brakes").lastDate)
    }

    @Test fun anOldBackupWithoutAJobsColumnStillMatchesByTitle() {
        val file = """
            Vehicle,Year,Make,Model,Date,Odometer,Unit,Type,Work,Cost,Shop,DIY,Notes
            Civic,2019,Honda,Civic,2026-01-10,49800,mi,Maintenance,Oil and filter,59.99,,,
        """.trimIndent()
        val fresh = store()
        val car = civic(fresh, 50_300.0)
        fresh.importHistory(ServiceImport.parse(file, us).services, car)
        assertEquals(49_800.0, fresh.dues(fresh.vehicle(car.id)!!).first { it.task.catalogKey == "oil" }.lastReading!!, 0.0)
    }
}
