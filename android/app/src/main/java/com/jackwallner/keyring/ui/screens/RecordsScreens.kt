package com.jackwallner.keyring.ui.screens

import android.annotation.SuppressLint
import android.graphics.BitmapFactory
import android.webkit.JavascriptInterface
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.PictureAsPdf
import androidx.compose.material.icons.outlined.TouchApp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.jackwallner.keyring.data.Attachment
import com.jackwallner.keyring.data.DueCopy
import com.jackwallner.keyring.data.NHTSAClient
import com.jackwallner.keyring.data.Recall
import com.jackwallner.keyring.data.ServiceImport
import com.jackwallner.keyring.data.VINRecallCheck
import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.Format
import com.jackwallner.keyring.model.ProFeature
import com.jackwallner.keyring.model.Storage
import com.jackwallner.keyring.ui.LocalGraph
import com.jackwallner.keyring.ui.LocalNavigator
import com.jackwallner.keyring.ui.PickedFiles
import com.jackwallner.keyring.ui.nav.Route
import com.jackwallner.keyring.ui.theme.Card
import com.jackwallner.keyring.ui.theme.Chip
import com.jackwallner.keyring.ui.theme.Divider
import com.jackwallner.keyring.ui.theme.Field
import com.jackwallner.keyring.ui.theme.Keyring
import com.jackwallner.keyring.ui.theme.ListRow
import com.jackwallner.keyring.ui.theme.PrimaryButton
import com.jackwallner.keyring.ui.theme.SecondaryButton
import com.jackwallner.keyring.ui.theme.SectionHeader
import com.jackwallner.keyring.ui.theme.Space
import com.jackwallner.keyring.ui.theme.Symbols
import com.jackwallner.keyring.ui.theme.TopBar
import com.jackwallner.keyring.ui.theme.Type
import com.jackwallner.keyring.ui.theme.parseNumber
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// MARK: - Documents

/** Papers kept with the vehicle: title, build sheet, Marti Report, appraisals, window sticker. */
@Composable
fun DocumentsScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val context = LocalContext.current
    val colors = Keyring.colors
    @Suppress("UNUSED_VARIABLE") val data = graph.data
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    val documents = graph.garage.documents(vehicle)
    var viewing by remember { mutableStateOf<Attachment?>(null) }
    var renaming by remember { mutableStateOf<Attachment?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        uris.mapNotNull { PickedFiles.read(context, it) }.forEach { (name, bytes) -> graph.garage.addDocument(name, bytes, graph.garage.vehicle(vehicleId)!!) }
    }
    ExplorePage("Documents", "documents.list") {
        item {
            if (documents.isEmpty()) {
                Text("Keep the title, build sheet, appraisals and window sticker with the vehicle. They stay on this phone with its log.",
                    style = Type.callout, color = colors.secondaryInk, modifier = Modifier.testTag("documents.empty"))
                Spacer(Modifier.height(Space.sm))
            } else {
                Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                    documents.forEachIndexed { index, document ->
                        if (index > 0) Divider()
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.weight(1f)) {
                                ListRow(document.name ?: "Document", Format.shortDate(document.createdAt),
                                    if (document.isPDF) Icons.Outlined.PictureAsPdf else Symbols.icon("photo.fill"), iconTint = colors.brass,
                                    modifier = Modifier.testTag("document.${document.name}"),
                                    onClick = { if (document.isPDF) PickedFiles.openPDF(context, graph, document) else viewing = document })
                            }
                            IconButton(onClick = { renaming = document }) { Icon(Icons.Outlined.Edit, contentDescription = "Rename", tint = colors.faintInk) }
                            IconButton(onClick = { graph.garage.delete(document) }) { Icon(Icons.Outlined.Delete, contentDescription = "Delete", tint = colors.faintInk) }
                        }
                    }
                }
                Spacer(Modifier.height(Space.sm))
            }
            SecondaryButton("Add from files", { picker.launch(arrayOf("application/pdf", "image/*")) }, tag = "documents.add")
        }
    }
    viewing?.let { AttachmentViewer(it) { viewing = null } }
    renaming?.let { document ->
        var name by remember(document.id) { mutableStateOf(document.name ?: "") }
        AlertDialog(
            onDismissRequest = { renaming = null },
            title = { Text("Rename") },
            text = { Field(name, { name = it }, "Name", tag = "document.name") },
            confirmButton = { TextButton({ graph.garage.rename(document, name); renaming = null }) { Text("Save", color = colors.ink) } },
            dismissButton = { TextButton({ renaming = null }) { Text("Cancel", color = colors.ink) } },
        )
    }
}

