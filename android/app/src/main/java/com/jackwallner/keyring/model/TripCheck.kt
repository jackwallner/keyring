package com.jackwallner.keyring.model

import com.jackwallner.keyring.data.TaskDue
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Before a long trip: what comes due on the way, by distance covered and days away. Ported from `TripCheckView.owed`. */
object TripCheck {
    /** Jobs owed now, due by date before the return, or due by a reading the trip will pass. */
    fun owed(dues: List<TaskDue>, distance: Double, days: Double, current: Double, now: Instant = Instant.now()): List<TaskDue> {
        val back = now.plusMillis((maxOf(0.0, days) * 86_400_000).toLong())
        return dues.filter { due ->
            if (!due.hasInterval && due.pendingEvent == null) return@filter false
            when (due.result.status) {
                DueStatus.OVERDUE -> return@filter true
                DueStatus.NO_RECORD -> return@filter false
                else -> Unit
            }
            val date = due.result.dueDate
            if (date != null && date <= back) return@filter true
            val reading = due.result.dueReading
            reading != null && !due.usesAuxMeter && distance > 0 && reading <= current + distance
        }
    }
}

/** Puts a vehicle away for the season, or brings it back out. */
object Storage {
    /** Catalog jobs worth doing before it goes away. */
    val prepKeys = setOf("winterize", "storage", "storageCharge", "boatBattery")

    /** Mid-April for something put away in the fall, otherwise three months out. */
    fun defaultReturn(today: LocalDate = LocalDate.now()): LocalDate {
        val month = today.monthValue
        if (month >= 9 || month <= 2) return LocalDate.of(today.year + if (month >= 9) 1 else 0, 4, 15)
        return today.plusMonths(3)
    }

    fun startOfDay(date: LocalDate, zone: ZoneId = ZoneId.systemDefault()): Instant = date.atStartOfDay(zone).toInstant()
}
