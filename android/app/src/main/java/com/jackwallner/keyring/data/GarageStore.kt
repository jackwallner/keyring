package com.jackwallner.keyring.data

import com.jackwallner.keyring.catalog.CatalogItem
import com.jackwallner.keyring.catalog.MaintenanceCatalog
import com.jackwallner.keyring.model.DueEngine
import com.jackwallner.keyring.model.DueInput
import com.jackwallner.keyring.model.DueResult
import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.EntryKind
import com.jackwallner.keyring.model.UsageEvent
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** Where the log's JSON lives: a file on the device, or memory in JVM tests. */
interface GarageFile {
    fun read(): String?
    fun write(text: String)
}

class MemoryGarageFile(var text: String? = null) : GarageFile {
    override fun read(): String? = text
    override fun write(text: String) { this.text = text }
}

/**
 * Every read and write of the log, ported from `GarageStore.swift`. The data
 * is one immutable [GarageData]; [onChange] lets Compose observe each swap.
 */
class GarageStore(
    private val file: GarageFile,
    private val zone: () -> ZoneId = { ZoneId.systemDefault() },
    private val newId: () -> String = { UUID.randomUUID().toString().uppercase() },
) {
    var data: GarageData = GarageCodec.decode(file.read())
        private set
    var onChange: ((GarageData) -> Unit)? = null

    private fun commit(next: GarageData) {
        data = next
        file.write(GarageCodec.encode(next))
        onChange?.invoke(next)
    }

    // MARK: - Reads

    val activeVehicles: List<Vehicle>
        get() = data.vehicles.filter { !it.isRetired }.sortedWith(compareBy<Vehicle> { it.sortIndex }.thenBy { it.createdAt })

    val retiredVehicles: List<Vehicle> get() = data.vehicles.filter { it.isRetired }.sortedBy { it.createdAt }

    fun vehicle(id: String?): Vehicle? = data.vehicles.firstOrNull { it.id == id }

    fun tasks(vehicle: Vehicle): List<MaintenanceTask> = data.tasks.filter { it.vehicleId == vehicle.id }

    fun enabledTasks(vehicle: Vehicle): List<MaintenanceTask> = tasks(vehicle).filter { it.isEnabled }.sortedBy { it.createdAt }

    fun entries(vehicle: Vehicle): List<ServiceEntry> = data.entries.filter { it.vehicleId == vehicle.id }.sortedByDescending { it.date }

    fun readings(vehicle: Vehicle): List<MeterReading> = data.readings.filter { it.vehicleId == vehicle.id }

    /** Every entry, newest first, for the history timeline. */
    fun allEntries(): List<ServiceEntry> = data.entries.sortedByDescending { it.date }

    fun dailyUse(vehicle: Vehicle, now: Instant = Instant.now()): Double {
        val points = readings(vehicle).map { it.date to it.value } +
            entries(vehicle).filter { it.hasReading }.map { it.date to it.reading } +
            listOfNotNull(vehicle.readingDate?.let { it to vehicle.reading })
        return DueEngine.dailyUse(points, typicalDailyUse(vehicle), now)
    }

    /** The kind's typical figure in this vehicle's own unit. */
    fun typicalDailyUse(vehicle: Vehicle): Double {
        if (vehicle.yearlyUse > 0) return vehicle.yearlyUse / 365
        val miles = vehicle.kind.typicalDailyUse
        return if (vehicle.meter == com.jackwallner.keyring.model.MeterUnit.kilometers) miles * 1.609344 else miles
    }

    /** The highest reading known by the end of `date`, from meter updates and logged entries. */
    fun reading(vehicle: Vehicle, on: Instant): Double? {
        val cutoff = on.atZone(zone()).toLocalDate().plusDays(1).atStartOfDay(zone()).toInstant()
        val values = readings(vehicle).filter { it.date < cutoff }.map { it.value } +
            entries(vehicle).filter { it.hasReading && it.date < cutoff }.map { it.reading } +
            listOfNotNull(vehicle.readingDate?.takeIf { it < cutoff }?.let { vehicle.reading })
        return values.maxOrNull()
    }

    /** The most recent time this job was done: a logged entry that covered it, or the setup baseline, whichever is later. */
    fun lastDone(task: MaintenanceTask): Pair<Instant?, Double?> {
        var date = task.baselineDate
        var reading: Double? = task.baselineReading.takeIf { it >= 0 }
        val vehicle = vehicle(task.vehicleId) ?: return date to reading
        val latest = data.entries.filter { it.vehicleId == vehicle.id && task.id in it.taskIds }.maxByOrNull { it.date }
        if (latest != null && latest.date >= (date ?: Instant.MIN)) {
            date = latest.date
            // No reading on the entry: the meter as it stood that day, never an older visit's.
            reading = if (latest.hasReading) latest.reading else reading(vehicle, latest.date)
        }
        return date to reading
    }

    fun dues(vehicle: Vehicle, now: Instant = Instant.now()): List<TaskDue> {
        val pace = dailyUse(vehicle, now)
        return enabledTasks(vehicle).map { task ->
            val (lastDate, lastReading) = lastDone(task)
            val results = mutableListOf(DueEngine.evaluate(DueInput(
                intervalDistance = task.intervalDistance,
                intervalMonths = task.intervalMonths,
                lastDate = lastDate,
                lastReading = lastReading,
                currentReading = vehicle.reading,
                dailyUse = pace,
                meter = vehicle.meter,
                calendarMonths = MaintenanceCatalog.usesCalendarMonths(task.catalogKey, vehicle.kind),
            ), now, zone()))
            val pending = task.trigger?.let { pendingEvent(it, vehicle, lastDate) }
            if (pending != null) results.add(DueEngine.triggered(pending, now))
            TaskDue(task, DueEngine.combine(results), lastDate, lastReading, vehicle.meter, vehicle.reading, pending)
        }.sortedWith(::ordering)
    }

    /** The earliest event of this kind logged after the job was last done. */
    fun pendingEvent(event: UsageEvent, vehicle: Vehicle, after: Instant?): Instant? {
        val since = after?.let { it.atZone(zone()).toLocalDate().plusDays(1).atStartOfDay(zone()).toInstant() } ?: Instant.MIN
        return entries(vehicle).filter { it.kind == EntryKind.event && it.event == event && it.date >= since }.minOfOrNull { it.date }
    }

    data class Headline(val status: DueStatus, val urgentCount: Int, val next: TaskDue?)

    /** The worst known status on a vehicle and the next job, for its card. */
    fun headline(vehicle: Vehicle, now: Instant = Instant.now()): Headline = headline(dues(vehicle, now))

    fun headline(dues: List<TaskDue>): Headline {
        val known = dues.filter { it.result.status != DueStatus.NO_RECORD }
        val status = known.firstOrNull()?.result?.status ?: if (dues.isEmpty()) DueStatus.OK else DueStatus.NO_RECORD
        return Headline(status, known.count { it.result.status <= DueStatus.DUE_SOON }, known.firstOrNull())
    }

    // MARK: - Vehicles

    fun addVehicle(draft: NewVehicle, now: Instant = Instant.now()): Vehicle {
        val vehicle = Vehicle(
            id = newId(),
            createdAt = now,
            kind = draft.kind,
            powertrain = draft.powertrain,
            meter = draft.meter,
            nickname = draft.nickname.trim().ifEmpty { null },
            year = draft.year.coerceIn(0, Short.MAX_VALUE.toInt()),
            make = draft.make.trim().ifEmpty { null },
            model = draft.model.trim().ifEmpty { null },
            trim = draft.trim.trim().ifEmpty { null },
            vin = draft.vin.trim().uppercase().ifEmpty { null },
            plate = draft.plate.trim().uppercase().ifEmpty { null },
            reading = maxOf(0.0, draft.reading),
            readingDate = if (draft.meter.hasReading) now else null,
            tint = draft.tint ?: com.jackwallner.keyring.model.VehicleTint.defaultTint(draft.kind),
            sortIndex = data.vehicles.size,
            yearlyUse = if (draft.meter.hasReading) maxOf(0.0, draft.yearlyUse) else 0.0,
            traits = draft.traits,
            drive = if (draft.kind == com.jackwallner.keyring.model.VehicleKind.motorcycle) draft.drive else null,
        )
        val readings = if (draft.meter.hasReading) listOf(MeterReading(newId(), vehicle.id, now, vehicle.reading)) else emptyList()
        val starting = vehicle.catalogItems.filter { it.isCore }
        val tasks = starting.mapIndexed { index, item ->
            var task = makeTask(item, vehicle, now.plusMillis(index.toLong()))
            val done = draft.lastDone[item.key]
            if (done != null) {
                // A date in the last few weeks most likely came at today's reading; older ones leave the meter unknown.
                val recent = now.toEpochMilli() - done.toEpochMilli() < 45L * 86_400_000L
                task = task.copy(baselineDate = done, baselineReading = if (recent && draft.meter.hasReading) vehicle.reading else -1.0)
            }
            task
        }
        commit(data.copy(vehicles = data.vehicles + vehicle, tasks = data.tasks + tasks, readings = data.readings + readings))
        return vehicle
    }

    fun makeTask(item: CatalogItem, vehicle: Vehicle, createdAt: Instant = Instant.now()) = MaintenanceTask(
        id = newId(),
        vehicleId = vehicle.id,
        createdAt = createdAt,
        catalogKey = item.key,
        name = item.name,
        symbol = item.symbol,
        intervalDistance = item.distanceInterval(vehicle.meter) ?: 0.0,
        intervalMonths = item.months ?: 0,
        trigger = item.trigger,
    )

    /** Catalog jobs not yet switched on for this vehicle, for "Add from the catalog". */
    fun availableCatalogItems(vehicle: Vehicle): List<CatalogItem> {
        val on = enabledTasks(vehicle).mapNotNull { it.catalogKey }.toSet()
        return vehicle.catalogItems.filter { it.key !in on }
    }

    fun addCatalogItems(items: List<CatalogItem>, vehicle: Vehicle) {
        val existing = tasks(vehicle)
        var tasks = data.tasks
        for (item in items) {
            val match = existing.firstOrNull { it.catalogKey == item.key }
            tasks = if (match != null) tasks.map { if (it.id == match.id) it.copy(isEnabled = true) else it }
            else tasks + makeTask(item, vehicle)
        }
        commit(data.copy(tasks = tasks))
    }

    fun addCustomTask(name: String, distance: Double, months: Int, vehicle: Vehicle): MaintenanceTask {
        val task = MaintenanceTask(
            id = newId(), vehicleId = vehicle.id, createdAt = Instant.now(), name = name.trim(),
            intervalDistance = maxOf(0.0, distance), intervalMonths = maxOf(0, months),
        )
        commit(data.copy(tasks = data.tasks + task))
        return task
    }

    fun updateTask(task: MaintenanceTask, name: String, distance: Double, months: Int, notes: String) {
        val next = task.copy(
            name = name.trim().ifEmpty { task.name },
            intervalDistance = maxOf(0.0, distance),
            intervalMonths = maxOf(0, months),
            notes = notes.trim().ifEmpty { null },
        )
        commit(data.copy(tasks = data.tasks.map { if (it.id == task.id) next else it }))
    }

    /** Switches a job off; its history stays. */
    fun remove(task: MaintenanceTask) {
        commit(data.copy(tasks = data.tasks.map { if (it.id == task.id) it.copy(isEnabled = false) else it }))
    }

    fun setBaseline(task: MaintenanceTask, date: Instant, reading: Double?) {
        commit(data.copy(tasks = data.tasks.map { if (it.id == task.id) it.copy(baselineDate = date, baselineReading = reading ?: -1.0) else it }))
    }

    fun updateVehicle(vehicle: Vehicle) {
        commit(data.copy(vehicles = data.vehicles.map { if (it.id == vehicle.id) vehicle else it }))
    }

    fun retire(vehicle: Vehicle, retired: Boolean = true) = updateVehicle(vehicle.copy(isRetired = retired))

    fun delete(vehicle: Vehicle) {
        commit(GarageData(
            vehicles = data.vehicles.filter { it.id != vehicle.id },
            tasks = data.tasks.filter { it.vehicleId != vehicle.id },
            entries = data.entries.filter { it.vehicleId != vehicle.id },
            readings = data.readings.filter { it.vehicleId != vehicle.id },
        ))
    }

    fun updateReading(vehicle: Vehicle, value: Double, at: Instant = Instant.now()) {
        if (!vehicle.meter.hasReading || value < 0) return
        val reading = MeterReading(newId(), vehicle.id, at, value)
        val moved = value >= vehicle.reading || (vehicle.readingDate ?: Instant.MIN) <= at
        val next = if (moved) vehicle.copy(
            reading = maxOf(vehicle.reading, value),
            readingDate = maxOf(vehicle.readingDate ?: Instant.MIN, at),
        ) else vehicle
        commit(data.copy(
            vehicles = data.vehicles.map { if (it.id == vehicle.id) next else it },
            readings = data.readings + reading,
        ))
    }

    /** A reading far beyond the vehicle's pace is usually a typo: an extra digit. */
    fun isSuspiciousJump(value: Double, vehicle: Vehicle, now: Instant = Instant.now()): Boolean {
        if (!vehicle.meter.hasReading || vehicle.reading <= 0 || value <= vehicle.reading) return false
        val days = maxOf(1.0, (now.toEpochMilli() - (vehicle.readingDate ?: now).toEpochMilli()) / 86_400_000.0)
        val plausible = maxOf(dailyUse(vehicle, now), typicalDailyUse(vehicle)) * days * 4 + vehicle.meter.typoSlack
        return value - vehicle.reading > plausible
    }

    // MARK: - Service log

    fun log(draft: ServiceDraft, vehicle: Vehicle, editing: ServiceEntry? = null, now: Instant = Instant.now()): ServiceEntry {
        val entry = ServiceEntry(
            id = editing?.id ?: newId(),
            vehicleId = vehicle.id,
            createdAt = editing?.createdAt ?: now,
            date = draft.date,
            reading = draft.reading ?: -1.0,
            // Mods and events don't do scheduled jobs; an event's own jobs come due from it instead.
            taskIds = if (draft.kind == EntryKind.event) emptyList() else draft.taskIds,
            title = draft.title.trim().ifEmpty { defaultTitle(draft, vehicle) },
            cost = maxOf(0.0, draft.cost),
            shop = if (draft.isDIY) null else draft.shop.trim().ifEmpty { null },
            isDIY = draft.isDIY,
            notes = draft.notes.trim().ifEmpty { null },
            kind = draft.kind,
            recallCampaign = draft.recallCampaign,
            fuelVolume = maxOf(0.0, draft.fuelVolume),
            fuelUnitPrice = maxOf(0.0, draft.fuelUnitPrice),
            event = if (draft.kind == EntryKind.event) draft.event else null,
        )
        val reading = draft.reading
        val nextVehicle = if (reading != null && reading > vehicle.reading && draft.date <= now) {
            vehicle.copy(reading = reading, readingDate = draft.date)
        } else vehicle
        val entries = if (editing != null) data.entries.map { if (it.id == editing.id) entry else it } else data.entries + entry
        commit(data.copy(entries = entries, vehicles = data.vehicles.map { if (it.id == vehicle.id) nextVehicle else it }))
        return entry
    }

    private fun defaultTitle(draft: ServiceDraft, vehicle: Vehicle): String = when {
        draft.kind == EntryKind.event -> draft.event?.title ?: EntryKind.event.title
        draft.kind == EntryKind.mod -> "Mod"
        draft.kind == EntryKind.fuel -> EntryKind.fuel.title
        draft.kind == EntryKind.repair && draft.taskIds.isEmpty() -> "Repair"
        else -> title(draft.taskIds, vehicle)
    }

    fun title(taskIds: List<String>, vehicle: Vehicle): String {
        val names = tasks(vehicle).filter { it.id in taskIds }.sortedBy { it.createdAt }.map { it.name }
        return when (names.size) {
            0 -> "Service"
            1 -> names[0]
            2 -> "${names[0]} and ${names[1].replaceFirstChar { it.lowercaseChar() }}"
            else -> "${names[0]} and ${names.size - 1} more"
        }
    }

    fun delete(entry: ServiceEntry) = commit(data.copy(entries = data.entries.filter { it.id != entry.id }))

    /** Restores a whole log, used by tests and the debug seed. */
    fun replaceAll(next: GarageData) = commit(next)

    companion object {
        private fun rank(status: DueStatus): Int = when (status) {
            DueStatus.OVERDUE -> 0
            DueStatus.DUE_SOON -> 1
            DueStatus.OK -> 2
            DueStatus.NO_RECORD -> 3
        }

        /** Overdue, due soon, then up to date by date, with no-record jobs last. */
        fun ordering(lhs: TaskDue, rhs: TaskDue): Int {
            if (lhs.result.status != rhs.result.status) return rank(lhs.result.status) - rank(rhs.result.status)
            val l = lhs.result.dueDate
            val r = rhs.result.dueDate
            return when {
                l != null && r != null -> l.compareTo(r)
                l != null -> -1
                r != null -> 1
                else -> lhs.name.compareTo(rhs.name)
            }
        }
    }
}

