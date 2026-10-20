package com.jackwallner.keyring.data

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.jackwallner.keyring.KeyringApplication
import com.jackwallner.keyring.MainActivity
import com.jackwallner.keyring.R
import com.jackwallner.keyring.model.DueStatus
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

/**
 * Local reminders, rebuilt from scratch after every change, ported from
 * `ReminderScheduler.swift`: one heads-up a week ahead, one on the day, and
 * overdue jobs rolled into a single Saturday-morning note for a few weeks.
 * Alarms are inexact, so no exact-alarm permission or Play declaration.
 */
class ReminderScheduler(private val context: Context, private val defaults: KeyValueStore) {
    data class Planned(val id: String, val title: String, val body: String, val fireAt: Instant, val vehicleId: String? = null)

    data class PlanInput(val vehicle: String, val vehicleId: String, val due: TaskDue)

    var enabled: Boolean
        get() = defaults.getBoolean(ENABLED, true)
        set(value) = defaults.putBoolean(ENABLED, value)

    val reminderHour: Int get() = if (defaults.contains(HOUR)) defaults.getInt(HOUR) else 9

    val hasPermission: Boolean
        get() = Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun ensureChannel() {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Maintenance reminders", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "A week ahead, on the day, and a Saturday roundup of anything overdue."
        })
    }

    fun refresh(store: GarageStore, now: Instant = Instant.now()) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val previous = defaults.getStringSet(SCHEDULED)
        previous.forEach { alarms.cancel(pending(it, null)) }
        if (!enabled) {
            defaults.putStringSet(SCHEDULED, emptySet())
            return
        }
        val inputs = store.activeVehicles.flatMap { vehicle -> store.dues(vehicle, now).map { PlanInput(vehicle.displayName, vehicle.id, it) } }
        val planned = plan(inputs, now, reminderHour, ZoneId.systemDefault())
        planned.forEach { alarms.set(AlarmManager.RTC_WAKEUP, it.fireAt.toEpochMilli(), pending(it.id, it)) }
        defaults.putStringSet(SCHEDULED, planned.map { it.id }.toSet())
    }

    private fun pending(id: String, planned: Planned?): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java).setAction("reminder.$id")
        if (planned != null) {
            intent.putExtra(EXTRA_ID, planned.id).putExtra(EXTRA_TITLE, planned.title).putExtra(EXTRA_BODY, planned.body)
                .putExtra(EXTRA_VEHICLE, planned.vehicleId)
        }
        return PendingIntent.getBroadcast(context, id.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    companion object {
        const val CHANNEL = "maintenance"
        const val OVERDUE_WEEKS = 4
        private const val ENABLED = "remindersEnabled"
        private const val HOUR = "reminderHour"
        private const val SCHEDULED = "scheduledReminders"
        const val EXTRA_ID = "id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_VEHICLE = "vehicleId"

        /** Pure planning, so the rules are testable without an alarm manager. */
        fun plan(dues: List<PlanInput>, now: Instant, hour: Int, zone: ZoneId): List<Planned> {
            fun atHour(date: Instant): Instant = date.atZone(zone).withHour(hour).withMinute(0).withSecond(0).withNano(0).toInstant()
            val planned = mutableListOf<Planned>()
            for ((vehicle, vehicleId, due) in dues) {
                val dueDate = due.result.dueDate ?: continue
                if (due.result.status == DueStatus.NO_RECORD || due.result.status == DueStatus.OVERDUE) continue
                val approximate = if (due.result.dateIsEstimated) "around " else ""
                val weekBefore = atHour(dueDate.minusSeconds(7 * 86_400))
                if (weekBefore > now) {
                    planned.add(Planned("week-$vehicleId-${due.task.id}", "$vehicle: ${due.name}",
                        "Coming due ${approximate}next week. Book it now and it's one less thing.", weekBefore, vehicleId))
                }
                val onDay = atHour(dueDate)
                if (onDay > now) {
                    planned.add(Planned("day-$vehicleId-${due.task.id}", "$vehicle: ${due.name}",
                        if (due.result.dateIsEstimated) "Should be due about now, going by your usual pace. Tap to log it or update the meter."
                        else "Due today. Tap to log it when it's done.", onDay, vehicleId))
                }
            }
            val overdue = dues.filter { it.due.result.status == DueStatus.OVERDUE }
            if (overdue.isNotEmpty()) {
                val local = now.atZone(zone)
                var saturday = local.with(TemporalAdjusters.nextOrSame(DayOfWeek.SATURDAY)).withHour(hour).withMinute(0).withSecond(0).withNano(0)
                if (!saturday.toInstant().isAfter(now)) saturday = saturday.plusWeeks(1)
                val names = overdue.take(3).map { "${it.vehicle} ${it.due.name.replaceFirstChar { c -> c.lowercaseChar() }}" }
                val more = if (overdue.size > 3) " and ${overdue.size - 3} more" else ""
                for (week in 0 until OVERDUE_WEEKS) {
                    planned.add(Planned(
                        if (week == 0) "weekend-overdue" else "weekend-overdue-${week + 1}",
                        if (overdue.size == 1) "One job is overdue" else "${overdue.size} jobs are overdue",
                        names.joinToString(", ") + more + ".",
                        saturday.plusWeeks(week.toLong()).toInstant(),
                    ))
                }
            }
            return planned.sortedBy { it.fireAt }.take(60)
        }
    }
}

/** Posts one planned reminder; a tap opens the vehicle. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(ReminderScheduler.EXTRA_ID) ?: return
        val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(MainActivity.EXTRA_VEHICLE, intent.getStringExtra(ReminderScheduler.EXTRA_VEHICLE))
        val tap = PendingIntent.getActivity(context, id.hashCode(), open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, ReminderScheduler.CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(intent.getStringExtra(ReminderScheduler.EXTRA_TITLE))
            .setContentText(intent.getStringExtra(ReminderScheduler.EXTRA_BODY))
            .setStyle(NotificationCompat.BigTextStyle().bigText(intent.getStringExtra(ReminderScheduler.EXTRA_BODY)))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()
        val manager = NotificationManagerCompat.from(context)
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        manager.notify(id.hashCode(), notification)
    }
}

private val RESCHEDULE_ACTIONS = setOf(
    Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED,
)

/** Alarms don't survive a reboot or an update; this puts them back. */
class RescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in RESCHEDULE_ACTIONS) return
        val graph = (context.applicationContext as KeyringApplication).graph
        graph.reminders.refresh(graph.garage)
    }
}
