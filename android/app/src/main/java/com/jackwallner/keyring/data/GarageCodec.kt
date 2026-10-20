package com.jackwallner.keyring.data

import com.jackwallner.keyring.model.EntryKind
import com.jackwallner.keyring.model.FinalDrive
import com.jackwallner.keyring.model.MeterUnit
import com.jackwallner.keyring.model.Powertrain
import com.jackwallner.keyring.model.UsageEvent
import com.jackwallner.keyring.model.VehicleKind
import com.jackwallner.keyring.model.VehicleTint
import com.jackwallner.keyring.model.VehicleTrait
import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject

/** JSON for the whole log, with the iOS attribute names and raw values. Unknown or broken rows are skipped, never fatal. */
object GarageCodec {
    const val VERSION = 1

    fun encode(data: GarageData): String = JSONObject()
        .put("version", VERSION)
        .put("vehicles", JSONArray(data.vehicles.map(::vehicle)))
        .put("tasks", JSONArray(data.tasks.map(::task)))
        .put("entries", JSONArray(data.entries.map(::entry)))
        .put("readings", JSONArray(data.readings.map(::reading)))
        .toString()

    fun decode(text: String?): GarageData {
        if (text.isNullOrBlank()) return GarageData()
        val root = runCatching { JSONObject(text) }.getOrNull() ?: return GarageData()
        return GarageData(
            vehicles = rows(root, "vehicles", ::vehicle),
            tasks = rows(root, "tasks", ::task),
            entries = rows(root, "entries", ::entry),
            readings = rows(root, "readings", ::reading),
        )
    }

    private fun <T> rows(root: JSONObject, key: String, read: (JSONObject) -> T): List<T> {
        val array = root.optJSONArray(key) ?: return emptyList()
        return (0 until array.length()).mapNotNull { index -> array.optJSONObject(index)?.let { runCatching { read(it) }.getOrNull() } }
    }

    private fun vehicle(v: Vehicle) = JSONObject()
        .put("id", v.id).put("createdAt", v.createdAt.toEpochMilli())
        .put("kindRaw", v.kind.name).put("powertrainRaw", v.powertrain.name).put("meterRaw", v.meter.name)
        .putOpt("nickname", v.nickname).put("year", v.year).putOpt("make", v.make).putOpt("model", v.model)
        .putOpt("trim", v.trim).putOpt("vin", v.vin).putOpt("plate", v.plate)
        .put("reading", v.reading).putOpt("readingDate", v.readingDate?.toEpochMilli())
        .put("tintRaw", v.tint.name).putOpt("notes", v.notes).put("sortIndex", v.sortIndex)
        .put("isRetired", v.isRetired).put("yearlyUse", v.yearlyUse)
        .put("traits", JSONArray(v.traits.map { it.name }.sorted())).putOpt("drive", v.drive?.name)

    private fun vehicle(o: JSONObject): Vehicle {
        val kind = VehicleKind.fromRaw(o.optString("kindRaw"))
        val traits = o.optJSONArray("traits")?.let { a -> (0 until a.length()).mapNotNull { i -> VehicleTrait.entries.firstOrNull { it.name == a.optString(i) } } }
        return Vehicle(
            id = o.getString("id"),
            createdAt = instant(o, "createdAt") ?: Instant.EPOCH,
            kind = kind,
            powertrain = Powertrain.fromRaw(o.optString("powertrainRaw")) ?: kind.defaultPowertrain,
            meter = MeterUnit.fromRaw(o.optString("meterRaw")) ?: kind.defaultMeter,
            nickname = string(o, "nickname"), year = o.optInt("year"), make = string(o, "make"), model = string(o, "model"),
            trim = string(o, "trim"), vin = string(o, "vin"), plate = string(o, "plate"),
            reading = o.optDouble("reading", 0.0), readingDate = instant(o, "readingDate"),
            tint = VehicleTint.fromRaw(o.optString("tintRaw")) ?: VehicleTint.defaultTint(kind),
            notes = string(o, "notes"), sortIndex = o.optInt("sortIndex"), isRetired = o.optBoolean("isRetired"),
            yearlyUse = o.optDouble("yearlyUse", 0.0), traits = traits.orEmpty().toSet(),
            drive = FinalDrive.entries.firstOrNull { it.name == o.optString("drive") },
        )
    }

