package com.jackwallner.keyring.data

import com.jackwallner.keyring.model.Powertrain
import com.jackwallner.keyring.model.VehicleKind
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

data class DecodedVIN(
    val year: Int?,
    val make: String,
    val model: String,
    val trim: String,
    val kind: VehicleKind?,
    val powertrain: Powertrain?,
    val engine: String,
    val drive: String,
    val body: String,
) {
    /** A short line for confirmation: "3.5L V6 · 4WD · Pickup". */
    val summary: String get() = listOf(engine, drive, body).filter { it.isNotEmpty() }.joinToString(" · ")
}

data class Recall(
    val campaign: String,
    val component: String,
    val summary: String,
    val consequence: String,
    val remedy: String,
    val reported: LocalDate?,
    val parkIt: Boolean,
    val parkOutside: Boolean,
) {
    val componentTitle: String
        get() = component.split(":").first().lowercase(Locale.US)
            .split(" ").joinToString(" ") { word -> word.replaceFirstChar { it.titlecase(Locale.US) } }
            .replace("Abs", "ABS")

    val nhtsaUrl: String get() = "https://www.nhtsa.gov/recalls?nhtsaId=$campaign"
}

enum class LookupError(val message: String) {
    INVALID_VIN("A VIN is 17 letters and numbers, with no I, O or Q. Check it against the windshield or door sticker."),
    OFFLINE("Couldn't reach NHTSA. Check your connection and try again."),
    NOT_FOUND("NHTSA didn't recognize that VIN. You can fill in the details by hand."),
}

class LookupException(val error: LookupError) : Exception(error.message)

/**
 * The two free U.S. government lookups, ported from `NHTSAClient.swift`:
 * decoding a VIN and listing safety recalls. No key, no account; nothing
 * about the owner is sent beyond the VIN or the year, make and model.
 */
object NHTSAClient {
    /** VINs exclude I, O and Q so they can't be mistaken for 1 and 0. */
    fun normalizedVIN(text: String): String? {
        val cleaned = text.uppercase(Locale.US).filter { it.isLetterOrDigit() }
        if (cleaned.length != 17 || cleaned.any { it in "IOQ" }) return null
        return cleaned
    }

    suspend fun decode(vinText: String): DecodedVIN {
        val vin = normalizedVIN(vinText) ?: throw LookupException(LookupError.INVALID_VIN)
        val body = fetch("https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/$vin?format=json")
        return parseDecode(body) ?: throw LookupException(LookupError.NOT_FOUND)
    }

    fun parseDecode(text: String): DecodedVIN? {
        val row = runCatching { JSONObject(text).getJSONArray("Results").getJSONObject(0) }.getOrNull() ?: return null
        fun value(key: String): String = if (row.has(key) && !row.isNull(key)) row.optString(key).trim() else ""
        val make = value("Make").lowercase(Locale.getDefault()).split(" ")
            .joinToString(" ") { w -> w.replaceFirstChar { it.titlecase(Locale.getDefault()) } }
        val model = value("Model")
        if (make.isEmpty() && model.isEmpty()) return null

        val fuel = value("FuelTypePrimary").lowercase(Locale.US)
        val electrification = value("ElectrificationLevel").lowercase(Locale.US)
        val powertrain = when {
            "bev" in electrification || fuel == "electric" -> Powertrain.electric
            "phev" in electrification -> Powertrain.plugInHybrid
            "hev" in electrification -> Powertrain.hybrid
            "diesel" in fuel -> Powertrain.diesel
            "gasoline" in fuel -> Powertrain.gasoline
            else -> null
        }
        val type = value("VehicleType").lowercase(Locale.US)
        val body = value("BodyClass")
        val lowerBody = body.lowercase(Locale.US)
        val kind = when {
            "motorcycle" in type -> VehicleKind.motorcycle
            "trailer" in type -> VehicleKind.trailer
            "incomplete" in type || "motorhome" in lowerBody -> VehicleKind.rv
            "truck" in type && "pickup" in lowerBody -> VehicleKind.truck
            "van" in lowerBody -> VehicleKind.van
            "sport utility" in lowerBody || "multipurpose" in type -> VehicleKind.suv
            "passenger car" in type -> VehicleKind.car
            "truck" in type -> VehicleKind.truck
            else -> null
        }
        var engine = ""
        val liters = value("DisplacementL").toDoubleOrNull()
        if (liters != null && liters > 0) {
            engine = "%.1fL".format(Locale.US, liters)
            val cylinders = value("EngineCylinders").toIntOrNull()
            if (cylinders != null && cylinders > 0) engine += if (cylinders <= 5) " $cylinders-cyl" else " V$cylinders"
        } else if (powertrain == Powertrain.electric) {
            engine = "Electric"
        }
        return DecodedVIN(
            year = value("ModelYear").toIntOrNull(),
            make = make, model = model, trim = value("Trim"), kind = kind, powertrain = powertrain,
            engine = engine, drive = value("DriveType").split("/").first(), body = body,
        )
    }

    suspend fun recalls(year: Int, make: String, model: String): List<Recall> {
        fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
        val body = fetch("https://api.nhtsa.gov/recalls/recallsByVehicle?make=${enc(make)}&model=${enc(model)}&modelYear=$year")
        return parseRecalls(body)
    }

    const val USER_AGENT = "VehicleMaintenanceLog/1.0 (Android)"

    private val reportedFormat = DateTimeFormatter.ofPattern("dd/MM/yyyy", Locale.US)

    fun parseRecalls(text: String): List<Recall> {
        val rows = runCatching { JSONObject(text).getJSONArray("results") }.getOrNull() ?: return emptyList()
        val seen = mutableSetOf<String>()
        return (0 until rows.length()).mapNotNull { index ->
            val row = rows.optJSONObject(index) ?: return@mapNotNull null
            fun s(key: String) = if (row.has(key) && !row.isNull(key)) row.optString(key) else null
            val campaign = s("NHTSACampaignNumber") ?: return@mapNotNull null
            if (!seen.add(campaign)) return@mapNotNull null
            Recall(
                campaign = campaign,
                component = s("Component").orEmpty(),
                summary = s("Summary").orEmpty().trim(),
                consequence = s("Consequence").orEmpty().trim(),
                remedy = s("Remedy").orEmpty().trim(),
                reported = s("ReportReceivedDate")?.let { runCatching { LocalDate.parse(it, reportedFormat) }.getOrNull() },
                parkIt = row.optBoolean("parkIt", false),
                parkOutside = row.optBoolean("parkOutSide", false),
            )
        }.sortedByDescending { it.reported ?: LocalDate.MIN }
    }

    private suspend fun fetch(url: String): String = withContext(Dispatchers.IO) {
        try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 15_000
            connection.readTimeout = 20_000
            connection.setRequestProperty("Accept", "application/json")
            // api.nhtsa.gov answers 403 to Android's default Dalvik user agent.
            connection.setRequestProperty("User-Agent", USER_AGENT)
            try {
                if (connection.responseCode !in 200..299) throw IOException("HTTP ${connection.responseCode}")
                connection.inputStream.bufferedReader().use { it.readText() }
            } finally {
                connection.disconnect()
            }
        } catch (error: IOException) {
            throw LookupException(LookupError.OFFLINE)
        }
    }
}
