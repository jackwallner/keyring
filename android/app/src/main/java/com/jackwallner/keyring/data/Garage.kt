package com.jackwallner.keyring.data

import com.jackwallner.keyring.catalog.CatalogItem
import com.jackwallner.keyring.catalog.MaintenanceCatalog
import com.jackwallner.keyring.model.DueResult
import com.jackwallner.keyring.model.EntryKind
import com.jackwallner.keyring.model.FinalDrive
import com.jackwallner.keyring.model.MeterUnit
import com.jackwallner.keyring.model.Powertrain
import com.jackwallner.keyring.model.UsageEvent
import com.jackwallner.keyring.model.VehicleKind
import com.jackwallner.keyring.model.VehicleTint
import com.jackwallner.keyring.model.VehicleTrait
import java.time.Instant

/** The fields of the iOS Core Data `Vehicle` this port carries. Raw strings match iOS. */
data class Vehicle(
    val id: String,
    val createdAt: Instant,
    val kind: VehicleKind,
    val powertrain: Powertrain,
    val meter: MeterUnit,
    val nickname: String? = null,
    val year: Int = 0,
    val make: String? = null,
    val model: String? = null,
    val trim: String? = null,
    val vin: String? = null,
    val plate: String? = null,
    val reading: Double = 0.0,
    val readingDate: Instant? = null,
    val tint: VehicleTint = VehicleTint.defaultTint(kind),
    val notes: String? = null,
    val sortIndex: Int = 0,
    val isRetired: Boolean = false,
    val yearlyUse: Double = 0.0,
    val traits: Set<VehicleTrait> = emptySet(),
    val drive: FinalDrive? = null,
    /** Set when the owner marks it sold rather than just retired. */
    val soldDate: Instant? = null,
    val soldPrice: Double = 0.0,
    /** A second meter, such as an RV's generator hours. Null when there's none. */
    val auxMeterName: String? = null,
    /** The second meter's unit; hours unless it reads distance. */
    val auxMeter: MeterUnit = MeterUnit.hours,
    val auxReading: Double = 0.0,
    val auxReadingDate: Instant? = null,
    /** Laid up for the season: reminders pause and the meter isn't assumed to move. */
    val storedSince: Instant? = null,
    val storedUntil: Instant? = null,
    /** File name of the vehicle's photo in app storage. */
    val photo: String? = null,
) {
    val hasAuxMeter: Boolean get() = !auxMeterName.isNullOrEmpty()

    val isStored: Boolean get() = storedSince != null

    /** "Generator hours", "Track hours", "Trail miles". */
    val auxMeterLabel: String
        get() {
            val name = auxMeterName ?: "Second meter"
            val unit = if (auxMeter == MeterUnit.hours) "hours" else auxMeter.title.lowercase()
            return if (name.lowercase().endsWith(unit)) name else "$name $unit"
        }

    /** "2019 Toyota Tacoma", or whatever parts are known. */
    val descriptor: String
        get() = listOfNotNull(if (year > 0) year.toString() else null, make, model)
            .map { it.trim() }.filter { it.isNotEmpty() }.joinToString(" ")

    /** The name people call it by: the nickname, else the model, else the make, else the kind. */
    val displayName: String
        get() = nickname?.takeIf { it.isNotBlank() } ?: model?.takeIf { it.isNotEmpty() } ?: make?.takeIf { it.isNotEmpty() } ?: kind.title

    val makeAndModel: String get() = listOfNotNull(make, model).filter { it.isNotEmpty() }.joinToString(" ")

    val catalogItems: List<CatalogItem>
        get() = MaintenanceCatalog.items(kind, powertrain, year, traits, drive)

    fun catalogItem(key: String): CatalogItem? = catalogItems.firstOrNull { it.key == key }
}

data class MaintenanceTask(
    val id: String,
    val vehicleId: String,
    val createdAt: Instant,
    val catalogKey: String? = null,
    val name: String,
    val symbol: String = "wrench.adjustable",
    val intervalDistance: Double = 0.0,
    val intervalMonths: Int = 0,
    val baselineDate: Instant? = null,
    /** -1 = unknown, like iOS. */
    val baselineReading: Double = -1.0,
    val isEnabled: Boolean = true,
    val notes: String? = null,
    val trigger: UsageEvent? = null,
    /** Counted on the vehicle's second meter instead of its main one. */
    val usesAuxMeter: Boolean = false,
    /** A whichever-first interval on the second meter (a UTV's oil at 100 hours or 1,000 miles); 0 = none. */
    val auxInterval: Double = 0.0,
)

data class ServiceEntry(
    val id: String,
    val vehicleId: String,
    val createdAt: Instant,
    val date: Instant,
    /** -1 = no reading, like iOS. */
    val reading: Double = -1.0,
    val title: String,
    val taskIds: List<String> = emptyList(),
    val cost: Double = 0.0,
    val shop: String? = null,
    val isDIY: Boolean = false,
    val notes: String? = null,
    val kind: EntryKind = EntryKind.service,
    val recallCampaign: String? = null,
    val fuelVolume: Double = 0.0,
    val fuelUnitPrice: Double = 0.0,
    val event: UsageEvent? = null,
    /** The second meter that day; -1 when not given. */
    val auxReading: Double = -1.0,
    /** A top-up that didn't fill the tank. */
    val fuelPartial: Boolean = false,
) {
    val hasReading: Boolean get() = reading >= 0
    val hasAuxReading: Boolean get() = auxReading >= 0
}