/** A stored photo, full screen. */
@Composable
fun AttachmentViewer(attachment: Attachment, onDismiss: () -> Unit) {
    val graph = LocalGraph.current
    val bitmap = remember(attachment.id) {
        graph.attachmentFiles.read(attachment.file)?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() }
    }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black)) {
            if (bitmap != null) Image(bitmap, contentDescription = attachment.name ?: "Photo", contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
            IconButton(onClick = onDismiss, modifier = Modifier.align(Alignment.TopEnd).padding(Space.sm).testTag("viewer.close")) {
                Icon(Icons.Outlined.Close, contentDescription = "Close", tint = androidx.compose.ui.graphics.Color.White)
            }
        }
    }
}

/** A row of photo and file thumbnails; tapping one opens it. */
@Composable
fun AttachmentStrip(attachments: List<Attachment>, onRemove: ((Attachment) -> Unit)? = null) {
    val graph = LocalGraph.current
    val context = LocalContext.current
    var viewing by remember { mutableStateOf<Attachment?>(null) }
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
        attachments.forEach { attachment ->
            val bitmap = remember(attachment.id) {
                if (attachment.isPDF) null else graph.attachmentFiles.read(attachment.file)?.let {
                    BitmapFactory.decodeByteArray(it, 0, it.size, BitmapFactory.Options().apply { inSampleSize = 8 })?.asImageBitmap()
                }
            }
            Box(Modifier.size(76.dp).clip(RoundedCornerShape(Space.smallRadius)).background(Keyring.colors.raised)
                .clickable { if (attachment.isPDF) PickedFiles.openPDF(context, graph, attachment) else viewing = attachment }
                .testTag("attachment.${attachment.kind}"), contentAlignment = Alignment.Center) {
                if (bitmap != null) Image(bitmap, contentDescription = "Photo", contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                else Icon(Icons.Outlined.PictureAsPdf, contentDescription = attachment.name ?: "PDF", tint = Keyring.colors.brass)
                if (onRemove != null) {
                    IconButton(onClick = { onRemove(attachment) }, modifier = Modifier.align(Alignment.TopEnd).size(28.dp)) {
                        Icon(Icons.Outlined.Close, contentDescription = "Remove", tint = Keyring.colors.ink)
                    }
                }
            }
        }
    }
    viewing?.let { AttachmentViewer(it) { viewing = null } }
}

// MARK: - Storage

