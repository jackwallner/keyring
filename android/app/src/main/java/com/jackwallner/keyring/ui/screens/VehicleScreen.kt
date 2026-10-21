package com.jackwallner.keyring.ui.screens

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.LocalGasStation
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.jackwallner.keyring.data.CSVExport
import com.jackwallner.keyring.data.DueCopy
import com.jackwallner.keyring.data.GarageStore
import com.jackwallner.keyring.data.ServiceRecordPDF
import com.jackwallner.keyring.data.Vehicle
import com.jackwallner.keyring.model.Format
import com.jackwallner.keyring.model.ProFeature
import com.jackwallner.keyring.ui.LocalGraph
import com.jackwallner.keyring.ui.LocalNavigator
import com.jackwallner.keyring.ui.nav.Route
import com.jackwallner.keyring.ui.theme.Card
import com.jackwallner.keyring.ui.theme.Divider
import com.jackwallner.keyring.ui.theme.Eyebrow
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
import com.jackwallner.keyring.ui.theme.color
import com.jackwallner.keyring.ui.theme.foreground
import com.jackwallner.keyring.ui.theme.parseNumber
import java.io.File

/** One vehicle: its schedule, its history and its tools. Ported from `VehicleDetailView.swift`. */
@Composable
fun VehicleScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val colors = Keyring.colors
    val data = graph.data
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    val dues = remember(vehicle, data) { graph.garage.dues(vehicle) }
    val entries = remember(vehicle, data) { graph.garage.entries(vehicle) }
    var updatingMeter by remember { mutableStateOf(false) }
    var updatingAux by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }
    val isPro = graph.store.isPro

    Column(Modifier.fillMaxSize()) {
        TopBar(vehicle.displayName, onBack = { nav.pop() }) {
            IconButton(onClick = { nav.push(Route.EditVehicle(vehicle.id)) }, modifier = Modifier.testTag("vehicle.edit")) {
                Icon(Icons.Outlined.Edit, contentDescription = "Edit", tint = colors.ink)
            }
        }
        LazyColumn(contentPadding = PaddingValues(start = Space.margin, end = Space.margin, bottom = Space.xxl), modifier = Modifier.testTag("vehicle.list")) {
            item { Header(vehicle, graph.attachmentFiles.read(vehicle.photo ?: ""), { updatingAux = true }) { updatingMeter = true } }
            if (vehicle.isStored) item {
                Spacer(Modifier.height(Space.sm))
                Card(Modifier.testTag("vehicle.stored")) {
                    Text("In storage since ${Format.shortDate(vehicle.storedSince!!)}", style = Type.subheadlineBold, color = colors.ink)
                    Text(vehicle.storedUntil?.let { "Reminders are paused until ${Format.shortDate(it)}." } ?: "Reminders are paused.",
                        style = Type.footnote, color = colors.secondaryInk)
                    androidx.compose.material3.TextButton({ nav.push(Route.Storage(vehicle.id)) }, modifier = Modifier.testTag("vehicle.unstore"),
                        contentPadding = PaddingValues(0.dp)) { Text("Back on the road", style = Type.subheadlineBold, color = colors.brass) }
                }
            }
            item {
                Row(Modifier.padding(vertical = Space.md), horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
                    PrimaryButton("Log service", { nav.push(Route.LogService(vehicle.id)) }, Modifier.weight(1f), tag = "vehicle.log")
                    if (vehicle.powertrain.burnsFuel) {
                        SecondaryButton("Fill-up", { nav.push(Route.LogService(vehicle.id, fuel = true)) }, Modifier.weight(0.7f), tag = "vehicle.fuel")
                    }
                }
            }
            item { SectionHeader("Schedule") }
            if (dues.isEmpty()) {
                item {
                    Text("No jobs on the schedule. Add some from the catalog for this ${vehicle.kind.title.lowercase()}.",
                        style = Type.callout, color = colors.secondaryInk)
                }
            }
            item {
                if (dues.isNotEmpty()) Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                    dues.forEachIndexed { index, due ->
                        if (index > 0) Divider()
                        ListRow(
                            title = due.name,
                            subtitle = DueCopy.dueLine(due),
                            icon = Symbols.icon(due.task.symbol),
                            iconTint = colors.status(due.result.status),
                            trailing = due.result.status.takeIf { it != com.jackwallner.keyring.model.DueStatus.OK }?.label,
                            trailingColor = colors.status(due.result.status),
                            modifier = Modifier.testTag("vehicle.task.${due.task.catalogKey ?: due.task.id}"),
                            onClick = { nav.push(Route.Task(vehicle.id, due.task.id)) },
                        )
                    }
                }
                TextButtonRow("Add from the catalog", "vehicle.catalog") { nav.push(Route.Catalog(vehicle.id)) }
                Text("Intervals are typical figures for normal use, not your maker's schedule. Check your owner's manual and adjust any job.",
                    style = Type.footnote, color = colors.faintInk)
                Spacer(Modifier.height(Space.sectionGap))
                SectionHeader("History")
            }
            if (entries.isEmpty()) {
                item { Text("Nothing logged yet. Log a job and it shows here.", style = Type.callout, color = colors.secondaryInk) }
            } else {
                item {
                    Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                        entries.take(8).forEachIndexed { index, entry ->
                            if (index > 0) Divider()
                            ListRow(
                                title = entry.title,
                                subtitle = listOfNotNull(Format.shortDate(entry.date), entry.reading.takeIf { it >= 0 }?.let { Format.reading(it, vehicle.meter) },
                                    entry.shop ?: if (entry.isDIY) "DIY" else null).joinToString(" · "),
                                icon = Symbols.entry(entry.kind),
                                trailing = entry.cost.takeIf { it > 0 }?.let { Format.money(it) },
                                onClick = { nav.push(Route.LogService(vehicle.id, entryId = entry.id)) },
                            )
                        }
                    }
                    if (entries.size > 8) TextButtonRow("All ${entries.size} entries", "vehicle.allHistory") { nav.push(Route.History) }
                }
            }
            item {
                Spacer(Modifier.height(Space.sectionGap))
                SectionHeader("Explore")
                val valuations = graph.garage.valuations(vehicle)
                val firstSource = com.jackwallner.keyring.catalog.ValueSource.sources(vehicle).firstOrNull()
                val tiles = listOfNotNull(
                    Tile("What it's worth", valuations.firstOrNull()?.let { "Last noted ${Format.money(it.amount)}" }
                        ?: if (vehicle.kind.isRoad && firstSource != null) "${firstSource.name} and more" else "Price guides",
                        "dollarsign.circle.fill", "explore.value") { nav.push(Route.Value(vehicle.id)) },
                    Tile("Parts and tools", "For what's due next", "wrench.and.screwdriver.fill", "explore.gear") { nav.push(Route.Gear(vehicle.id)) },
                    Tile("Upgrades", "Popular add-ons", "sparkles", "explore.upgrades") { nav.push(Route.Upgrades(vehicle.id)) },
                    Tile("Clubs", "Owners like you", "person.3.fill", "explore.clubs") { nav.push(Route.Clubs(vehicle.id)) },
                    Tile("Service nearby", "Shops, mobile mechanics, detailing", "mappin.and.ellipse", "explore.service") { nav.push(Route.ServiceNearby(vehicle.id)) },
                    if (vehicle.kind.hasNHTSARecords) Tile(if (isUSRegion) "Recalls" else "US recalls",
                        if (vehicle.year > 0 && vehicle.make != null) graph.vinChecks.check(vehicle)?.let { "VIN checked ${Format.shortDate(it.date)}" } ?: "Open NHTSA campaigns"
                        else "Add year, make and model", "exclamationmark.shield.fill", "vehicle.recalls") { nav.push(Route.Recalls(vehicle.id)) } else null,
                    Tile("Insights", if (isPro) "Where the money goes" else "Pro", "chart.bar.fill", "vehicle.insights") {
                        nav.push(if (isPro) Route.Insights(vehicle.id) else Route.Paywall(ProFeature.insights))
                    },
                )
                TileGrid(tiles)
                Spacer(Modifier.height(Space.sectionGap))
                SectionHeader("Records")
                Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                    val documents = graph.garage.documents(vehicle).size
                    ListRow("Documents", if (documents == 0) "Title, build sheet, appraisals" else Format.count(documents, "document", "documents"),
                        Symbols.icon("doc.text"), iconTint = colors.brass, modifier = Modifier.testTag("vehicle.documents"), onClick = { nav.push(Route.Documents(vehicle.id)) })
                    Divider()
                    ListRow("Trip check", "What comes due before you're back", Symbols.icon("suitcase.rolling"), iconTint = colors.brass,
                        modifier = Modifier.testTag("vehicle.trip"), onClick = { nav.push(Route.TripCheck(vehicle.id)) })
                    Divider()
                    ListRow("Service Record", if (isPro) "A clean PDF of every job, for a buyer, a shop or the glovebox" else "Pro",
                        Symbols.icon("doc.text"), iconTint = colors.brass, modifier = Modifier.testTag("vehicle.record"),
                        onClick = {
                            if (isPro) shareFile(context, ServiceRecordPDF.write(context, graph.garage, vehicle), "application/pdf")
                            else nav.push(Route.Paywall(ProFeature.serviceRecord))
                        })
                    Divider()
                    ListRow("Spreadsheet (CSV)", "Every entry, free, always", Symbols.icon("checklist"), iconTint = colors.brass, modifier = Modifier.testTag("vehicle.csv"),
                        onClick = { shareFile(context, writeCsv(context, graph.garage, listOf(vehicle)), "text/csv") })
                    Divider()
                    ListRow("Import history", "From Fuelly, Drivvo, Simply Auto or a spreadsheet", Symbols.icon("tray.and.arrow.down"), iconTint = colors.brass,
                        modifier = Modifier.testTag("vehicle.import"), onClick = { nav.push(Route.Import(vehicle.id)) })
                }
                Spacer(Modifier.height(Space.lg))
                if (!vehicle.isStored) {
                    SecondaryButton("Put in storage", { nav.push(Route.Storage(vehicle.id)) }, tag = "vehicle.store")
                    Spacer(Modifier.height(Space.xs))
                }
                SecondaryButton("Sold or retired", { nav.push(Route.Retire(vehicle.id)) }, tag = "vehicle.retire")
                Spacer(Modifier.height(Space.xs))
                androidx.compose.material3.TextButton(onClick = { confirmingDelete = true }, modifier = Modifier.fillMaxWidth().testTag("vehicle.delete")) {
                    Text("Delete vehicle and history", style = Type.subheadlineBold, color = colors.overdue)
                }
                Text("Retired and sold vehicles keep their full history and stop sending reminders. They don't count toward the free limit.",
                    style = Type.footnote, color = colors.faintInk)
            }
        }
    }
    if (updatingMeter) MeterDialog(vehicle, graph.garage) { updatingMeter = false }
    if (updatingAux) AuxMeterDialog(vehicle, graph.garage) { updatingAux = false }
    if (confirmingDelete) {
        AlertDialog(
            onDismissRequest = { confirmingDelete = false },
            title = { Text("Delete ${vehicle.displayName}?") },
            text = { Text("Its whole history is deleted. To keep the history, retire it instead.") },
            confirmButton = { TextButton({ confirmingDelete = false; graph.garage.delete(vehicle); nav.pop() }) { Text("Delete", color = colors.overdue) } },
            dismissButton = { TextButton({ confirmingDelete = false }) { Text("Cancel", color = colors.ink) } },
        )
    }
}

