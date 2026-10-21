package com.jackwallner.keyring.data

import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.Format
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

/**
 * What the widget shows, written by the app after every change. The widget
 * never opens the log, so it can't show anything the app wouldn't. Ported
 * from `WidgetSnapshot.swift`.
 */
data class WidgetSnapshot(val vehicles: List<VehicleSummary>) {
    data class Item(val name: String, val status: DueStatus, val dueDate: Instant?, val estimated: Boolean, val dueAt: String?)

    data class VehicleSummary(val id: String, val name: String, val tintHex: Long, val tintIsLight: Boolean, val items: List<Item>)

    /** Every job across the garage, most urgent first. */
    val upcoming: List<Pair<VehicleSummary, Item>>
        get() = vehicles.flatMap { vehicle -> vehicle.items.map { vehicle to it } }
            .sortedWith(compareBy<Pair<VehicleSummary, Item>> { it.second.status.ordinal }.thenBy { it.second.dueDate ?: Instant.MAX })

    fun encode(): String = JSONObject().put("vehicles", JSONArray(vehicles.map { v ->
        JSONObject().put("id", v.id).put("name", v.name).put("tintHex", v.tintHex).put("light", v.tintIsLight)
            .put("items", JSONArray(v.items.map { i ->
                JSONObject().put("name", i.name).put("status", i.status.name).putOpt("dueDate", i.dueDate?.toEpochMilli())
                    .put("estimated", i.estimated).putOpt("dueAt", i.dueAt)
            }))
    })).toString()

    companion object {
        const val KEY = "widgetSnapshot"
        val EMPTY = WidgetSnapshot(emptyList())

        /** Stored vehicles are left out: nothing on them is moving. */
        fun build(store: GarageStore, now: Instant = Instant.now()): WidgetSnapshot = WidgetSnapshot(
            store.activeVehicles.filter { !it.isStored }.map { vehicle ->
                val dues = store.dues(vehicle, now).filter { it.result.status != DueStatus.NO_RECORD }
                VehicleSummary(vehicle.id, vehicle.displayName, vehicle.tint.hex, vehicle.tint.isLight, dues.take(3).map { due ->
                    Item(due.name, due.result.status, due.result.dueDate, due.result.dateIsEstimated, due.result.dueReading?.let { "At ${Format.reading(it, due.meter)}" })
                })
            },
        )

        fun decode(text: String?): WidgetSnapshot {
            val root = text?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return EMPTY
            val array = root.optJSONArray("vehicles") ?: return EMPTY
            return WidgetSnapshot((0 until array.length()).mapNotNull { index ->
                val v = array.optJSONObject(index) ?: return@mapNotNull null
                val items = v.optJSONArray("items")
                VehicleSummary(v.optString("id"), v.optString("name"), v.optLong("tintHex"), v.optBoolean("light"),
                    (0 until (items?.length() ?: 0)).mapNotNull { i ->
                        val o = items?.optJSONObject(i) ?: return@mapNotNull null
                        Item(o.optString("name"), DueStatus.entries.firstOrNull { it.name == o.optString("status") } ?: DueStatus.OK,
                            if (o.has("dueDate")) Instant.ofEpochMilli(o.getLong("dueDate")) else null, o.optBoolean("estimated"),
                            if (o.has("dueAt")) o.getString("dueAt") else null)
                    })
            })
        }

        /** "Overdue", "Today", "~9 days", "3 wks", "Mar 4". */
        fun whenText(item: Item, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String {
            if (item.status == DueStatus.OVERDUE) return "Overdue"
            val date = item.dueDate ?: return item.dueAt ?: "Up to date"
            val days = ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), date.atZone(zone).toLocalDate())
            val prefix = if (item.estimated) "~" else ""
            return when {
                days < 1 -> "Today"
                days == 1L -> "Tomorrow"
                days < 14 -> "$prefix$days days"
                days < 60 -> "$prefix${days / 7} wks"
                else -> date.atZone(zone).format(DateTimeFormatter.ofPattern("MMM d", locale))
            }
        }
    }
}