    private fun task(t: MaintenanceTask) = JSONObject()
        .put("id", t.id).put("vehicleId", t.vehicleId).put("createdAt", t.createdAt.toEpochMilli())
        .putOpt("catalogKey", t.catalogKey).put("name", t.name).put("symbol", t.symbol)
        .put("intervalDistance", t.intervalDistance).put("intervalMonths", t.intervalMonths)
        .putOpt("baselineDate", t.baselineDate?.toEpochMilli()).put("baselineReading", t.baselineReading)
        .put("isEnabled", t.isEnabled).putOpt("notes", t.notes).putOpt("triggerRaw", t.trigger?.name)

    private fun task(o: JSONObject) = MaintenanceTask(
        id = o.getString("id"), vehicleId = o.getString("vehicleId"), createdAt = instant(o, "createdAt") ?: Instant.EPOCH,
        catalogKey = string(o, "catalogKey"), name = o.getString("name"), symbol = o.optString("symbol", "wrench.adjustable"),
        intervalDistance = o.optDouble("intervalDistance", 0.0), intervalMonths = o.optInt("intervalMonths"),
        baselineDate = instant(o, "baselineDate"), baselineReading = o.optDouble("baselineReading", -1.0),
        isEnabled = o.optBoolean("isEnabled", true), notes = string(o, "notes"), trigger = UsageEvent.fromRaw(string(o, "triggerRaw")),
    )

    private fun entry(e: ServiceEntry) = JSONObject()
        .put("id", e.id).put("vehicleId", e.vehicleId).put("createdAt", e.createdAt.toEpochMilli())
        .put("date", e.date.toEpochMilli()).put("reading", e.reading).put("title", e.title)
        .put("taskIDs", JSONArray(e.taskIds)).put("cost", e.cost).putOpt("shop", e.shop).put("isDIY", e.isDIY)
        .putOpt("notes", e.notes).put("kindRaw", e.kind.name).putOpt("recallCampaign", e.recallCampaign)
        .put("fuelVolume", e.fuelVolume).put("fuelUnitPrice", e.fuelUnitPrice).putOpt("event", e.event?.name)

    private fun entry(o: JSONObject): ServiceEntry {
        val ids = o.optJSONArray("taskIDs")?.let { a -> (0 until a.length()).map { a.getString(it) } }.orEmpty()
        return ServiceEntry(
            id = o.getString("id"), vehicleId = o.getString("vehicleId"), createdAt = instant(o, "createdAt") ?: Instant.EPOCH,
            date = instant(o, "date") ?: Instant.EPOCH, reading = o.optDouble("reading", -1.0), title = o.optString("title", "Service"),
            taskIds = ids, cost = o.optDouble("cost", 0.0), shop = string(o, "shop"), isDIY = o.optBoolean("isDIY"),
            notes = string(o, "notes"), kind = EntryKind.fromRaw(string(o, "kindRaw")), recallCampaign = string(o, "recallCampaign"),
            fuelVolume = o.optDouble("fuelVolume", 0.0), fuelUnitPrice = o.optDouble("fuelUnitPrice", 0.0),
            event = UsageEvent.fromRaw(string(o, "event")),
        )
    }

    private fun reading(r: MeterReading) = JSONObject()
        .put("id", r.id).put("vehicleId", r.vehicleId).put("date", r.date.toEpochMilli()).put("value", r.value)

    private fun reading(o: JSONObject) = MeterReading(
        id = o.getString("id"), vehicleId = o.getString("vehicleId"), date = instant(o, "date") ?: Instant.EPOCH, value = o.getDouble("value"),
    )

    private fun string(o: JSONObject, key: String): String? = if (o.has(key) && !o.isNull(key)) o.getString(key) else null

    private fun instant(o: JSONObject, key: String): Instant? = if (o.has(key) && !o.isNull(key)) Instant.ofEpochMilli(o.getLong(key)) else null
}