/** Every entry as a spreadsheet. Free, always: a log you can't take with you isn't yours. */
object CSVExport {
    val header = listOf("Vehicle", "Year", "Make", "Model", "Date", "Odometer", "Unit", "Type", "Work", "Covered jobs", "Cost", "Shop", "DIY", "Notes", "Logged by", "Fuel", "Fuel unit", "Price per unit", "Grade", "Partial fill", "Parts", "Measurements", "Second meter")

    fun csv(store: GarageStore, vehicles: List<Vehicle>, zone: ZoneId = ZoneId.systemDefault(), unit: FuelUnit = FuelUnit.current()): String {
        val lines = mutableListOf(header.joinToString(",") { escape(it) })
        for (vehicle in vehicles) {
            val tasks = store.tasks(vehicle)
            for (entry in store.entries(vehicle)) {
                val covered = tasks.filter { it.id in entry.taskIds }.map { it.name }
                val fuel = entry.kind == EntryKind.fuel
                val fields = listOf(
                    vehicle.displayName,
                    if (vehicle.year > 0) vehicle.year.toString() else "",
                    vehicle.make.orEmpty(),
                    vehicle.model.orEmpty(),
                    entry.date.atZone(zone).toLocalDate().toString(),
                    if (entry.hasReading) Math.round(entry.reading).toString() else "",
                    vehicle.meter.short,
                    entry.kind.title,
                    entry.title,
                    covered.joinToString("; "),
                    if (entry.cost > 0) "%.2f".format(java.util.Locale.US, entry.cost) else "",
                    entry.shop.orEmpty(),
                    if (entry.isDIY) "Yes" else "",
                    entry.notes.orEmpty(),
                    "",
                    if (fuel && entry.fuelVolume > 0) "%.3f".format(java.util.Locale.US, unit.fromLiters(entry.fuelVolume)) else "",
                    if (fuel) unit.short else "",
                    if (fuel && entry.fuelUnitPrice > 0) "%.3f".format(java.util.Locale.US, unit.fromPerLiter(entry.fuelUnitPrice)) else "",
                    "", "", "", "", "",
                )
                lines.add(fields.joinToString(",") { escape(it) })
            }
        }
        return lines.joinToString("\n") + "\n"
    }