@Composable
private fun TextButtonRow(text: String, tag: String, onClick: () -> Unit) {
    androidx.compose.material3.TextButton(onClick = onClick, modifier = Modifier.testTag(tag), contentPadding = PaddingValues(vertical = Space.sm)) {
        Text(text, style = Type.subheadlineBold, color = Keyring.colors.brass)
    }
}

private class Tile(val title: String, val detail: String, val symbol: String, val tag: String, val onClick: () -> Unit)

/** Two tiles a row, like the iOS explore grid; an odd last tile takes the full width. */
@Composable
private fun TileGrid(tiles: List<Tile>) {
    val colors = Keyring.colors
    Column(verticalArrangement = Arrangement.spacedBy(Space.stackGap)) {
        tiles.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(Space.stackGap)) {
                row.forEach { tile ->
                    Column(Modifier.weight(1f).clip(RoundedCornerShape(Space.radius)).background(colors.surface)
                        .border(1.dp, colors.hairline, RoundedCornerShape(Space.radius))
                        .clickable(onClick = tile.onClick).testTag(tile.tag).padding(Space.md)) {
                        Icon(Symbols.icon(tile.symbol), contentDescription = null, tint = colors.brass, modifier = Modifier.size(24.dp))
                        Spacer(Modifier.height(Space.sm))
                        Text(tile.title, style = Type.subheadlineBold, color = colors.ink, maxLines = 1)
                        Text(tile.detail, style = Type.footnote, color = colors.secondaryInk, maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

@Composable
private fun Header(vehicle: Vehicle, photo: ByteArray?, onAux: () -> Unit, onMeter: () -> Unit) {
    val tint = vehicle.tint
    val fg = tint.foreground()
    val image = androidx.compose.runtime.remember(vehicle.photo) {
        photo?.let { android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() }
    }
    if (image != null) {
        androidx.compose.foundation.Image(image, contentDescription = "Photo of ${vehicle.displayName}",
            contentScale = androidx.compose.ui.layout.ContentScale.Crop,
            modifier = Modifier.fillMaxWidth().height(180.dp).clip(RoundedCornerShape(Space.radius)).testTag("vehicle.photo"))
        Spacer(Modifier.height(Space.sm))
    }
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Space.radius)).background(tint.color()).padding(Space.lg)) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(vehicle.descriptor.uppercase().ifEmpty { vehicle.kind.title.uppercase() }, style = Type.caption, color = fg.copy(alpha = 0.8f))
                Text(vehicle.displayName, style = Type.title(28), color = fg)
                listOfNotNull(vehicle.trim, vehicle.powertrain.title.takeIf { vehicle.powertrain.burnsFuel || vehicle.powertrain.name == "electric" })
                    .filter { it.isNotEmpty() }.joinToString(" · ").takeIf { it.isNotEmpty() }?.let { Text(it, style = Type.footnote, color = fg.copy(alpha = 0.8f)) }
            }
            Icon(Symbols.kind(vehicle.kind), contentDescription = null, tint = fg, modifier = Modifier.size(30.dp))
        }
        if (vehicle.meter.hasReading || vehicle.hasAuxMeter) {
            Spacer(Modifier.height(Space.md))
            Row(horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
                val chip = androidx.compose.ui.graphics.Color.Black.copy(alpha = if (tint.isLight) 0.08f else 0.22f)
                if (vehicle.meter.hasReading) {
                    Box(Modifier.clip(RoundedCornerShape(14.dp)).background(chip)
                        .clickable(onClick = onMeter).testTag("vehicle.meter").padding(horizontal = Space.md, vertical = Space.sm)) {
                        Column {
                            Text(vehicle.meter.meterName.uppercase(), style = Type.caption, color = fg.copy(alpha = 0.75f))
                            Text(Format.reading(vehicle.reading, vehicle.meter), style = Type.figure(22), color = fg)
                            Text("Tap to update", style = Type.footnote, color = fg.copy(alpha = 0.75f))
                        }
                    }
                }
                if (vehicle.hasAuxMeter) {
                    Box(Modifier.clip(RoundedCornerShape(14.dp)).background(chip)
                        .clickable(onClick = onAux).testTag("vehicle.auxMeter").padding(horizontal = Space.md, vertical = Space.sm)) {
                        Column {
                            Text(vehicle.auxMeterLabel.uppercase(), style = Type.caption, color = fg.copy(alpha = 0.75f), maxLines = 1)
                            Text(Format.reading(vehicle.auxReading, vehicle.auxMeter), style = Type.figure(22), color = fg)
                            Text("Tap to update", style = Type.footnote, color = fg.copy(alpha = 0.75f))
                        }
                    }
                }
            }
        }
    }
}

