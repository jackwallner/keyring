package com.jackwallner.keyring.data

import com.jackwallner.keyring.model.EntryKind
import com.jackwallner.keyring.model.MeterUnit
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.chrono.IsoChronology
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeFormatterBuilder
import java.time.format.FormatStyle
import java.time.format.ResolverStyle
import java.time.temporal.ChronoField
import java.util.Locale

/**
 * Reads a service history exported from another app or a spreadsheet: Fuelly,
 * Drivvo, Simply Auto, aCar, a Vehicle Maintenance Log export, or any CSV with
 * a date column. A port of `Shared/Export/ServiceImport.swift`; pure, so JVM
 * tests feed it files.
 */
object ServiceImport {
    @Suppress("EnumEntryName")
    enum class Field(val title: String, val names: List<String>) {
        date("Date", listOf("date", "servicedate", "fuelupdate", "refuelingdate", "refuellingdate", "dateperformed", "performedon",
            "completed", "completedon", "datetime", "day", "when", "fecha", "datum", "data")),
        odometer("Odometer", listOf("odometer", "odo", "odometerreading", "odometermi", "odometerkm", "odometermiles", "odometerkilometers",
            "odometerkilometres", "mileage", "kilometrage", "km", "kms", "kilometers", "kilometres", "hours",
            "enginehours", "hobbs", "tach", "meter", "reading", "totalmiles", "currentmileage")),
        work("Work done", listOf("work", "service", "services", "servicetype", "servicetypes", "servicesperformed", "workdone", "servicename",
            "maintenance", "task", "tasks", "job", "jobs", "item", "items", "title", "description", "type",
            "expensetype", "expense", "category", "repair", "parts")),
        cost("Cost", listOf("cost", "totalcost", "total", "amount", "totalamount", "totalprice", "price", "paid", "charge", "value")),
        shop("Shop", listOf("shop", "place", "location", "vendor", "garage", "station", "servicecenter", "provider", "where",
            "mechanic", "dealer", "business", "store", "performedby", "servicedby")),
        notes("Notes", listOf("notes", "note", "comments", "comment", "memo", "remarks", "details", "description")),
        vehicle("Vehicle", listOf("vehicle", "car", "carname", "vehiclename", "vehiclenickname", "nickname", "auto", "bike", "boat")),
        kind("Type", listOf("entrytype", "kind")),
        diy("DIY", listOf("diy", "selfservice", "didityourself")),
        loggedBy("Logged by", listOf("loggedby", "driver", "enteredby", "user")),
        unit("Unit", listOf("unit", "units", "odometerunit", "distanceunit")),
        year("Year", listOf("year", "modelyear")),
        make("Make", listOf("make", "manufacturer", "brand")),
        model("Model", listOf("model")),
        volume("Fuel", listOf("gallons", "gal", "liters", "litres", "volume", "quantity", "qty", "fuelvolume", "fuelamount", "amountoffuel")),
        volumeUnit("Fuel unit", listOf("fuelunit", "volumeunit")),
        unitPrice("Price per unit", listOf("pricepergallon", "priceperliter", "priceperlitre", "priceperunit", "unitprice", "ppg", "fuelprice",
            "pricegal", "pricel", "priceperl", "pricelitre", "priceliter")),
        grade("Grade", listOf("fueltype", "fuelgrade", "grade", "octane")),
        partial("Partial fill", listOf("partialfuelup", "partialfill", "partial", "partialrefuel", "partialrefueling"));

        companion object {
            /** The columns a person might need to fix by hand. */
            val editable = listOf(date, odometer, work, cost, shop, notes, vehicle)
        }
    }

    enum class Source(val title: String) {
        KEYRING("a Vehicle Maintenance Log backup"), FUELLY("Fuelly"), DRIVVO("Drivvo"), SIMPLY_AUTO("Simply Auto"), SPREADSHEET("your spreadsheet")
    }

    enum class Role { SERVICE, FUEL, EXPENSE }