data class MeterReading(val id: String, val vehicleId: String, val date: Instant, val value: Double, val isAux: Boolean = false)

/** A photo, receipt or document. Kept with a visit (`entryId`) or with the vehicle itself (a document). */
data class Attachment(
    val id: String,
    val vehicleId: String,
    val createdAt: Instant,
    /** "photo", "receipt" or "pdf", the iOS raw values. */
    val kind: String,
    /** File name in app storage. */
    val file: String,
    val name: String? = null,
    val entryId: String? = null,
) {
    val isPDF: Boolean get() = kind == "pdf"
    val isDocument: Boolean get() = entryId == null
}

@Suppress("EnumEntryName")
enum class ValuationKind(val title: String) {
    estimate("Estimate"), appraisal("Appraisal"), agreedValue("Agreed value (insurance)"), offer("Offer");

    companion object {
        fun fromRaw(raw: String?): ValuationKind = entries.firstOrNull { it.name == raw } ?: estimate
    }
}

/** A figure the owner noted: a quote, an offer, an appraisal. Never a third-party value shown as the app's own. */
data class Valuation(val id: String, val vehicleId: String, val date: Instant, val amount: Double, val source: String? = null, val kind: ValuationKind = ValuationKind.estimate)

/** The whole log. Immutable; the store swaps it whole and persists it as one JSON document. */
data class GarageData(
    val vehicles: List<Vehicle> = emptyList(),
    val tasks: List<MaintenanceTask> = emptyList(),
    val entries: List<ServiceEntry> = emptyList(),
    val readings: List<MeterReading> = emptyList(),
    val attachments: List<Attachment> = emptyList(),
    val valuations: List<Valuation> = emptyList(),
)

/** One job on one vehicle, with when it comes due. */
data class TaskDue(
    val task: MaintenanceTask,
    val result: DueResult,
    val lastDate: Instant?,
    val lastReading: Double?,
    val meter: MeterUnit,
    val currentReading: Double,
    val pendingEvent: Instant? = null,
    /** Counted on the second meter. */
    val usesAuxMeter: Boolean = false,
    /** The whichever-first figure on the second meter; 0 = none. */
    val secondInterval: Double = 0.0,
    val secondMeter: MeterUnit = MeterUnit.hours,
) {
    val name: String get() = task.name
    val hasInterval: Boolean get() = task.intervalMonths > 0 || (task.intervalDistance > 0 && meter.hasReading)
}

/** What a new vehicle starts with. */
data class NewVehicle(
    val kind: VehicleKind = VehicleKind.car,
    val powertrain: Powertrain = kind.defaultPowertrain,
    val meter: MeterUnit = kind.defaultMeter,
    val year: Int = 0,
    val make: String = "",
    val model: String = "",
    val trim: String = "",
    val nickname: String = "",
    val vin: String = "",
    val plate: String = "",
    val reading: Double = 0.0,
    val yearlyUse: Double = 0.0,
    val traits: Set<VehicleTrait> = emptySet(),
    val drive: FinalDrive? = null,
    val tint: VehicleTint? = null,
    val auxMeterName: String = "",
    val auxMeter: MeterUnit = MeterUnit.hours,
    /** Catalog key to the date it was last done. */
    val lastDone: Map<String, Instant> = emptyMap(),
)

data class ServiceDraft(
    val kind: EntryKind = EntryKind.service,
    val date: Instant = Instant.now(),
    val reading: Double? = null,
    val taskIds: List<String> = emptyList(),
    val title: String = "",
    val cost: Double = 0.0,
    val shop: String = "",
    val isDIY: Boolean = false,
    val notes: String = "",
    val recallCampaign: String? = null,
    val fuelVolume: Double = 0.0,
    val fuelUnitPrice: Double = 0.0,
    val event: UsageEvent? = null,
    val auxReading: Double? = null,
    /** Photos of the work, already scaled to JPEG. */
    val photos: List<ByteArray> = emptyList(),
    /** Files picked from storage: (name, bytes), PDFs or images. */
    val files: List<Pair<String, ByteArray>> = emptyList(),
)

/** Fill-ups are stored in liters like iOS; the reader sees their own unit. */
enum class FuelUnit(val title: String, val short: String, val liters: Double) {
    GALLONS("Gallons", "gal", 3.785411784), LITERS("Liters", "L", 1.0);

    fun fromLiters(value: Double) = value / liters
    fun toLiters(value: Double) = value * liters
    fun fromPerLiter(price: Double) = price * liters
    fun toPerLiter(price: Double) = price / liters

    companion object {
        fun current(region: String? = java.util.Locale.getDefault().country): FuelUnit =
            if (region in setOf("US", "LR", "MM")) GALLONS else LITERS
    }
}
