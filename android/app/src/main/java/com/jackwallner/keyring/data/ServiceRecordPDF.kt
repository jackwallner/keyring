package com.jackwallner.keyring.data

import android.content.Context
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import com.jackwallner.keyring.model.Format
import java.io.File
import java.time.Instant

/**
 * The Pro Service Record, ported from `ServiceRecordPDF.swift`: the vehicle,
 * its schedule and every job on US Letter pages. No affiliate links (Amazon's
 * offline-use rule) and no third-party values.
 */
object ServiceRecordPDF {
    private const val WIDTH = 612
    private const val HEIGHT = 792
    private const val MARGIN = 48f

    fun write(context: Context, store: GarageStore, vehicle: Vehicle, now: Instant = Instant.now()): File {
        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val file = File(dir, "${vehicle.displayName.replace(Regex("[^A-Za-z0-9 ]"), "").trim().ifEmpty { "Vehicle" }} Service Record.pdf")
        val document = PdfDocument()
        val ink = 0xFF1C1B19.toInt()
        val secondary = 0xFF69655C.toInt()
        val title = Paint().apply { color = ink; textSize = 24f; typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD); isAntiAlias = true }
        val heading = Paint().apply { color = ink; textSize = 13f; typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD); isAntiAlias = true }
        val body = Paint().apply { color = ink; textSize = 10.5f; isAntiAlias = true }
        val small = Paint().apply { color = secondary; textSize = 9f; isAntiAlias = true }
        val rule = Paint().apply { color = 0xFFDED8CB.toInt(); strokeWidth = 0.8f }

        var pageNumber = 0
        var page = document.startPage(PdfDocument.PageInfo.Builder(WIDTH, HEIGHT, ++pageNumber).create())
        var y = MARGIN
        fun ensure(space: Float) {
            if (y + space <= HEIGHT - MARGIN) return
            page.canvas.drawText("Page $pageNumber", MARGIN, HEIGHT - 24f, small)
            document.finishPage(page)
            page = document.startPage(PdfDocument.PageInfo.Builder(WIDTH, HEIGHT, ++pageNumber).create())
            y = MARGIN
        }
        fun line(text: String, paint: Paint, x: Float = MARGIN, gap: Float = paint.textSize + 5f) {
            ensure(gap)
            page.canvas.drawText(text, x, y + paint.textSize, paint)
            y += gap
        }

        line("SERVICE RECORD", small)
        line(vehicle.displayName, title, gap = 32f)
        line(listOf(vehicle.descriptor, vehicle.trim.orEmpty()).filter { it.isNotEmpty() }.joinToString(" · "), body)
        vehicle.vin?.let { line("${vehicle.kind.identifierLabel}: $it", body) }
        if (vehicle.meter.hasReading) line("${vehicle.meter.meterName}: ${Format.reading(vehicle.reading, vehicle.meter)}", body)
        line("Prepared ${Format.shortDate(now, now)}", small, gap = 22f)

        val dues = store.dues(vehicle, now)
        if (dues.isNotEmpty()) {
            line("Schedule", heading, gap = 20f)
            for (due in dues) {
                ensure(16f)
                page.canvas.drawText(due.name, MARGIN, y + 10.5f, body)
                page.canvas.drawText(DueCopy.dueLine(due, now, notingPace = false), 300f, y + 10.5f, small)
                y += 16f
            }
            y += 10f
        }

        val entries = store.entries(vehicle)
        line("History (${entries.size})", heading, gap = 20f)
        if (entries.isEmpty()) line("Nothing logged yet.", body)
        for (entry in entries) {
            ensure(36f)
            page.canvas.drawLine(MARGIN, y, WIDTH - MARGIN, y, rule)
            y += 6f
            page.canvas.drawText(Format.shortDate(entry.date, now), MARGIN, y + 10.5f, small)
            page.canvas.drawText(entry.title.take(60), 120f, y + 10.5f, body)
            if (entry.cost > 0) page.canvas.drawText(Format.money(entry.cost), WIDTH - MARGIN - body.measureText(Format.money(entry.cost)), y + 10.5f, body)
            y += 15f
            val detail = listOfNotNull(entry.kind.title, entry.reading.takeIf { it >= 0 }?.let { Format.reading(it, vehicle.meter) },
                entry.shop ?: if (entry.isDIY) "Done by the owner" else null).joinToString(" · ")
            page.canvas.drawText(detail, 120f, y + 9f, small)
            y += 14f
            entry.notes?.let { notes -> notes.chunked(95).take(3).forEach { chunk -> line(chunk, small, x = 120f, gap = 12f) } }
        }
        page.canvas.drawText("Page $pageNumber · Kept with Vehicle Maintenance Log", MARGIN, HEIGHT - 24f, small)
        document.finishPage(page)
        file.outputStream().use(document::writeTo)
        document.close()
        return file
    }
}