    /** One block of rows under one header line. Drivvo and Simply Auto stack fill-ups, services and expenses in one file. */
    data class Table(val id: Int, val title: String?, val headers: List<String>, val rows: List<List<String>>, val mapping: Map<Field, Int>, val role: Role) {
        /** Columns no field reads, such as "Part #". On a service table they're kept in the notes rather than dropped. */
        val extraColumns: List<Int>
            get() {
                if (role != Role.SERVICE) return emptyList()
                val used = mapping.values.toSet()
                return headers.indices.filter { column ->
                    val name = normalize(headers[column])
                    column !in used && name.isNotEmpty() && name !in ignoredHeaders
                }
            }
    }

    /** Columns a backup from this app writes that the log already rebuilds. */
    val ignoredHeaders = setOf("coveredjobs", "fuel", "fuelunit", "priceperunit", "grade", "partialfill", "secondmeter")

    data class Row(
        val id: Int,
        val vehicleName: String,
        val date: Instant,
        val reading: Double?,
        val unit: MeterUnit?,
        val work: String,
        val cost: Double,
        val shop: String?,
        val notes: String?,
        val kind: EntryKind,
        val isDIY: Boolean,
        val loggedBy: String?,
        val isFillUp: Boolean,
        val volume: Double? = null,
        val volumeUnit: FuelUnit? = null,
        val unitPrice: Double? = null,
        val partial: Boolean = false,
        val year: Int? = null,
        val make: String? = null,
        val model: String? = null,
    )

    data class Result(
        val source: Source,
        val tables: List<Table>,
        val services: List<Row>,
        val fillUps: List<Row>,
        /** Insurance, parking, tolls and the like: real costs, not maintenance. */
        val skippedExpenses: Int,
        /** Rows with no date the app could read. */
        val unreadable: Int,
    ) {
        val isEmpty: Boolean get() = services.isEmpty() && fillUps.isEmpty()

        /** Headers of the extra columns kept in notes. */
        val foldedHeaders: List<String>
            get() {
                val seen = mutableListOf<String>()
                for (table in tables) for (column in table.extraColumns) {
                    val header = table.headers[column].trim()
                    if (header !in seen) seen += header
                }
                return seen
            }

        /** Each vehicle named in the file, in order of first appearance, with "" for files that never name one. */
        val vehicleNames: List<String> get() = (services + fillUps).map { it.vehicleName }.distinct()

        /** The table whose columns the person is most likely to want to fix. */
        val mainTable: Table?
            get() = tables.filter { it.role == Role.SERVICE }.maxByOrNull { it.rows.size } ?: tables.maxByOrNull { it.rows.size }
    }

    // MARK: - Parsing

    fun parse(text: String, locale: Locale = Locale.getDefault(), zone: ZoneId = ZoneId.systemDefault(), now: Instant = Instant.now()): Result =
        build(findTables(rows(text)), locale, zone, now)

    /** Rebuilds the rows after the person points a field at another column. */
    fun remap(result: Result, table: Int, field: Field, column: Int?, locale: Locale = Locale.getDefault(), zone: ZoneId = ZoneId.systemDefault()): Result {
        val tables = result.tables.toMutableList()
        val index = tables.indexOfFirst { it.id == table }.takeIf { it >= 0 } ?: return result
        val mapping = tables[index].mapping.filter { (other, value) -> !(value == column && other != field) }.toMutableMap()
        if (column == null) mapping.remove(field) else mapping[field] = column
        tables[index] = tables[index].copy(mapping = mapping)
        return build(tables, locale, zone, Instant.now())
    }