    fun escape(field: String): String {
        var value = field
        // A leading = + - @ makes spreadsheets run the cell as a formula.
        if (value.isNotEmpty() && value[0] in "=+-@") value = "'$value"
        if (value.any { it == ',' || it == '"' || it == '\n' }) return "\"" + value.replace("\"", "\"\"") + "\""
        return value
    }
}

/** Spending insights (Pro): totals by kind and cost per distance. */
object CostInsights {
    data class Summary(val upkeep: Double, val fuel: Double, val mods: Double, val perUnit: Double?)

    fun summary(store: GarageStore, vehicle: Vehicle): Summary {
        val entries = store.entries(vehicle)
        val upkeep = entries.filter { it.kind.isUpkeep }.sumOf { it.cost }
        val fuel = entries.filter { it.kind == EntryKind.fuel }.sumOf { it.cost }
        val mods = entries.filter { it.kind == EntryKind.mod }.sumOf { it.cost }
        val readings = store.readings(vehicle).map { it.value } + entries.filter { it.hasReading }.map { it.reading }
        val span = (readings.maxOrNull() ?: 0.0) - (readings.minOrNull() ?: 0.0)
        val perUnit = if (span > 0 && vehicle.meter.hasReading) (upkeep + fuel) / span else null
        return Summary(upkeep, fuel, mods, perUnit)
    }
}

fun DueResult.isUrgent(): Boolean = status <= DueStatus.DUE_SOON
