package com.jackwallner.keyring

import com.jackwallner.keyring.catalog.MaintenanceCatalog
import com.jackwallner.keyring.model.DueEngine
import com.jackwallner.keyring.model.DueInput
import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.MeterUnit
import com.jackwallner.keyring.model.VehicleKind
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** `DueEngineTests` from KeyringTests.swift, case for case. */
class DueEngineTest {
    private val now = Instant.ofEpochSecond(1_790_000_000)
    private val utc = ZoneOffset.UTC

    private fun input(distance: Double = 7_500.0, months: Int = 12, lastDaysAgo: Double? = 100.0, lastReading: Double? = 40_000.0,
                      current: Double = 43_000.0, pace: Double = 33.0, meter: MeterUnit = MeterUnit.miles) = DueInput(
        intervalDistance = distance, intervalMonths = months,
        lastDate = lastDaysAgo?.let { now.minusSeconds((it * 86_400).toLong()) }, lastReading = lastReading,
        currentReading = current, dailyUse = pace, meter = meter,
    )

    @Test fun distanceComesFirstWhenDrivingALot() {
        val result = DueEngine.evaluate(input(), now, utc)
        // 4,500 miles left at 33 a day is ~136 days, before the 12-month date.
        assertEquals(DueStatus.OK, result.status)
        assertTrue(result.dateIsEstimated)
        assertEquals(47_500.0, result.dueReading!!, 0.0)
        val days = (result.dueDate!!.epochSecond - now.epochSecond) / 86_400.0
        assertEquals(4_500 / 33.0, days, 1.0)
    }

    @Test fun calendarComesFirstWhenParked() {
        assertFalse(DueEngine.evaluate(input(pace = 1.0), now, utc).dateIsEstimated)
    }

    @Test fun overdueByDistance() {
        val result = DueEngine.evaluate(input(current = 48_000.0), now, utc)
        assertEquals(DueStatus.OVERDUE, result.status)
        assertTrue(result.progress > 1)
    }

    @Test fun overdueByTime() {
        assertEquals(DueStatus.OVERDUE, DueEngine.evaluate(input(lastDaysAgo = 400.0, current = 40_100.0, pace = 0.2), now, utc).status)
    }

    @Test fun dueSoonWithinThirtyDays() {
        assertEquals(DueStatus.DUE_SOON, DueEngine.evaluate(input(lastDaysAgo = 350.0, current = 40_100.0, pace = 0.2), now, utc).status)
    }

    @Test fun noRecordWhenNothingKnown() {
        assertEquals(DueStatus.NO_RECORD, DueEngine.evaluate(input(lastDaysAgo = null, lastReading = null), now, utc).status)
    }

    @Test fun timeOnlyJobOnHourMeterIgnoresDistanceWhenNoMeter() {
        val result = DueEngine.evaluate(input(distance = 100.0, months = 12, lastReading = null, meter = MeterUnit.none), now, utc)
        assertFalse(result.dateIsEstimated)
        assertNull(result.dueReading)
    }

    @Test fun faaCalendarMonthsRunToTheEndOfTheMonth() {
        fun day(y: Int, m: Int, d: Int) = LocalDate.of(y, m, d).atStartOfDay(utc).toInstant()
        val value = DueInput(0.0, 12, day(2026, 3, 3), null, 0.0, 0.0, MeterUnit.hours, calendarMonths = true)
        val result = DueEngine.evaluate(value, day(2027, 3, 20), utc)
        assertEquals(LocalDate.of(2027, 3, 31), result.dueDate!!.atZone(utc).toLocalDate())
        assertEquals(DueStatus.DUE_SOON, result.status)
        assertEquals(DueStatus.OVERDUE, DueEngine.evaluate(value, day(2027, 4, 1), utc).status)
        assertTrue(MaintenanceCatalog.usesCalendarMonths("annual", VehicleKind.aircraft))
        assertFalse(MaintenanceCatalog.usesCalendarMonths("annual", VehicleKind.golfCart))
    }

    @Test fun dailyUseNeedsTwoWeeksOfSpread() {
        val points = listOf(now.minusSeconds(5 * 86_400) to 100.0, now to 400.0)
        assertEquals(33.0, DueEngine.dailyUse(points, 33.0, now), 0.0)
        val longer = listOf(now.minusSeconds(30 * 86_400) to 100.0, now to 400.0)
        assertEquals(10.0, DueEngine.dailyUse(longer, 33.0, now), 0.01)
    }

    @Test fun eventTriggersAndCombineTakeTheMostUrgent() {
        val past = DueEngine.triggered(now.minusSeconds(86_400), now)
        assertEquals(DueStatus.OVERDUE, past.status)
        val soon = DueEngine.triggered(now.plusSeconds(10 * 86_400), now)
        assertEquals(DueStatus.DUE_SOON, soon.status)
        val noRecord = DueEngine.evaluate(input(lastDaysAgo = null, lastReading = null), now, utc)
        val combined = DueEngine.combine(listOf(noRecord, soon))
        assertEquals(DueStatus.DUE_SOON, combined.status)
        assertEquals(soon.dueDate, combined.dueDate)
    }
}