/** Puts a vehicle away for the season, or brings it back out. While it's stored, reminders pause and its pace stops counting. */
@Composable
fun StorageScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val colors = Keyring.colors
    @Suppress("UNUSED_VARIABLE") val data = graph.data
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    val returning = vehicle.isStored
    var remind by remember { mutableStateOf(vehicle.storedUntil != null || vehicle.storedSince == null) }
    var until by remember {
        mutableStateOf(vehicle.storedUntil?.atZone(ZoneId.systemDefault())?.toLocalDate() ?: Storage.defaultReturn())
    }
    var reading by remember { mutableStateOf("") }
    var auxReading by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize()) {
        TopBar(if (returning) "Back on the road" else "Put in storage", { nav.pop() })
        androidx.compose.foundation.lazy.LazyColumn(contentPadding = PaddingValues(start = Space.margin, end = Space.margin, bottom = Space.xxl),
            verticalArrangement = Arrangement.spacedBy(Space.sm), modifier = Modifier.testTag("storage.list")) {
            if (!returning) {
                item {
                    Card {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Remind me to take it out", style = Type.subheadlineBold, color = colors.ink, modifier = Modifier.weight(1f))
                            Switch(remind, { remind = it }, modifier = Modifier.testTag("storage.remind"),
                                colors = SwitchDefaults.colors(checkedTrackColor = colors.ink))
                        }
                        if (remind) {
                            Spacer(Modifier.height(Space.xs))
                            DateRow("On", until, { until = it }, min = LocalDate.now())
                        }
                    }
                    Spacer(Modifier.height(Space.xs))
                    Text("Reminders for ${vehicle.displayName} pause and the app stops assuming the ${vehicle.meter.meterName.lowercase()} is moving. Jobs that go by the calendar still count the months.",
                        style = Type.footnote, color = colors.secondaryInk)
                }
                val prep = graph.garage.enabledTasks(vehicle).filter { it.catalogKey in Storage.prepKeys }
                if (prep.isNotEmpty()) item {
                    SectionHeader("Before you put it away")
                    Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                        prep.forEachIndexed { index, task ->
                            if (index > 0) Divider()
                            ListRow(task.name, null, Symbols.icon(task.symbol))
                        }
                    }
                }
                item {
                    PrimaryButton("Put away", {
                        graph.garage.store(vehicle, if (remind) Storage.startOfDay(until) else null)
                        nav.pop()
                    }, tag = "storage.save")
                }
            } else {
                item {
                    if (vehicle.meter.hasReading) {
                        Field(reading, { reading = it }, "${vehicle.meter.meterName} (${vehicle.meter.short})", number = true, tag = "storage.reading",
                            supporting = "Last ${Format.reading(vehicle.reading, vehicle.meter)}")
                    }
                    if (vehicle.hasAuxMeter) {
                        Spacer(Modifier.height(Space.xs))
                        Field(auxReading, { auxReading = it }, vehicle.auxMeterLabel, number = true, tag = "storage.auxReading",
                            supporting = "Last ${Format.reading(vehicle.auxReading, vehicle.auxMeter)}")
                    }
                    vehicle.storedSince?.let {
                        Spacer(Modifier.height(Space.xs))
                        Text("In storage since ${Format.shortDate(it)}. A new reading picks the due dates back up from here.", style = Type.footnote, color = colors.secondaryInk)
                    }
                }
                item {
                    SectionHeader("Before its first trip")
                    val due = graph.garage.dues(vehicle).filter { it.result.status <= DueStatus.DUE_SOON }
                    if (due.isEmpty()) Text("Nothing is due. Enjoy the season.", style = Type.callout, color = colors.secondaryInk)
                    else Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                        due.forEachIndexed { index, item ->
                            if (index > 0) Divider()
                            ListRow(item.name, DueCopy.dueLine(item), Symbols.icon(item.task.symbol), iconTint = colors.status(item.result.status))
                        }
                    }
                }
                item {
                    PrimaryButton("Done", {
                        graph.garage.returnFromStorage(vehicle, parseNumber(reading), parseNumber(auxReading))
                        nav.pop()
                    }, tag = "storage.save")
                }
            }
        }
    }
}

/** A date with a picker behind it. */
@Composable
fun DateRow(label: String, date: LocalDate, onChange: (LocalDate) -> Unit, min: LocalDate? = null, max: LocalDate? = null) {
    val context = LocalContext.current
    val colors = Keyring.colors
    Row(Modifier.fillMaxWidth().clickable {
        android.app.DatePickerDialog(context, { _, y, m, d -> onChange(LocalDate.of(y, m + 1, d)) }, date.year, date.monthValue - 1, date.dayOfMonth).apply {
            min?.let { datePicker.minDate = it.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli() }
            max?.let { datePicker.maxDate = it.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli() }
        }.show()
    }.padding(vertical = Space.xs).testTag("date.$label"), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = Type.subheadline, color = colors.ink, modifier = Modifier.weight(1f))
        Text(Format.longDate(date), style = Type.subheadlineBold, color = colors.brass)
    }
}

// MARK: - Sold or retired

