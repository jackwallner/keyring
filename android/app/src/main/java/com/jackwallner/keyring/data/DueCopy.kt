package com.jackwallner.keyring.data

import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.Format
import java.time.Instant

/** The words under each job and on each key tag, ported from `TaskDue.dueLine` and the garage card. */
object DueCopy {
    fun dueLine(due: TaskDue, now: Instant = Instant.now(), notingPace: Boolean = true): String {
        val result = due.result
        val trigger = due.task.trigger
        val pending = due.pendingEvent
        if (pending != null && trigger != null && result.dueDate == pending) {
            val event = trigger.title.replaceFirstChar { it.lowercaseChar() }
            return if (!pending.isAfter(now)) "Due after the $event ${Format.relative(pending, now)}"
            else "Due before the $event ${Format.relative(pending, now)}"
        }
        if (!due.hasInterval) {
            if (trigger != null) {
                return listOfNotNull(trigger.dueRule, due.lastDate?.let { "last done ${Format.relative(it, now)}" }).joinToString(", ")
            }
            val last = due.lastDate ?: return "Not logged yet"
            return "Last done ${Format.relative(last, now)}"
        }
        return when (result.status) {
            DueStatus.NO_RECORD -> "When was it last done?"
            DueStatus.OVERDUE -> {
                val reading = result.dueReading
                when {
                    reading != null && due.meter.hasReading && due.currentReading >= reading ->
                        "Overdue by ${Format.reading(due.currentReading - reading, due.meter)}"
                    result.dueDate != null -> "Overdue since ${Format.shortDate(result.dueDate, now)}"
                    else -> "Overdue"
                }
            }
            DueStatus.DUE_SOON, DueStatus.OK -> {
                val date = result.dueDate
                if (date == null) {
                    result.dueReading?.let { "Due at ${Format.reading(it, due.meter)}" } ?: "Up to date"
                } else {
                    val whenText = Format.relative(date, now)
                    if (result.dateIsEstimated && notingPace) "Due $whenText, by your pace" else "Due $whenText"
                }
            }
        }
    }

    /** The one line on a vehicle's key tag. */
    fun cardStatus(dues: List<TaskDue>, headline: GarageStore.Headline, now: Instant = Instant.now()): String {
        val next = headline.next ?: return if (dues.isEmpty()) "No schedule yet" else "Add when jobs were last done"
        val line = dueLine(next, now, notingPace = false)
        if (headline.urgentCount > 1) {
            val overdue = dues.count { it.result.status == DueStatus.OVERDUE }
            val soon = dues.count { it.result.status == DueStatus.DUE_SOON }
            if (overdue > 0 && soon > 0) return "${next.name} overdue, $soon more due soon"
            val state = if (overdue > 0) "overdue" else "due soon"
            return "${next.name} and ${headline.urgentCount - 1} more $state"
        }
        return "${next.name} · ${line.replaceFirstChar { it.lowercaseChar() }}"
    }
}