    private fun build(tables: List<Table>, locale: Locale, zone: ZoneId, now: Instant): Result {
        val services = mutableListOf<Row>()
        val fillUps = mutableListOf<Row>()
        var skipped = 0
        var unreadable = 0
        var nextId = 0
        for (table in tables) {
            val dateColumn = table.mapping[Field.date] ?: continue
            if (table.role == Role.EXPENSE) {
                skipped += table.rows.size
                continue
            }
            val dates = DateColumn(table.rows.map { cell(it, dateColumn) }, locale, zone, now)
            val thousandsDot = table.mapping[Field.odometer]?.let { column -> usesDotThousands(table.rows.map { cell(it, column) }) } ?: false
            val headerUnit = table.mapping[Field.odometer]?.let { unitFromHeader(table.headers[it]) }
            for (raw in table.rows) {
                val date = dates.date(cell(raw, dateColumn))
                if (date == null) {
                    if (raw.any { it.isNotBlank() }) unreadable += 1
                    continue
                }
                val value = { field: Field -> table.mapping[field]?.let { cell(raw, it).trim() } ?: "" }
                val work = value(Field.work)
                val rowKind = kind(value(Field.kind), work)
                if (table.role == Role.SERVICE && rowKind != EntryKind.fuel && isExpense(work)) {
                    skipped += 1
                    continue
                }
                val reading = number(value(Field.odometer), thousandsDot)?.takeIf { it > 0 }
                val isFillUp = table.role == Role.FUEL || rowKind == EntryKind.fuel
                if (!isFillUp && work.isEmpty() && reading == null && number(value(Field.cost)) == null) continue
                var row = Row(
                    id = nextId,
                    vehicleName = value(Field.vehicle),
                    date = date,
                    reading = reading,
                    unit = unit(value(Field.unit)) ?: headerUnit,
                    work = work,
                    cost = maxOf(0.0, number(value(Field.cost)) ?: 0.0),
                    shop = value(Field.shop).ifEmpty { null },
                    notes = notes(value(Field.notes), table.extraColumns.mapNotNull { column ->
                        val text = cell(raw, column).trim()
                        if (text.isEmpty()) null else "${table.headers[column].trim()}: $text"
                    }),
                    kind = if (isFillUp) EntryKind.fuel else rowKind,
                    isDIY = value(Field.diy).lowercase() in yes,
                    loggedBy = value(Field.loggedBy).ifEmpty { null },
                    isFillUp = isFillUp,
                    year = value(Field.year).toIntOrNull()?.takeIf { it in 1900..2100 },
                    make = value(Field.make).ifEmpty { null },
                    model = value(Field.model).ifEmpty { null },
                )
                nextId += 1
                if (isFillUp) {
                    row = fill(row, value, table.mapping[Field.volume]?.let { table.headers[it] })
                    fillUps += row
                } else {
                    services += row
                }
            }
        }
        return Result(source(tables), tables, services.sortedBy { it.date }, fillUps.sortedBy { it.date }, skipped, unreadable)
    }

    private val yes = setOf("yes", "y", "true", "1", "x")

    /** The notes column, then any extra columns, one per line. */
    private fun notes(notes: String, extras: List<String>): String? =
        (listOf(notes).filter { it.isNotEmpty() } + extras).joinToString("\n").ifEmpty { null }

    // MARK: - Tables

    private fun findTables(rows: List<List<String>>): List<Table> {
        val tables = mutableListOf<Table>()
        var index = 0
        var pendingTitle: String? = null
        while (index < rows.size) {
            val row = rows[index]
            val filled = row.map { it.trim() }.filter { it.isNotEmpty() }
            val mapping = headerMapping(row)
            if (mapping != null && mapping[Field.date] != null && mapping.size >= 2) {
                val body = mutableListOf<List<String>>()
                index += 1
                while (index < rows.size) {
                    val next = rows[index]
                    val nextFilled = next.map { it.trim() }.filter { it.isNotEmpty() }
                    if (nextFilled.isEmpty()) {
                        index += 1
                        if (body.isEmpty()) continue else break
                    }
                    val other = headerMapping(next)
                    if (other != null && other[Field.date] != null && other.size >= 2) break
                    if (nextFilled.size == 1 && isSectionTitle(nextFilled[0])) break
                    body += next
                    index += 1
                }
                val table = Table(tables.size, pendingTitle, row, body, mapping, role(pendingTitle, row))
                if (table.rows.isNotEmpty()) tables += table
                pendingTitle = null
                continue
            }
            if (filled.size == 1) pendingTitle = filled[0]
            index += 1
        }
        return tables
    }

    private fun isSectionTitle(text: String): Boolean {
        val lower = text.lowercase()
        return lower.startsWith("#") || (listOf("refuel", "fuel", "service", "expense", "income", "route", "trip", "reminder", "maintenance")
            .any { lower.contains(it) } && lower.length < 40 && lower.none { it.isDigit() })
    }