/** Marks it sold (with the date and price) or just retired, then offers to hand its history to the buyer. */
@Composable
fun RetireScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val colors = Keyring.colors
    @Suppress("UNUSED_VARIABLE") val data = graph.data
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    var sold by remember { mutableStateOf(true) }
    var date by remember { mutableStateOf(LocalDate.now()) }
    var price by remember { mutableStateOf("") }
    var handingOver by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        TopBar(if (handingOver) "Sold" else vehicle.displayName, if (handingOver) null else ({ nav.pop() }))
        Column(Modifier.padding(horizontal = Space.margin), verticalArrangement = Arrangement.spacedBy(Space.sm)) {
            if (handingOver) {
                Spacer(Modifier.height(Space.lg))
                Icon(Symbols.icon("key.horizontal.fill"), contentDescription = null, tint = colors.brass, modifier = Modifier.size(34.dp))
                Text("Hand over its history", style = Type.title(28), color = colors.ink)
                Text("A clean record of every job helps the buyer trust the price.", style = Type.callout, color = colors.secondaryInk)
                PrimaryButton("Service Record (PDF)", {
                    if (graph.store.isPro) shareFile(context, com.jackwallner.keyring.data.ServiceRecordPDF.write(context, graph.garage, vehicle), "application/pdf")
                    else nav.push(Route.Paywall(ProFeature.serviceRecord))
                }, tag = "retire.record")
                SecondaryButton("Spreadsheet (CSV)", { shareFile(context, writeCsv(context, graph.garage, listOf(vehicle)), "text/csv") }, tag = "retire.csv")
                TextButton({ nav.reset(Route.Garage) }, modifier = Modifier.fillMaxWidth().testTag("retire.done")) {
                    Text("Done", style = Type.subheadlineBold, color = colors.ink)
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
                    Chip("Sold", sold, { sold = true }, tag = "retire.sold")
                    Chip("Retired", !sold, { sold = false }, tag = "retire.retired")
                }
                if (sold) {
                    Card {
                        DateRow("Sold on", date, { date = it }, max = LocalDate.now())
                        Field(price, { price = it }, "Price (optional)", number = true, tag = "retire.price")
                    }
                    Text("Kept with its history, so you know what it cost to own.", style = Type.footnote, color = colors.secondaryInk)
                }
                PrimaryButton(if (sold) "Mark sold" else "Retire", {
                    if (sold) {
                        graph.garage.markSold(vehicle, date.atTime(12, 0).atZone(ZoneId.systemDefault()).toInstant(), parseNumber(price))
                        handingOver = true
                    } else {
                        graph.garage.retire(vehicle)
                        nav.reset(Route.Garage)
                    }
                }, tag = "retire.save")
                Text("Its history stays, reminders stop, and it no longer counts toward the free limit. Restore it any time from Sold and retired.",
                    style = Type.footnote, color = colors.secondaryInk)
            }
        }
    }
}

// MARK: - Import

