package com.jackwallner.keyring.model

import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** When each job comes due. Ordinals match the iOS raw values: lower is more urgent. */
enum class DueStatus(val label: String) {
    OVERDUE("Overdue"), DUE_SOON("Due soon"), NO_RECORD("No record yet"), OK("Up to date")
}

data class DueInput(
    val intervalDistance: Double,
    val intervalMonths: Int,
    val lastDate: Instant?,
    val lastReading: Double?,
    val currentReading: Double,
    val dailyUse: Double,
    val meter: MeterUnit,
    /** FAA-style calendar months: due at the end of the month the interval lands in. */
    val calendarMonths: Boolean = false,
)

data class DueResult(
    val status: DueStatus,
    val dueDate: Instant?,
    val dueReading: Double?,
    val progress: Double,
    val dateIsEstimated: Boolean,
)

/** Pure due math, a line-for-line port of `DueEngine.swift`, so lists, reminders and the PDF never disagree. */
object DueEngine {
    const val SOON_WINDOW_DAYS = 30.0
    private const val DAY_SECONDS = 86_400.0

    private val okEmpty = DueResult(DueStatus.OK, null, null, 0.0, false)

    fun evaluate(input: DueInput, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): DueResult {
        val usesDistance = input.intervalDistance > 0 && input.meter.hasReading
        val usesTime = input.intervalMonths > 0
        if (!usesDistance && !usesTime) return okEmpty
        val knowsTime = usesTime && input.lastDate != null
        val knowsDistance = usesDistance && input.lastReading != null
        if (!knowsTime && !knowsDistance) return DueResult(DueStatus.NO_RECORD, null, null, 0.0, false)

        val candidates = mutableListOf<Pair<Instant, Boolean>>()
        var progress = 0.0
        var dueReading: Double? = null
        var overdue = false

        val last = input.lastDate
        if (knowsTime && last != null) {
            val due = timeDue(last, input, zone)
            candidates.add(due to false)
            val total = seconds(last, due)
            if (total > 0) progress = maxOf(progress, seconds(last, now) / total)
            if (!now.isBefore(due)) overdue = true
        }

        val lastReading = input.lastReading
        if (knowsDistance && lastReading != null) {
            val target = lastReading + input.intervalDistance
            dueReading = target
            val used = input.currentReading - lastReading
            progress = maxOf(progress, used / input.intervalDistance)
            if (input.currentReading >= target) {
                overdue = true
                candidates.add(now to true)
            } else if (input.dailyUse > 0) {
                val days = (target - input.currentReading) / input.dailyUse
                if (days.isFinite() && days < 365 * 30) candidates.add(plusSeconds(now, days * DAY_SECONDS) to true)
            }
        }

        val earliest = candidates.minByOrNull { it.first }
        val status = when {
            overdue -> DueStatus.OVERDUE
            earliest != null && seconds(now, earliest.first) <= SOON_WINDOW_DAYS * DAY_SECONDS -> DueStatus.DUE_SOON
            dueReading != null && input.currentReading >= dueReading - input.intervalDistance * 0.1 -> DueStatus.DUE_SOON
            else -> DueStatus.OK
        }
        return DueResult(status, earliest?.first, dueReading, maxOf(0.0, progress), earliest?.second ?: false)
    }

    /** A job brought due by an event: owed now if it has happened, owed by then if it's coming up. */
    fun triggered(event: Instant, now: Instant = Instant.now()): DueResult {
        val past = !event.isAfter(now)
        val status = when {
            past -> DueStatus.OVERDUE
            seconds(now, event) <= SOON_WINDOW_DAYS * DAY_SECONDS -> DueStatus.DUE_SOON
            else -> DueStatus.OK
        }
        return DueResult(status, event, null, if (past) 1.0 else 0.0, false)
    }

    /** The most urgent status and earliest date from several ways a job comes due. */
    fun combine(results: List<DueResult>): DueResult {
        var combined = results.firstOrNull() ?: return okEmpty
        for (result in results.drop(1)) {
            // "No record" only stands when nothing else knows better.
            if (combined.status == DueStatus.NO_RECORD || (result.status != DueStatus.NO_RECORD && result.status < combined.status)) {
                combined = combined.copy(status = result.status)
            }
            val date = result.dueDate
            if (date != null && date < (combined.dueDate ?: Instant.MAX)) {
                combined = combined.copy(dueDate = date, dateIsEstimated = result.dateIsEstimated)
            }
            combined = combined.copy(progress = maxOf(combined.progress, result.progress))
        }
        return combined
    }

    fun timeDue(last: Instant, input: DueInput, zone: ZoneId): Instant {
        val due = last.atZone(zone).plusMonths(input.intervalMonths.toLong())
        if (!input.calendarMonths) return due.toInstant()
        val monthEnd = due.toLocalDate().withDayOfMonth(1).plusMonths(1).atStartOfDay(zone)
        return monthEnd.toInstant().minusSeconds(1)
    }

    /** Use per day from the vehicle's history over the last year, needing two weeks of spread. */
    fun dailyUse(readings: List<Pair<Instant, Double>>, fallback: Double, now: Instant = Instant.now()): Double {
        val yearAgo = now.minus(365, ChronoUnit.DAYS)
        val recent = readings.filter { !it.first.isBefore(yearAgo) && it.second >= 0 }.sortedBy { it.first }
        val first = recent.firstOrNull() ?: return fallback
        val last = recent.last()
        val days = seconds(first.first, last.first) / DAY_SECONDS
        val delta = last.second - first.second
        if (days < 14 || delta <= 0) return fallback
        return delta / days
    }

    private fun seconds(from: Instant, to: Instant): Double = (to.toEpochMilli() - from.toEpochMilli()) / 1000.0

    private fun plusSeconds(instant: Instant, seconds: Double): Instant = instant.plusMillis((seconds * 1000).toLong())
}