    fun headerMapping(row: List<String>): Map<Field, Int>? {
        val normalized = row.map(::normalize)
        if (normalized.none { it.isNotEmpty() }) return null
        // A backup from this app maps one to one.
        if (normalized.take(9) == listOf("vehicle", "year", "make", "model", "date", "odometer", "unit", "type", "work")) {
            val mapping = mutableMapOf(Field.vehicle to 0, Field.year to 1, Field.make to 2, Field.model to 3, Field.date to 4,
                Field.odometer to 5, Field.unit to 6, Field.kind to 7, Field.work to 8)
            for ((field, name) in listOf(Field.cost to "cost", Field.shop to "shop", Field.diy to "diy", Field.notes to "notes", Field.loggedBy to "loggedby",
                Field.volume to "fuel", Field.volumeUnit to "fuelunit", Field.unitPrice to "priceperunit", Field.grade to "grade", Field.partial to "partialfill")) {
                val column = normalized.indexOf(name)
                if (column >= 0) mapping[field] = column
            }
            return mapping
        }
        val mapping = mutableMapOf<Field, Int>()
        val used = mutableSetOf<Int>()
        for (field in Field.entries) {
            for (name in field.names) {
                val column = normalized.indices.firstOrNull { normalized[it] == name && it !in used }
                if (column != null) {
                    mapping[field] = column
                    used += column
                    break
                }
            }
        }
        // Looser matches for the two columns that matter most.
        if (mapping[Field.date] == null) {
            normalized.indices.firstOrNull { column ->
                val name = normalized[column]
                column !in used && name.contains("date") && listOf("added", "created", "modified", "due", "next", "updated").none { name.contains(it) }
            }?.let { mapping[Field.date] = it; used += it }
        }
        if (mapping[Field.odometer] == null) {
            normalized.indices.firstOrNull { column ->
                column !in used && (normalized[column].startsWith("odometer") || normalized[column].startsWith("odo") || normalized[column].startsWith("mileage"))
            }?.let { mapping[Field.odometer] = it; used += it }
        }
        // "Miles" is trip distance in fuel logs; only trust it when nothing else could be the odometer.
        if (mapping[Field.odometer] == null && !hasFuelColumns(normalized)) {
            normalized.indexOf("miles").takeIf { it >= 0 }?.let { mapping[Field.odometer] = it }
        }
        return mapping.ifEmpty { null }
    }

    private fun role(title: String?, headers: List<String>): Role {
        val lower = title?.lowercase() ?: ""
        if (listOf("fuel", "refuel", "gas", "fill").any { lower.contains(it) }) return Role.FUEL
        if (listOf("expense", "income", "route", "trip", "reminder").any { lower.contains(it) }) return Role.EXPENSE
        if (listOf("service", "maintenance", "repair").any { lower.contains(it) }) return Role.SERVICE
        return if (hasFuelColumns(headers.map(::normalize))) Role.FUEL else Role.SERVICE
    }

    private fun hasFuelColumns(normalized: List<String>): Boolean {
        val markers = listOf("gallon", "litre", "liter", "volume", "mpg", "l100", "quantity", "fillup", "refuel", "fuelup", "partial", "missed", "kwh")
        return normalized.any { name -> markers.any { name.contains(it) } }
    }

    private fun source(tables: List<Table>): Source {
        val headers = tables.flatMap { it.headers }.map(::normalize).toSet()
        val titles = tables.mapNotNull { it.title }.joinToString(" ").lowercase()
        return when {
            headers.containsAll(listOf("vehicle", "work", "coveredjobs")) -> Source.KEYRING
            "fuelupdate" in headers || "carname" in headers -> Source.FUELLY
            titles.contains("##") || titles.contains("refuelling") -> Source.DRIVVO
            titles.contains("log") && (titles.contains("fuel") || titles.contains("service")) -> Source.SIMPLY_AUTO
            else -> Source.SPREADSHEET
        }
    }

    // MARK: - Cells

    fun normalize(header: String): String = header.lowercase().filter { it.code < 128 && it.isLetterOrDigit() }

    private fun cell(row: List<String>, column: Int): String = if (column < row.size) row[column] else ""

    private val expenseWords = listOf("insurance", "parking", "toll", "fine", "ticket", "loan", "payment", "lease", "tax",
        "car wash", "wash", "fuel", "gas", "fill-up", "fill up", "financing", "membership", "subscription")

