package com.jackwallner.keyring.data

import com.jackwallner.keyring.catalog.CatalogItem
import com.jackwallner.keyring.catalog.MaintenanceCatalog
import com.jackwallner.keyring.model.DueEngine
import com.jackwallner.keyring.model.DueInput
import com.jackwallner.keyring.model.DueResult
import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.EntryKind
import com.jackwallner.keyring.model.MeterUnit
import com.jackwallner.keyring.model.swiftRound
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

/** Where photos and documents live: files beside the log, or memory in JVM tests. */
interface AttachmentFiles {
    /** Saves the bytes and returns the file name to keep on the row. */
    fun save(id: String, extension: String, bytes: ByteArray): String
    fun read(file: String): ByteArray?
    fun delete(file: String)
}

class MemoryAttachmentFiles : AttachmentFiles {
    val files = mutableMapOf<String, ByteArray>()
    override fun save(id: String, extension: String, bytes: ByteArray): String = "$id.$extension".also { files[it] = bytes }
    override fun read(file: String): ByteArray? = files[file]
    override fun delete(file: String) { files.remove(file) }
}

/**
 * Every read and write of the log, ported from `GarageStore.swift`. The data
 * is one immutable [GarageData]; [onChange] lets Compose observe each swap.
 */
class GarageStore(
    private val file: GarageFile,
    val files: AttachmentFiles = MemoryAttachmentFiles(),
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

    /** Main-meter readings only; the second meter keeps its own. */
    fun readings(vehicle: Vehicle): List<MeterReading> = data.readings.filter { it.vehicleId == vehicle.id && !it.isAux }

    fun auxReadings(vehicle: Vehicle): List<MeterReading> = data.readings.filter { it.vehicleId == vehicle.id && it.isAux }

    /** Papers kept with the vehicle, newest first. */
    fun documents(vehicle: Vehicle): List<Attachment> =
        data.attachments.filter { it.vehicleId == vehicle.id && it.entryId == null }.sortedByDescending { it.createdAt }

    fun attachments(entry: ServiceEntry): List<Attachment> = data.attachments.filter { it.entryId == entry.id }.sortedBy { it.createdAt }

    /** Noted values, newest first. */
    fun valuations(vehicle: Vehicle): List<Valuation> = data.valuations.filter { it.vehicleId == vehicle.id }.sortedByDescending { it.date }

    /** Every entry, newest first, for the history timeline. */
    fun allEntries(): List<ServiceEntry> = data.entries.sortedByDescending { it.date }

    fun dailyUse(vehicle: Vehicle, now: Instant = Instant.now()): Double {
        val points = readings(vehicle).map { it.date to it.value } +
            entries(vehicle).filter { it.hasReading }.map { it.date to it.reading } +
            listOfNotNull(vehicle.readingDate?.let { it to vehicle.reading })
        return DueEngine.dailyUse(points, typicalDailyUse(vehicle), now)
    }

    /** Use a day on the second meter. A generator runs about 100 hours a year. */
    fun auxDailyUse(vehicle: Vehicle, now: Instant = Instant.now()): Double {
        val points = auxReadings(vehicle).map { it.date to it.value } +
            entries(vehicle).filter { it.hasAuxReading }.map { it.date to it.auxReading } +
            listOfNotNull(vehicle.auxReadingDate?.let { it to vehicle.auxReading })
        return DueEngine.dailyUse(points, 0.3, now)
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

    /** The same for the second meter. */
    fun auxReading(vehicle: Vehicle, on: Instant): Double? {
        val cutoff = on.atZone(zone()).toLocalDate().plusDays(1).atStartOfDay(zone()).toInstant()
        val values = auxReadings(vehicle).filter { it.date < cutoff }.map { it.value } +
            entries(vehicle).filter { it.hasAuxReading && it.date < cutoff }.map { it.auxReading } +
            listOfNotNull(vehicle.auxReadingDate?.takeIf { it < cutoff }?.let { vehicle.auxReading })
        return values.maxOrNull()
    }

    /**
     * The most recent time this job was done: a logged entry that covered it,
     * or the setup baseline, whichever is later. `onAux` reads the second meter.
     */
    fun lastDone(task: MaintenanceTask, onAux: Boolean = task.usesAuxMeter): Pair<Instant?, Double?> {
        var date = task.baselineDate
        // The setup baseline is on the job's own meter only.
        var reading: Double? = task.baselineReading.takeIf { it >= 0 && onAux == task.usesAuxMeter }
        val vehicle = vehicle(task.vehicleId) ?: return date to reading
        val latest = data.entries.filter { it.vehicleId == vehicle.id && task.id in it.taskIds }.maxByOrNull { it.date }
        if (latest != null && latest.date >= (date ?: Instant.MIN)) {
            date = latest.date
            // No reading on the entry: the meter as it stood that day, never an older visit's.
            reading = if (onAux) {
                if (latest.hasAuxReading) latest.auxReading else auxReading(vehicle, latest.date)
            } else {
                if (latest.hasReading) latest.reading else reading(vehicle, latest.date)
            }
        }
        return date to reading
    }

    /** Counted on the vehicle's second meter, which only applies while it has one. */
    fun countsOnAux(task: MaintenanceTask, vehicle: Vehicle): Boolean = task.usesAuxMeter && vehicle.hasAuxMeter

    /** The whichever-first interval on the second meter, when it applies. */
    fun secondInterval(task: MaintenanceTask, vehicle: Vehicle): Double =
        if (!task.usesAuxMeter && task.auxInterval > 0 && vehicle.hasAuxMeter) task.auxInterval else 0.0

    fun dues(vehicle: Vehicle, now: Instant = Instant.now()): List<TaskDue> {
        // Stored, it isn't going anywhere: only the calendar moves.
        val stored = vehicle.isStored
        val pace = if (stored) 0.0 else dailyUse(vehicle, now)
        val auxPace = if (vehicle.hasAuxMeter && !stored) auxDailyUse(vehicle, now) else 0.0
        return enabledTasks(vehicle).map { task ->
            val (lastDate, lastReading) = lastDone(task)
            val onAux = countsOnAux(task, vehicle)
            val meter = if (onAux) vehicle.auxMeter else vehicle.meter
            val current = if (onAux) vehicle.auxReading else vehicle.reading
            val results = mutableListOf(DueEngine.evaluate(DueInput(
                intervalDistance = task.intervalDistance,
                intervalMonths = task.intervalMonths,
                lastDate = lastDate,
                lastReading = lastReading,
                currentReading = current,
                dailyUse = if (onAux) auxPace else pace,
                meter = meter,
                calendarMonths = MaintenanceCatalog.usesCalendarMonths(task.catalogKey, vehicle.kind),
            ), now, zone()))
            val second = secondInterval(task, vehicle)
            if (second > 0) {
                val (auxDate, auxLast) = lastDone(task, onAux = true)
                results.add(DueEngine.evaluate(DueInput(second, 0, auxDate, auxLast, vehicle.auxReading, auxPace, vehicle.auxMeter), now, zone()))
            }
            val pending = task.trigger?.let { pendingEvent(it, vehicle, lastDate) }
            if (pending != null) results.add(DueEngine.triggered(pending, now))
            TaskDue(task, DueEngine.combine(results), lastDate, lastReading, meter, current, pending, onAux, second, vehicle.auxMeter)
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
            auxMeterName = draft.auxMeterName.trim().ifEmpty { null },
            auxMeter = draft.auxMeter.takeIf { it.hasReading } ?: MeterUnit.hours,
        )
        val readings = if (draft.meter.hasReading) listOf(MeterReading(newId(), vehicle.id, now, vehicle.reading)) else emptyList()
        val auxHours = vehicle.hasAuxMeter && vehicle.auxMeter == MeterUnit.hours
        val starting = vehicle.catalogItems.filter { it.isCore || (auxHours && it.auxHours != null) }
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

    fun makeTask(item: CatalogItem, vehicle: Vehicle, createdAt: Instant = Instant.now()): MaintenanceTask {
        val onAux = item.auxHours != null && vehicle.hasAuxMeter && vehicle.auxMeter == MeterUnit.hours
        return MaintenanceTask(
            id = newId(),
            vehicleId = vehicle.id,
            createdAt = createdAt,
            catalogKey = item.key,
            name = item.name,
            symbol = item.symbol,
            intervalDistance = if (onAux) item.auxHours!! else item.distanceInterval(vehicle.meter) ?: 0.0,
            intervalMonths = item.months ?: 0,
            trigger = item.trigger,
            usesAuxMeter = onAux,
            auxInterval = if (onAux) 0.0 else secondInterval(item, vehicle),
        )
    }

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

    /** Retires it, or restores it; restoring clears a sale. */
    fun retire(vehicle: Vehicle, retired: Boolean = true) =
        updateVehicle(if (retired) vehicle.copy(isRetired = true) else vehicle.copy(isRetired = false, soldDate = null, soldPrice = 0.0))

    /** Retires it as sold, keeping the date and price with its history. */
    fun markSold(vehicle: Vehicle, on: Instant, price: Double?) =
        updateVehicle(vehicle.copy(isRetired = true, soldDate = on, soldPrice = maxOf(0.0, price ?: 0.0)))

    /** Lays it up: reminders pause until it's back on the road. */
    fun store(vehicle: Vehicle, until: Instant?, now: Instant = Instant.now()) =
        updateVehicle(vehicle.copy(storedSince = vehicle.storedSince ?: now, storedUntil = until))

    /** Back on the road, with fresh readings when there are some. */
    fun returnFromStorage(vehicle: Vehicle, reading: Double?, auxReading: Double? = null, now: Instant = Instant.now()) {
        updateVehicle(vehicle.copy(storedSince = null, storedUntil = null))
        if (reading != null && reading > 0 && vehicle.meter.hasReading) updateReading(vehicle(vehicle.id)!!, reading, now)
        if (auxReading != null && auxReading > 0 && vehicle.hasAuxMeter) updateAuxReading(vehicle(vehicle.id)!!, auxReading, now)
    }

    /**
     * Turns the second meter on, renames it, changes its unit, or (with null)
     * removes it. Jobs the catalog counts in its hours, like generator service,
     * follow, and so do whichever-first figures on it.
     */
    fun setAuxMeter(vehicle: Vehicle, name: String?, unit: MeterUnit? = null) {
        val trimmed = name?.trim()?.ifEmpty { null }
        val wasOn = vehicle.hasAuxMeter
        val unitChanged = unit != null && unit != vehicle.auxMeter
        var next = vehicle.copy(auxMeterName = trimmed, auxMeter = unit?.takeIf { it.hasReading } ?: vehicle.auxMeter)
        var readings = data.readings
        if (trimmed != null && (!wasOn || unitChanged)) {
            next = next.copy(auxReading = 0.0, auxReadingDate = null)
            readings = readings.filterNot { it.vehicleId == vehicle.id && it.isAux }
        }
        val hours = trimmed != null && next.auxMeter == MeterUnit.hours
        var tasks = data.tasks.map { task ->
            if (task.vehicleId != vehicle.id) return@map task
            val item = task.catalogKey?.let { next.catalogItem(it) } ?: return@map task
            var updated = task
            item.auxHours?.let { auxHours ->
                updated = updated.copy(
                    usesAuxMeter = hours,
                    intervalDistance = if (hours) auxHours else item.distanceInterval(next.meter) ?: 0.0,
                    baselineReading = -1.0,
                )
            }
            if (!updated.usesAuxMeter) updated = updated.copy(auxInterval = secondInterval(item, next))
            updated
        }
        if (!hours) {
            tasks = tasks.map { task ->
                if (task.vehicleId == vehicle.id && task.usesAuxMeter && (trimmed == null || unitChanged)) task.copy(usesAuxMeter = false, intervalDistance = 0.0) else task
            }
        }
        if (hours && (!wasOn || unitChanged)) {
            val enabled = tasks.filter { it.vehicleId == vehicle.id && it.isEnabled }.mapNotNull { it.catalogKey }.toSet()
            for (item in next.catalogItems.filter { it.auxHours != null && it.key !in enabled }) {
                val existing = tasks.firstOrNull { it.vehicleId == vehicle.id && it.catalogKey == item.key }
                tasks = if (existing != null) tasks.map { if (it.id == existing.id) it.copy(isEnabled = true) else it } else tasks + makeTask(item, next)
            }
        }
        commit(data.copy(vehicles = data.vehicles.map { if (it.id == vehicle.id) next else it }, tasks = tasks, readings = readings))
    }

    fun updateAuxReading(vehicle: Vehicle, value: Double, at: Instant = Instant.now()) {
        if (!vehicle.hasAuxMeter || value < 0) return
        val next = if (value >= vehicle.auxReading) {
            vehicle.copy(auxReading = value, auxReadingDate = maxOf(vehicle.auxReadingDate ?: Instant.MIN, at))
        } else vehicle
        commit(data.copy(
            vehicles = data.vehicles.map { if (it.id == vehicle.id) next else it },
            readings = data.readings + MeterReading(newId(), vehicle.id, at, value, isAux = true),
        ))
    }

    fun delete(vehicle: Vehicle) {
        data.attachments.filter { it.vehicleId == vehicle.id }.forEach { files.delete(it.file) }
        vehicle.photo?.let(files::delete)
        commit(GarageData(
            vehicles = data.vehicles.filter { it.id != vehicle.id },
            tasks = data.tasks.filter { it.vehicleId != vehicle.id },
            entries = data.entries.filter { it.vehicleId != vehicle.id },
            readings = data.readings.filter { it.vehicleId != vehicle.id },
            attachments = data.attachments.filter { it.vehicleId != vehicle.id },
            valuations = data.valuations.filter { it.vehicleId != vehicle.id },
        ))
    }

    /** Sets or clears the vehicle's photo (JPEG bytes). */
    fun setPhoto(vehicle: Vehicle, jpeg: ByteArray?) {
        vehicle.photo?.let(files::delete)
        val file = jpeg?.let { files.save(newId(), "jpg", it) }
        updateVehicle(vehicle.copy(photo = file))
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
            auxReading = if (vehicle.hasAuxMeter) draft.auxReading ?: -1.0 else -1.0,
            fuelPartial = editing?.fuelPartial ?: false,
        )
        val reading = draft.reading
        var nextVehicle = if (reading != null && reading > vehicle.reading && draft.date <= now) {
            vehicle.copy(reading = reading, readingDate = draft.date)
        } else vehicle
        val aux = draft.auxReading
        if (vehicle.hasAuxMeter && aux != null && aux > vehicle.auxReading) nextVehicle = nextVehicle.copy(auxReading = aux, auxReadingDate = draft.date)
        val added = draft.photos.mapIndexed { index, bytes ->
            val id = newId()
            Attachment(id, vehicle.id, now.plusMillis(index.toLong()), "photo", files.save(id, "jpg", bytes), entryId = entry.id)
        } + draft.files.mapIndexed { index, (name, bytes) ->
            makeDocument(name, bytes, vehicle, now.plusMillis((draft.photos.size + index).toLong())).copy(entryId = entry.id)
        }
        val entries = if (editing != null) data.entries.map { if (it.id == editing.id) entry else it } else data.entries + entry
        commit(data.copy(
            entries = entries,
            vehicles = data.vehicles.map { if (it.id == vehicle.id) nextVehicle else it },
            attachments = data.attachments + added,
        ))
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

    fun delete(entry: ServiceEntry) {
        data.attachments.filter { it.entryId == entry.id }.forEach { files.delete(it.file) }
        commit(data.copy(entries = data.entries.filter { it.id != entry.id }, attachments = data.attachments.filter { it.entryId != entry.id }))
    }

    // MARK: - Documents

    /** A file kept against a vehicle or a visit: PDFs stay PDFs, images are expected already scaled to JPEG. */
    fun makeDocument(name: String, bytes: ByteArray, vehicle: Vehicle, now: Instant = Instant.now()): Attachment {
        val isPDF = isPDF(bytes)
        val id = newId()
        return Attachment(id, vehicle.id, now, if (isPDF) "pdf" else "photo", files.save(id, if (isPDF) "pdf" else "jpg", bytes), name.trim().ifEmpty { null })
    }

    fun addDocument(name: String, bytes: ByteArray, vehicle: Vehicle, now: Instant = Instant.now()): Attachment {
        val document = makeDocument(name, bytes, vehicle, now)
        commit(data.copy(attachments = data.attachments + document))
        return document
    }

    fun rename(attachment: Attachment, name: String) {
        commit(data.copy(attachments = data.attachments.map { if (it.id == attachment.id) it.copy(name = name.trim().ifEmpty { null }) else it }))
    }

    fun delete(attachment: Attachment) {
        files.delete(attachment.file)
        commit(data.copy(attachments = data.attachments.filter { it.id != attachment.id }))
    }

    // MARK: - Import

    data class ImportOutcome(val added: Int = 0, val duplicates: Int = 0, val readings: Int = 0, val fillUps: Int = 0, val jobsUpdated: Int = 0)

    /**
     * Adds rows from another app's export to one vehicle. Rows already in the
     * log (same day, same work, same cost) are skipped, so importing twice is harmless.
     */
    fun importHistory(rows: List<ServiceImport.Row>, vehicle: Vehicle, keepFillUps: Boolean = true, now: Instant = Instant.now()): ImportOutcome {
        fun day(date: Instant) = date.atZone(zone()).toLocalDate().toEpochDay()
        fun dayKey(date: Instant, title: String) = "${day(date)}|${title.lowercase().trim()}"
        // Front and rear brakes on one day at different prices are two visits.
        fun serviceKey(date: Instant, title: String, cost: Double) = dayKey(date, "$title|${Math.round(cost * 100)}")
        val existing = entries(vehicle).map { entry ->
            if (entry.kind == EntryKind.fuel) dayKey(entry.date, "${EntryKind.fuel.title}|${entry.reading.toLong()}") else serviceKey(entry.date, entry.title, entry.cost)
        }.toMutableSet()
        val readingDays = readings(vehicle).map { "${day(it.date)}|${it.value.toLong()}" }.toMutableSet()
        val touched = mutableSetOf<String>()
        var highest: Pair<Double, Instant>? = null
        val newEntries = mutableListOf<ServiceEntry>()
        val newReadings = mutableListOf<MeterReading>()
        var outcome = ImportOutcome()

        for (row in rows) {
            val reading = row.reading?.takeIf { vehicle.meter.hasReading }?.let { (row.unit ?: vehicle.meter).convert(it, vehicle.meter) }
            if (reading != null && reading > (highest?.first ?: -1.0)) highest = reading to row.date
            if (row.isFillUp && keepFillUps && (row.volume != null || row.cost > 0)) {
                // A real fill-up, volume and price and all, so economy works from day one.
                if (!existing.add(dayKey(row.date, "${EntryKind.fuel.title}|${(reading ?: -1.0).toLong()}"))) {
                    outcome = outcome.copy(duplicates = outcome.duplicates + 1)
                    continue
                }
                val unit = row.volumeUnit ?: FuelUnit.current()
                val (volume, unitPrice, total) = completedPump(row.volume, row.unitPrice, row.cost.takeIf { it > 0 })
                newEntries += ServiceEntry(
                    id = newId(), vehicleId = vehicle.id, createdAt = now, date = row.date, reading = reading ?: -1.0,
                    title = EntryKind.fuel.title, kind = EntryKind.fuel, cost = total ?: 0.0, shop = row.shop, notes = row.notes,
                    fuelVolume = volume?.let(unit::toLiters) ?: 0.0, fuelUnitPrice = unitPrice?.let(unit::toPerLiter) ?: 0.0,
                    fuelPartial = row.partial,
                )
                outcome = outcome.copy(fillUps = outcome.fillUps + 1)
                continue
            }
            if (row.isFillUp) {
                if (!keepFillUps || reading == null) continue
                if (!readingDays.add("${day(row.date)}|${reading.toLong()}")) continue
                newReadings += MeterReading(newId(), vehicle.id, row.date, reading)
                outcome = outcome.copy(readings = outcome.readings + 1)
                continue
            }
            val taskIds = matchingTasks(row.work, vehicle)
            val title = row.work.ifEmpty { if (taskIds.isEmpty()) "Service" else title(taskIds, vehicle) }
            if (!existing.add(serviceKey(row.date, title, row.cost))) {
                outcome = outcome.copy(duplicates = outcome.duplicates + 1)
                continue
            }
            newEntries += ServiceEntry(
                id = newId(), vehicleId = vehicle.id, createdAt = now, date = row.date, reading = reading ?: -1.0, title = title,
                taskIds = taskIds, cost = row.cost, shop = if (row.isDIY) null else row.shop, isDIY = row.isDIY, notes = row.notes, kind = row.kind,
            )
            touched += taskIds
            outcome = outcome.copy(added = outcome.added + 1)
        }
        var next = vehicle
        highest?.let { (value, date) ->
            if (value > vehicle.reading) next = vehicle.copy(reading = value, readingDate = maxOf(vehicle.readingDate ?: Instant.MIN, date))
        }
        commit(data.copy(
            vehicles = data.vehicles.map { if (it.id == vehicle.id) next else it },
            entries = data.entries + newEntries,
            readings = data.readings + newReadings,
        ))
        return outcome.copy(jobsUpdated = touched.size)
    }

    /** Schedule items a line of imported work covers: by catalog job, then by a custom item's own name. */
    fun matchingTasks(work: String, vehicle: Vehicle): List<String> {
        val keys = ServiceImport.catalogKeys(work)
        val lower = work.lowercase()
        return enabledTasks(vehicle).filter { task ->
            val key = task.catalogKey
            if (key != null) key in keys else task.name.lowercase().let { it.length > 3 && lower.contains(it) }
        }.map { it.id }
    }

    // MARK: - Value

    fun addValuation(amount: Double, source: String, kind: ValuationKind, vehicle: Vehicle, at: Instant = Instant.now()): Valuation {
        val valuation = Valuation(newId(), vehicle.id, at, amount, source.trim().ifEmpty { null }, kind)
        commit(data.copy(valuations = data.valuations + valuation))
        return valuation
    }

    fun delete(valuation: Valuation) = commit(data.copy(valuations = data.valuations.filter { it.id != valuation.id }))

    /** Restores a whole log, used by tests and the debug seed. */
    fun replaceAll(next: GarageData) = commit(next)

    companion object {
        /** The pump's third figure from the other two, rounded like `PumpReader.completed`. */
        fun completedPump(volume: Double?, unitPrice: Double?, total: Double?): Triple<Double?, Double?, Double?> = when {
            volume != null && unitPrice != null && total == null -> Triple(volume, unitPrice, swiftRound(volume * unitPrice * 100) / 100)
            volume != null && unitPrice == null && total != null && volume > 0 -> Triple(volume, swiftRound(total / volume * 1_000) / 1_000, total)
            volume == null && unitPrice != null && total != null && unitPrice > 0 -> Triple(swiftRound(total / unitPrice * 1_000) / 1_000, unitPrice, total)
            else -> Triple(volume, unitPrice, total)
        }

        fun isPDF(bytes: ByteArray): Boolean = bytes.size >= 4 && String(bytes, 0, 4, Charsets.US_ASCII) == "%PDF"

        /**
         * A catalog job's figure on the second meter when that meter reads a
         * different unit from the main one: a UTV's 1,000 miles beside its 100 hours.
         */
        fun secondInterval(item: CatalogItem, vehicle: Vehicle): Double {
            if (!vehicle.hasAuxMeter || vehicle.auxMeter == vehicle.meter || vehicle.auxMeter.convert(1.0, vehicle.meter) != null) return 0.0
            return item.distanceInterval(vehicle.auxMeter) ?: 0.0
        }

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
                    "",
                    if (fuel && entry.fuelPartial) "Yes" else "",
                    "", "",
                    if (entry.hasAuxReading) Math.round(entry.auxReading).toString() else "",
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