/** Update the meter, with the iOS typo check for an extra digit. */
@Composable
fun MeterDialog(vehicle: Vehicle, store: GarageStore, onDismiss: () -> Unit) {
    val colors = Keyring.colors
    var text by remember { mutableStateOf("") }
    var warned by remember { mutableStateOf(false) }
    val value = parseNumber(text)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Update ${vehicle.meter.meterName.lowercase()}") },
        text = {
            Column {
                Field(text, { text = it; warned = false }, "Now (${vehicle.meter.short})", number = true, tag = "meter.field")
                Spacer(Modifier.height(Space.xs))
                val note = when {
                    warned && value != null -> "That's ${Format.reading(value - vehicle.reading, vehicle.meter)} more than last time, which is a lot. Check for an extra digit."
                    value != null && value < vehicle.reading -> "That's lower than the last reading of ${Format.reading(vehicle.reading, vehicle.meter)}. It will be saved as a past reading."
                    else -> "Last updated ${vehicle.readingDate?.let { Format.relative(it) } ?: "never"}. The app learns your pace from these and estimates when things come due."
                }
                Text(note, style = Type.footnote, color = if (warned) colors.dueSoon else colors.secondaryInk)
            }
        },
        confirmButton = {
            TextButton(enabled = value != null, onClick = {
                val v = value ?: return@TextButton
                if (!warned && store.isSuspiciousJump(v, vehicle)) {
                    warned = true
                    return@TextButton
                }
                store.updateReading(vehicle, v)
                onDismiss()
            }, modifier = Modifier.testTag("meter.save")) { Text(if (warned) "Save anyway" else "Save", color = colors.ink) }
        },
        dismissButton = { TextButton(onDismiss) { Text("Cancel", color = colors.ink) } },
    )
}

