package com.jackwallner.keyring

import com.jackwallner.keyring.catalog.CatalogItem
import com.jackwallner.keyring.catalog.MaintenanceCatalog
import com.jackwallner.keyring.model.FinalDrive
import com.jackwallner.keyring.model.VehicleKind
import com.jackwallner.keyring.model.VehicleTrait
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Kotlin catalog against the Swift source. `scripts/export-android-catalog.py`
 * extracts every `CatalogItem(...)` literal from MaintenanceCatalog.swift; this
 * test computes the Kotlin catalog over every kind, powertrain, trait, drive,
 * classic year and region and checks the two agree item for item.
 */
class CatalogParityTest {
    private data class Literal(val fields: JSONObject) {
        val key: String get() = fields.getString("key")
        val name: String? get() = fields.optString("name").takeIf { fields.has("name") }
        val unresolved: Set<String>
            get() = fields.getJSONArray("unresolved").let { a -> (0 until a.length()).map { a.getString(it) }.toSet() }

        /** Every field the Swift literal spells out, compared to the computed Kotlin item. */
        fun mismatches(item: CatalogItem): List<String> {
            val problems = mutableListOf<String>()
            fun check(field: String, swift: Any?, kotlin: Any?) {
                if (field in unresolved) return
                if (swift != kotlin) problems.add("$field: swift=$swift kotlin=$kotlin")
            }
            fun num(field: String): Double? = if (fields.has(field)) fields.getDouble(field) else null
            check("name", name, item.name)
            check("detail", fields.optString("detail"), item.detail)
            check("symbol", fields.optString("symbol"), item.symbol)
            check("miles", num("miles"), item.miles)
            check("hours", num("hours"), item.hours)
            check("months", num("months")?.toInt(), item.months)
            check("auxHours", num("auxHours"), item.auxHours)
            check("calendarMonths", fields.optBoolean("calendarMonths", false), item.calendarMonths)
            check("trigger", fields.optString("trigger").ifEmpty { null }, item.trigger?.name)
            check("isCore", fields.optBoolean("isCore", true), item.isCore)
            check("difficulty", fields.optString("difficulty").ifEmpty { "diy" }, item.difficulty.name)
            check("source", fields.optString("source").ifEmpty { null }, item.source)
            val gear = fields.optJSONArray("gear")?.let { a -> (0 until a.length()).map { a.getJSONObject(it).let { g -> g.getString("title") to g.getString("query") } } }.orEmpty()
            check("gear", gear, item.gear.map { it.title to it.query })
            return problems
        }
    }

    private val literals: List<Literal> by lazy {
        val text = javaClass.classLoader!!.getResource("catalog_literals_swift.json")!!.readText()
        val items = JSONObject(text).getJSONArray("items")
        (0 until items.length()).map { Literal(items.getJSONObject(it)) }
    }

    private fun matrix(tuned: Boolean): List<CatalogItem> {
        val out = mutableListOf<CatalogItem>()
        val regions = listOf("US", "CA", "GB", "IE", "AU", "FR", null)
        for (kind in VehicleKind.entries) for (powertrain in kind.powertrainChoices) for (region in regions) {
            out += MaintenanceCatalog.items(kind, powertrain, region = region)
            if (!tuned) continue
            out += MaintenanceCatalog.items(kind, powertrain, year = 1967, region = region)
            for (trait in VehicleTrait.entries) out += MaintenanceCatalog.items(kind, powertrain, traits = setOf(trait), region = region)
            for (drive in FinalDrive.entries) out += MaintenanceCatalog.items(kind, powertrain, drive = drive, region = region)
        }
        return out
    }

    @Test fun swiftSourceHasTheExpectedLiteralCount() {
        // 161 literals on 2026-10-20; a change here means the Swift catalog moved and the Kotlin port must follow.
        assertEquals(169, literals.size)
    }

    @Test fun everySwiftLiteralIsReachableOnAndroid() {
        val computed = matrix(tuned = true).map { it.key to it.name }.toSet()
        val missing = literals.filter { it.name != null && "name" !in it.unresolved }
            .filter { (it.key to it.name) !in computed }.map { "${it.key}/${it.name}" }
        assertEquals("Swift catalog items missing from Kotlin", emptyList<String>(), missing)
    }

    @Test fun everyUntunedKotlinItemEqualsItsSwiftLiteral() {
        val problems = mutableListOf<String>()
        for (item in matrix(tuned = false).distinct()) {
            val candidates = literals.filter { it.key == item.key && ("name" in it.unresolved || it.name == item.name) }
            if (candidates.isEmpty()) {
                problems.add("${item.key}/${item.name}: no Swift literal")
                continue
            }
            val best = candidates.map { it.mismatches(item) }.minByOrNull { it.size }!!
            // The winter swap's isCore and the inspection's name are computed in Swift too; checked in CatalogTest.
            if (best.isNotEmpty()) problems.add("${item.key}/${item.name}: $best")
        }
        assertEquals(emptyList<String>(), problems)
    }

    @Test fun noKotlinItemIsInvented() {
        val known = literals.map { it.key }.toSet()
        val invented = matrix(tuned = true).map { it.key }.toSet() - known
        assertTrue("Kotlin-only catalog keys: $invented", invented.isEmpty())
    }

    @Test fun matrixCoversEveryKindAndPowertrain() {
        val combos = VehicleKind.entries.sumOf { it.powertrainChoices.size }
        assertEquals(61, combos)
        assertEquals(literals.map { it.key }.toSet(), matrix(tuned = true).map { it.key }.toSet())
    }
}