/** A service history from another app or a spreadsheet, added to one vehicle. Ported from `ImportView.swift`. */
@Composable
fun ImportScreen(preselected: String?, initialText: String? = null) {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val colors = Keyring.colors
    @Suppress("UNUSED_VARIABLE") val data = graph.data
    var result by remember { mutableStateOf(initialText?.let { ServiceImport.parse(it) }) }
    var target by remember { mutableStateOf(preselected ?: graph.garage.activeVehicles.firstOrNull()?.id) }
    var keepFillUps by remember { mutableStateOf(true) }
    var outcome by remember { mutableStateOf<String?>(null) }
    var failed by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val text = PickedFiles.text(context, uri)
        val parsed = text?.let { ServiceImport.parse(it) }
        failed = parsed == null || parsed.isEmpty
        result = parsed?.takeIf { !it.isEmpty }
        outcome = null
    }
    ExplorePage("Import history", "import.list") {
        item {
            Text("Bring your history from Fuelly, Drivvo, Simply Auto, aCar or a spreadsheet. Export a CSV from the other app, then pick it here.",
                style = Type.callout, color = colors.secondaryInk)
            Spacer(Modifier.height(Space.sm))
            SecondaryButton(if (result == null) "Choose a CSV file" else "Choose another file",
                { picker.launch(arrayOf("text/*", "application/csv", "application/vnd.ms-excel", "application/octet-stream")) }, tag = "import.pick")
            if (failed) {
                Spacer(Modifier.height(Space.xs))
                Text("Couldn't find dated rows in that file. It needs a header row with a date column.", style = Type.footnote, color = colors.overdue)
            }
        }
        val current = result ?: return@ExplorePage
        item {
            Spacer(Modifier.height(Space.sm))
            SectionHeader("From ${current.source.title}")
            Card {
                Text(listOfNotNull(
                    Format.count(current.services.size, "service", "services"),
                    current.fillUps.size.takeIf { it > 0 }?.let { Format.count(it, "fill-up", "fill-ups") },
                    current.skippedExpenses.takeIf { it > 0 }?.let { "${Format.count(it, "expense", "expenses")} skipped" },
                    current.unreadable.takeIf { it > 0 }?.let { "${Format.count(it, "row", "rows")} without a date" },
                ).joinToString(" · "), style = Type.subheadlineBold, color = colors.ink, modifier = Modifier.testTag("import.summary"))
                if (current.foldedHeaders.isNotEmpty()) {
                    Text("Kept in notes: ${current.foldedHeaders.joinToString(", ")}", style = Type.footnote, color = colors.secondaryInk)
                }
                current.services.takeLast(4).reversed().forEach { row ->
                    Divider()
                    ListRow(row.work.ifEmpty { "Service" }, listOfNotNull(Format.shortDate(row.date), row.cost.takeIf { it > 0 }?.let { Format.money(it) }, row.shop).joinToString(" · "))
                }
            }
        }
        current.mainTable?.let { table ->
            item { ColumnMapping(table) { field, column -> result = ServiceImport.remap(current, table.id, field, column) } }
        }
        item {
            SectionHeader("Add to")
            val vehicles = graph.garage.activeVehicles
            if (vehicles.isEmpty()) Text("Add a vehicle first, then import its history.", style = Type.callout, color = colors.secondaryInk)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
                vehicles.forEach { Chip(it.displayName, target == it.id, { target = it.id }, tag = "import.vehicle.${it.displayName}") }
            }
            if (current.fillUps.isNotEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = Space.xs)) {
                    Text("Keep fill-ups", style = Type.subheadline, color = colors.ink, modifier = Modifier.weight(1f))
                    Switch(keepFillUps, { keepFillUps = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.ink))
                }
            }
            Spacer(Modifier.height(Space.sm))
            val vehicle = target?.let { graph.garage.vehicle(it) }
            if (outcome == null) {
                PrimaryButton("Import", {
                    val chosen = vehicle ?: return@PrimaryButton
                    val done = graph.garage.importHistory(current.services + current.fillUps, chosen, keepFillUps)
                    outcome = listOfNotNull(
                        "Added ${Format.count(done.added, "entry", "entries")}",
                        done.fillUps.takeIf { it > 0 }?.let { Format.count(it, "fill-up", "fill-ups") },
                        done.readings.takeIf { it > 0 }?.let { Format.count(it, "meter reading", "meter readings") },
                        done.duplicates.takeIf { it > 0 }?.let { "${Format.count(it, "duplicate", "duplicates")} skipped" },
                        done.jobsUpdated.takeIf { it > 0 }?.let { "${Format.count(it, "job", "jobs")} on the schedule updated" },
                    ).joinToString(". ") + "."
                }, enabled = vehicle != null, tag = "import.save")
            } else {
                Text(outcome!!, style = Type.callout, color = colors.good, modifier = Modifier.testTag("import.outcome"))
                Spacer(Modifier.height(Space.xs))
                SecondaryButton("Done", { nav.pop() }, tag = "import.done")
            }
        }
    }
}