/** Update the second meter. */
@Composable
fun AuxMeterDialog(vehicle: Vehicle, store: GarageStore, onDismiss: () -> Unit) {
    val colors = Keyring.colors
    var text by remember { mutableStateOf("") }
    val value = parseNumber(text)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Update ${vehicle.auxMeterLabel.lowercase()}") },
        text = {
            Column {
                Field(text, { text = it }, "Now (${vehicle.auxMeter.short})", number = true, tag = "auxMeter.field")
                Spacer(Modifier.height(Space.xs))
                Text("Last ${Format.reading(vehicle.auxReading, vehicle.auxMeter)}${vehicle.auxReadingDate?.let { ", ${Format.relative(it)}" } ?: ""}.",
                    style = Type.footnote, color = colors.secondaryInk)
            }
        },
        confirmButton = {
            TextButton(enabled = value != null, onClick = {
                value?.let { store.updateAuxReading(vehicle, it) }
                onDismiss()
            }, modifier = Modifier.testTag("auxMeter.save")) { Text("Save", color = colors.ink) }
        },
        dismissButton = { TextButton(onDismiss) { Text("Cancel", color = colors.ink) } },
    )
}

fun writeCsv(context: Context, store: GarageStore, vehicles: List<Vehicle>): File {
    val dir = File(context.cacheDir, "exports").apply { mkdirs() }
    val name = if (vehicles.size == 1) vehicles[0].displayName else "Maintenance Log"
    return File(dir, "${name.replace(Regex("[^A-Za-z0-9 ]"), "").trim().ifEmpty { "Vehicle" }} service history.csv").apply {
        writeText(CSVExport.csv(store, vehicles))
    }
}

fun shareFile(context: Context, file: File, mime: String) {
    val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
    val send = Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(send, file.nameWithoutExtension).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}
