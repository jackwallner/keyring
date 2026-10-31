package com.jackwallner.keyring

import com.jackwallner.keyring.data.GarageStore
import com.jackwallner.keyring.data.MemoryGarageFile
import com.jackwallner.keyring.data.NewVehicle
import com.jackwallner.keyring.data.ServiceDraft
import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.VehicleKind
import java.time.Instant
import java.time.temporal.ChronoUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The odometer is optional when a vehicle is added. Leaving it empty must not store a reading of zero
 * that the first real reading is then measured against (`NoOdometerSetupTests` in the iOS app).
 */
class NoOdometerSetupTest {
    private fun store() = GarageStore(MemoryGarageFile())
    private fun daysAgo(days: Long): Instant = Instant.now().minus(days, ChronoUnit.DAYS)
    private fun car(reading: Double = 0.0, lastDone: Map<String, Instant> = emptyMap()) =
        NewVehicle(kind = VehicleKind.car, make = "Honda", model = "Civic", reading = reading, lastDone = lastDone)

    @Test fun theFirstReadingMonthsLaterDoesNotInventAPace() {
        val store = store()
        val vehicle = store.addVehicle(car(), daysAgo(30))
        store.updateReading(store.vehicle(vehicle.id)!!, 52_000.0)
        val now = store.vehicle(vehicle.id)!!
        assertEquals(store.typicalDailyUse(now), store.dailyUse(now), 0.001)
    }

    @Test fun aJobAnsweredThisMonthIsNotOverdueOnceTheOdometerIsEntered() {
        val store = store()
        val vehicle = store.addVehicle(car(lastDone = mapOf("oil" to daysAgo(34))), daysAgo(20))
        store.updateReading(store.vehicle(vehicle.id)!!, 52_000.0)
        val oil = store.dues(store.vehicle(vehicle.id)!!).first { it.task.catalogKey == "oil" }
        assertEquals(DueStatus.OK, oil.result.status)
    }

    @Test fun aServiceLoggedWithoutAReadingIsNotOverdueOnceTheOdometerIsEntered() {
        val store = store()
        val vehicle = store.addVehicle(car(), daysAgo(30))
        val oil = store.tasks(vehicle).first { it.catalogKey == "oil" }
        store.log(ServiceDraft(date = daysAgo(7), taskIds = listOf(oil.id)), vehicle)
        store.updateReading(store.vehicle(vehicle.id)!!, 52_000.0)
        val due = store.dues(store.vehicle(vehicle.id)!!).first { it.task.catalogKey == "oil" }
        assertEquals(DueStatus.OK, due.result.status)
    }

    @Test fun anEnteredOdometerStillStartsThePaceAndTheBaseline() {
        val store = store()
        val vehicle = store.addVehicle(car(reading = 50_000.0, lastDone = mapOf("oil" to daysAgo(34))), daysAgo(20))
        store.updateReading(store.vehicle(vehicle.id)!!, 50_600.0)
        val now = store.vehicle(vehicle.id)!!
        assertEquals(30.0, store.dailyUse(now), 0.5)
        val oil = store.dues(now).first { it.task.catalogKey == "oil" }
        assertEquals(50_000.0, oil.lastReading!!, 0.0)
        assertTrue(oil.result.status == DueStatus.OK)
    }
}