    private fun isExpense(work: String): Boolean {
        val lower = work.lowercase().trim()
        if (lower.isEmpty()) return false
        return lower in expenseWords || expenseWords.any { lower == it + "s" }
    }

    /** A fill-up's volume and price. Fuelly's "price" is per gallon, so a small figure beside a volume is the price, not the total. */
    private fun fill(row: Row, value: (Field) -> String, volumeHeader: String?): Row {
        val volume = number(value(Field.volume))?.takeIf { it > 0 }
        var volumeUnit: FuelUnit? = null
        val header = normalize(volumeHeader ?: "")
        if (header.startsWith("gal") || header.contains("gallon")) volumeUnit = FuelUnit.GALLONS
        if (header.startsWith("lit") || header == "l") volumeUnit = FuelUnit.LITERS
        when (normalize(value(Field.volumeUnit))) {
            "gal", "gallon", "gallons" -> volumeUnit = FuelUnit.GALLONS
            "l", "liter", "liters", "litre", "litres" -> volumeUnit = FuelUnit.LITERS
        }
        var unitPrice = number(value(Field.unitPrice))?.takeIf { it > 0 }
        var cost = row.cost
        val unit = volumeUnit ?: FuelUnit.current()
        if (unitPrice == null && volume != null && volume > 1 && cost > 0 && cost <= (if (unit == FuelUnit.GALLONS) 10.0 else 3.0)) {
            unitPrice = cost
            cost = 0.0
        }
        return row.copy(volume = volume, volumeUnit = volumeUnit, unitPrice = unitPrice, cost = cost, partial = value(Field.partial).lowercase() in yes)
    }

    private fun kind(type: String, work: String): EntryKind {
        val lowerType = type.lowercase()
        if (lowerType.contains("fill") || lowerType.contains("fuel")) return EntryKind.fuel
        if (lowerType.contains("recall")) return EntryKind.recall
        if (lowerType.contains("repair")) return EntryKind.repair
        if (lowerType.isNotEmpty() && (lowerType.contains("maint") || lowerType.contains("service"))) return EntryKind.service
        val lower = work.lowercase()
        if (lower.contains("recall")) return EntryKind.recall
        if (lower.contains("repair")) return EntryKind.repair
        return EntryKind.service
    }

    fun unit(text: String): MeterUnit? = when (normalize(text)) {
        "mi", "mile", "miles" -> MeterUnit.miles
        "km", "kms", "kilometer", "kilometers", "kilometre", "kilometres" -> MeterUnit.kilometers
        "hr", "hrs", "hour", "hours", "h" -> MeterUnit.hours
        else -> null
    }

    private fun unitFromHeader(header: String): MeterUnit? {
        val name = normalize(header)
        return when {
            name.endsWith("km") || name.contains("kilomet") -> MeterUnit.kilometers
            name.endsWith("mi") || name.endsWith("miles") -> MeterUnit.miles
            name.contains("hour") || name.contains("hobbs") || name.contains("tach") -> MeterUnit.hours
            else -> null
        }
    }

    /** "1,234.56", "1.234,56", "$45", "45,00 €". With `thousandsDot`, a dot always groups thousands ("45.000"). */
    fun number(raw: String, thousandsDot: Boolean = false): Double? {
        var text = raw.filter { it in "0123456789.," }
        if (text.none { it.isDigit() }) return null
        if (thousandsDot) return text.replace(".", "").replace(",", ".").toDoubleOrNull()
        val dot = text.lastIndexOf('.')
        val comma = text.lastIndexOf(',')
        when {
            dot >= 0 && comma >= 0 -> text = if (dot > comma) text.replace(",", "") else text.replace(".", "").replace(",", ".")
            comma >= 0 -> {
                val parts = text.split(",")
                text = if (parts.size == 2 && parts[1].length != 3) text.replace(",", ".") else text.replace(",", "")
            }
            dot >= 0 -> if (text.count { it == '.' } > 1) text = text.replace(".", "")
        }
        return text.toDoubleOrNull()
    }

    private val dotThousands = Regex("""^\d{1,3}(\.\d{3})+$""")

    /** True when every dotted value reads like "45.000" or "1.234.567". */
    private fun usesDotThousands(values: List<String>): Boolean {
        val dotted = values.map { it.trim() }.filter { it.contains(".") }
        if (dotted.isEmpty()) return false
        return dotted.all { !it.contains(",") && dotThousands.matches(it) }
    }