@Composable
private fun ColumnMapping(table: ServiceImport.Table, onChange: (ServiceImport.Field, Int?) -> Unit) {
    val colors = Keyring.colors
    Column {
        SectionHeader("Columns")
        Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
            ServiceImport.Field.editable.forEachIndexed { index, field ->
                if (index > 0) Divider()
                var open by remember { mutableStateOf(false) }
                Box {
                    Row(Modifier.fillMaxWidth().clickable { open = true }.padding(vertical = Space.rowPadding).testTag("import.column.${field.name}"),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(field.title, style = Type.subheadline, color = colors.ink, modifier = Modifier.weight(1f))
                        Text(table.mapping[field]?.let { table.headers[it].trim() } ?: "None", style = Type.subheadlineBold, color = colors.brass)
                    }
                    DropdownMenu(open, { open = false }) {
                        DropdownMenuItem({ Text("None") }, { open = false; onChange(field, null) })
                        table.headers.forEachIndexed { column, header ->
                            if (header.isNotBlank()) DropdownMenuItem({ Text(header.trim()) }, { open = false; onChange(field, column) })
                        }
                    }
                }
            }
        }
        Text("Point a field at another column if something landed in the wrong place.", style = Type.footnote, color = colors.secondaryInk)
    }
}

// MARK: - VIN check

/**
 * NHTSA's VIN lookup inside the app, with the VIN filled in. The owner taps
 * Search on NHTSA's own page (it's behind reCAPTCHA); the result is read off
 * the page and saved on the device. Ported from `VINCheckSheet.swift`.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun VinCheckScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val colors = Keyring.colors
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    val vin = vehicle.vin ?: return
    var known by remember { mutableStateOf<List<Recall>?>(null) }
    var loaded by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        known = runCatching { withContext(Dispatchers.IO) { NHTSAClient.recalls(vehicle.year, vehicle.make.orEmpty(), vehicle.model.orEmpty()) } }.getOrDefault(emptyList())
    }
    Column(Modifier.fillMaxSize()) {
        TopBar("Check the VIN", { nav.pop() })
        Row(Modifier.fillMaxWidth().background(colors.brassSoft).padding(Space.md), horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            Icon(Icons.Outlined.TouchApp, contentDescription = null, tint = colors.brass)
            Text("Your VIN is filled in. Tap Search and the recalls still open on it come back here.", style = Type.footnote, color = colors.ink)
        }
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            val list = known
            if (list != null && !failed) {
                androidx.compose.runtime.key(attempt) {
                    AndroidView(modifier = Modifier.fillMaxSize().testTag("vin.web"), factory = { context ->
                        WebView(context).apply {
                            settings.javaScriptEnabled = true
                            settings.domStorageEnabled = true
                            addJavascriptInterface(object {
                                @JavascriptInterface
                                fun postMessage(json: String) {
                                    val check = VINRecallCheck.parse(json, vin, list) ?: return
                                    post {
                                        graph.vinChecks.save(check, vehicle)
                                        nav.pop()
                                    }
                                }
                            }, VINRecallCheck.BRIDGE)
                            webViewClient = object : WebViewClient() {
                                override fun onPageFinished(view: WebView, url: String?) {
                                    loaded = true
                                    view.evaluateJavascript(VINRecallCheck.pageScript(vin), null)
                                }

                                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                                    if (request.isForMainFrame) failed = true
                                }
                            }
                            loadUrl(VINRecallCheck.LOOKUP_URL)
                        }
                    })
                }
            }
            if (failed) {
                Column(Modifier.padding(Space.margin), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.sm)) {
                    Text("Couldn't reach NHTSA", style = Type.headline, color = colors.ink)
                    Text("Check the connection and try again. The recalls for the model are still listed.", style = Type.callout, color = colors.secondaryInk)
                    SecondaryButton("Try again", { failed = false; loaded = false; attempt += 1 })
                }
            } else if (!loaded) {
                CircularProgressIndicator(Modifier.size(28.dp), color = colors.ink)
            }
        }
    }
}

/** "Checked Oct 20" for the recalls screen. */
fun vinCheckedLine(check: VINRecallCheck): String =
    if (check.covered) "Checked your VIN ${Format.shortDate(check.date)}" else "NHTSA has no VIN data from this maker yet (checked ${Format.shortDate(check.date)})"