    // MARK: - CSV

    /** RFC 4180 rows, with the delimiter (comma, semicolon or tab) taken from the file itself. */
    fun rows(source: String): List<List<String>> {
        val text = source.removePrefix("﻿")
        val delimiter = detectDelimiter(text)
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val field = StringBuilder()
        var quoted = false
        var i = 0
        while (i < text.length) {
            val char = text[i]
            i += 1
            if (quoted) {
                if (char == '"') {
                    if (i < text.length && text[i] == '"') {
                        field.append('"')
                        i += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(char)
                }
                continue
            }
            when {
                char == '"' && field.isEmpty() -> quoted = true
                char == delimiter -> {
                    row += field.toString()
                    field.clear()
                }
                char == '\n' || char == '\r' -> {
                    // "\r\n" is one line break, like Swift's single Character.
                    if (char == '\r' && i < text.length && text[i] == '\n') i += 1
                    row += field.toString()
                    rows += row
                    row = mutableListOf()
                    field.clear()
                }
                else -> field.append(char)
            }
        }
        if (field.isNotEmpty() || row.isNotEmpty()) {
            row += field.toString()
            rows += row
        }
        return rows
    }

    private fun detectDelimiter(text: String): Char {
        val lines = text.split('\n', '\r').filter { it.isNotEmpty() }.take(20)
        return listOf(',', ';', '\t').maxByOrNull { candidate -> lines.sumOf { line -> line.count { it == candidate } } } ?: ','
    }

    // MARK: - Dates

    /**
     * One format for a whole column, so 03/04 means the same thing on every row:
     * whichever format reads the most values, with the region's day/month order breaking ties.
     */
    class DateColumn(values: List<String>, locale: Locale, private val zone: ZoneId, private val now: Instant) {
        private val formatter: DateTimeFormatter?

        init {
            val samples = values.map(::datePart).filter { it.isNotEmpty() }.take(400)
            val dayFirst = prefersDayFirst(locale)
            var best: Triple<DateTimeFormatter, Int, Int>? = null
            for ((rank, format) in FORMATS.withIndex()) {
                val candidate = formatter(format)
                val score = samples.count { plausible(parse(candidate, it)) }
                if (score <= 0) continue
                val localRank = if (dayFirst && format.startsWith("d")) rank - 100 else rank
                val current = best
                if (current == null || score > current.second || (score == current.second && localRank < current.third)) {
                    best = Triple(candidate, score, localRank)
                }
            }
            formatter = best?.first
        }

        fun date(value: String): Instant? {
            val format = formatter ?: return null
            val day = parse(format, datePart(value))?.takeIf { plausible(it) } ?: return null
            // Noon keeps a date on the same day in every time zone the family is in.
            return day.atTime(LocalTime.NOON).atZone(zone).toInstant()
        }

        private fun plausible(date: LocalDate?): Boolean =
            date != null && date.year >= 1950 && date.atStartOfDay(zone).toInstant() < now.plusSeconds(2 * 86_400)

        private fun parse(format: DateTimeFormatter, text: String): LocalDate? = runCatching { LocalDate.parse(text, format) }.getOrNull()

        companion object {
            val FORMATS = listOf(
                "yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", "M/d/yyyy", "M/d/yy", "d/M/yyyy", "d/M/yy", "d.M.yyyy", "d.M.yy",
                "M-d-yyyy", "d-M-yyyy", "MMM d, yyyy", "MMMM d, yyyy", "MMM d yyyy", "d MMM yyyy", "d MMMM yyyy", "d-MMM-yyyy",
                "d-MMM-yy", "yyyyMMdd",
            )

            /** The Unicode pattern as a strict java.time formatter; a two-digit year lands within the last 80 years, like Foundation's. */
            fun formatter(format: String): DateTimeFormatter {
                val builder = DateTimeFormatterBuilder().parseCaseInsensitive()
                if (format.endsWith("yy") && !format.endsWith("yyyy")) {
                    builder.appendPattern(format.dropLast(2))
                        .appendValueReduced(ChronoField.YEAR, 2, 2, LocalDate.now().minusYears(80))
                } else {
                    builder.appendPattern(format.replace("yyyy", "uuuu"))
                }
                return builder.toFormatter(Locale.US).withResolverStyle(ResolverStyle.STRICT).withChronology(IsoChronology.INSTANCE)
            }

            private val timeSuffix = Regex("""(T|\s)\d{1,2}:\d{2}.*$""")

            /** Drops a trailing time: "2024-03-01 14:05", "2024-03-01T14:05:00Z". */
            fun datePart(value: String): String = value.trim().replace(timeSuffix, "").trim()

            fun prefersDayFirst(locale: Locale): Boolean {
                val pattern = DateTimeFormatterBuilder.getLocalizedDateTimePattern(FormatStyle.SHORT, null, IsoChronology.INSTANCE, locale)
                val day = pattern.indexOf('d')
                val month = pattern.indexOf('M')
                return day >= 0 && month >= 0 && day < month
            }
        }
    }

    // MARK: - Matching the schedule

    /** The catalog jobs a line of work names, most specific first, so "gear oil" never restarts the engine oil countdown. */
    fun catalogKeys(work: String): List<String> {
        var text = " " + work.lowercase() + " "
        val keys = mutableListOf<String>()
        for ((patterns, matched) in rules) {
            var hit = false
            for (pattern in patterns) {
                if (text.contains(pattern)) {
                    hit = true
                    text = text.replace(pattern, " ")
                }
            }
            if (hit) keys += matched.filter { it !in keys }
        }
        return keys
    }

    private val rules: List<Pair<List<String>, List<String>>> = listOf(
        listOf("gear oil", "lower unit", "gearcase", "gear case") to listOf("gearOil", "diffs"),
        listOf("fork oil", "fork seal") to listOf("forks"),
        listOf("chaincase", "chain case") to listOf("chaincase"),
        listOf("transmission fluid", "transmission oil", "transmission service", "transmission", "trans fluid", " atf", "cvt fluid") to
            listOf("transmission", "transmissionFluid", "hydraulic"),
        listOf("differential", "diff fluid", "diff oil") to listOf("diffs"),
        listOf("brake fluid") to listOf("brakeFluid"),
        listOf("oil leak", "oil pressure", "oil pan", "oil sensor") to emptyList(),
        listOf("brake pad", "brake job", "rotors", "brakes", "brake") to listOf("brakes"),
        listOf("cabin") to listOf("cabinFilter"),
        listOf("air filter", "engine filter", "air cleaner") to listOf("airFilter"),
        listOf("fuel filter") to listOf("fuelFilter"),
        listOf("fuel/water", "water separator") to listOf("fuelSeparator"),
        listOf("rotation", "rotate") to listOf("rotate"),
        listOf("alignment") to listOf("alignment"),
        listOf("new tires", "tire replacement", "replace tires", "replaced tires", "mount and balance", "tires installed") to listOf("tires"),
        listOf("wiper") to listOf("wipers"),
        listOf("coolant", "antifreeze", "radiator flush") to listOf("coolant"),
        listOf("spark plug", "plugs") to listOf("plugs"),
        listOf("battery") to listOf("battery", "battery12v", "boatBattery"),
        listOf("annual inspection", "annual") to listOf("annual"),
        listOf("smog", "emissions", "state inspection", "safety inspection") to listOf("inspection"),
        listOf("registration", "tabs") to listOf("registration"),
        listOf("impeller") to listOf("impeller"),
        listOf("winteriz", "layup") to listOf("winterize"),
        listOf("timing belt", "serpentine", "drive belt", "cvt belt") to listOf("belt", "cvt"),
        listOf("chain") to listOf("chain"),
        listOf("tune-up", "tune up", "tuneup") to listOf("tune"),
        listOf("diesel exhaust", " def ") to listOf("def"),
        listOf("grease", "lube chassis", "chassis lube") to listOf("grease"),
        listOf("valve") to listOf("valves"),
        listOf("anode", "zinc") to listOf("anodes"),
        listOf("generator") to listOf("generator"),
        listOf("oil change", "oil and filter", "oil & filter", "oil/filter", "lube oil", " lof ", "oil service", "synthetic oil",
            "engine oil", " oil") to listOf("oil"),
    )
}
