package com.jackwallner.keyring.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Delete
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.jackwallner.keyring.catalog.AmazonLinks
import com.jackwallner.keyring.catalog.ClubDirectory
import com.jackwallner.keyring.catalog.ClubKind
import com.jackwallner.keyring.catalog.ServiceFinder
import com.jackwallner.keyring.catalog.ServiceGroup
import com.jackwallner.keyring.catalog.UpgradeCatalog
import com.jackwallner.keyring.catalog.UpgradeCategory
import com.jackwallner.keyring.catalog.ValueSource
import com.jackwallner.keyring.data.DueCopy
import com.jackwallner.keyring.data.ValuationKind
import com.jackwallner.keyring.data.Vehicle
import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.Format
import com.jackwallner.keyring.model.MeterUnit
import com.jackwallner.keyring.model.TripCheck
import com.jackwallner.keyring.ui.LocalGraph
import com.jackwallner.keyring.ui.LocalNavigator
import com.jackwallner.keyring.ui.nav.Route
import com.jackwallner.keyring.ui.openUrl
import com.jackwallner.keyring.ui.theme.Card
import com.jackwallner.keyring.ui.theme.Chip
import com.jackwallner.keyring.ui.theme.Divider
import com.jackwallner.keyring.ui.theme.Field
import com.jackwallner.keyring.ui.theme.Keyring
import com.jackwallner.keyring.ui.theme.ListRow
import com.jackwallner.keyring.ui.theme.SectionHeader
import com.jackwallner.keyring.ui.theme.Space
import com.jackwallner.keyring.ui.theme.Symbols
import com.jackwallner.keyring.ui.theme.TopBar
import com.jackwallner.keyring.ui.theme.Type
import com.jackwallner.keyring.ui.theme.parseNumber
import java.util.Locale

/** The US gets the national booking sites and NHTSA's own wording; `RecallRegion.isUS` on iOS. */
val isUSRegion: Boolean get() = Locale.getDefault().country.let { it == "US" || it.isEmpty() }

/** A plain scrolling page with a title, the shape every explore screen shares. */
@Composable
fun ExplorePage(title: String, tag: String, content: LazyListScope.() -> Unit) {
    val nav = LocalNavigator.current
    Column(Modifier.fillMaxSize()) {
        TopBar(title, { nav.pop() })
        LazyColumn(
            contentPadding = PaddingValues(start = Space.margin, end = Space.margin, bottom = Space.xxl),
            verticalArrangement = Arrangement.spacedBy(Space.xs),
            modifier = Modifier.testTag(tag),
            content = content,
        )
    }
}

/** A titled card of outside links; each opens in the browser or the destination's own app, never inside this one. */
fun LazyListScope.linkSection(title: String?, rows: List<LinkItem>, footer: String? = null) {
    if (rows.isEmpty() && footer == null) return
    item(key = "section.$title") {
        Column {
            if (title != null) {
                Spacer(Modifier.height(Space.sm))
                SectionHeader(title)
            }
            if (rows.isNotEmpty()) {
                val context = LocalContext.current
                Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                    rows.forEachIndexed { index, row ->
                        if (index > 0) Divider()
                        ListRow(row.title, row.detail, Symbols.icon(row.symbol), iconTint = Keyring.colors.brass,
                            modifier = Modifier.testTag("link.${row.title}"), onClick = { context.openUrl(row.url) })
                    }
                }
            }
            if (footer != null) {
                Spacer(Modifier.height(Space.xs))
                Text(footer, style = Type.footnote, color = Keyring.colors.secondaryInk)
            }
        }
    }
}

data class LinkItem(val title: String, val detail: String, val symbol: String, val url: String)

// MARK: - Value

/** What it's worth: price guides opened on this vehicle, and the figures the owner noted over time. */
@Composable
fun ValueScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val colors = Keyring.colors
    @Suppress("UNUSED_VARIABLE") val data = graph.data
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    val valuations = graph.garage.valuations(vehicle)
    var adding by remember { mutableStateOf(false) }
    ExplorePage("What it's worth", "value.list") {
        val sources = ValueSource.sources(vehicle).map { LinkItem(it.name, it.detail, "safari", it.url) }
        val withMileage = if (vehicle.meter == MeterUnit.miles && vehicle.reading > 0) " with ${Format.reading(vehicle.reading, vehicle.meter)}" else ""
        linkSection("Check the value", sources,
            if (vehicle.descriptor.isEmpty()) "Add the year, make and model so these open on your exact vehicle."
            else "Opens on the ${vehicle.descriptor}$withMileage. This app isn't affiliated with these guides.")
        item(key = "notes") {
            Column {
                Spacer(Modifier.height(Space.sm))
                SectionHeader("Your notes")
                Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                    if (valuations.size > 1) ValueChart(valuations.reversed().map { it.amount })
                    valuations.forEachIndexed { index, valuation ->
                        if (index > 0 || valuations.size > 1) Divider()
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f).padding(vertical = Space.rowPadding)) {
                                Text(Format.money(valuation.amount), style = Type.figure(17), color = colors.ink)
                                Text(listOfNotNull(valuation.kind.takeIf { it != ValuationKind.estimate }?.title, valuation.source, Format.shortDate(valuation.date))
                                    .joinToString(" · "), style = Type.footnote, color = colors.secondaryInk)
                            }
                            IconButton(onClick = { graph.garage.delete(valuation) }) {
                                Icon(Icons.Outlined.Delete, contentDescription = "Delete value", tint = colors.faintInk)
                            }
                        }
                    }
                    if (valuations.isNotEmpty()) Divider()
                    ListRow("Note a value", null, Symbols.icon("plus"), iconTint = colors.brass, modifier = Modifier.testTag("value.add"), onClick = { adding = true })
                }
                Spacer(Modifier.height(Space.xs))
                Text("Jot down a quote, an offer, an appraisal or your agreed insurance value to watch it over time. Keep the appraisal itself in Documents.",
                    style = Type.footnote, color = colors.secondaryInk)
            }
        }
    }
    if (adding) NoteValueDialog(vehicle) { adding = false }
}

@Composable
private fun ValueChart(values: List<Double>) {
    val brass = Keyring.colors.brass
    Canvas(Modifier.fillMaxWidth().height(120.dp).padding(vertical = Space.sm)) {
        val min = values.min()
        val max = values.max()
        val span = (max - min).takeIf { it > 0 } ?: 1.0
        val points = values.mapIndexed { index, value ->
            Offset(size.width * index / (values.size - 1).coerceAtLeast(1), size.height - ((value - min) / span * size.height).toFloat())
        }
        points.zipWithNext().forEach { (a, b) -> drawLine(brass, a, b, strokeWidth = 3f) }
        points.forEach { drawCircle(brass, 6f, it) }
        drawCircle(brass, 6f, points.last(), style = Stroke(2f))
    }
}

@Composable
private fun NoteValueDialog(vehicle: Vehicle, onDismiss: () -> Unit) {
    val graph = LocalGraph.current
    val colors = Keyring.colors
    var amount by remember { mutableStateOf("") }
    var source by remember { mutableStateOf("") }
    var kind by remember { mutableStateOf(ValuationKind.estimate) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Note a value") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                Field(amount, { amount = it }, "Value", number = true, tag = "value.amount")
                Row(horizontalArrangement = Arrangement.spacedBy(Space.xs), modifier = Modifier.fillMaxWidth()) {
                    ValuationKind.entries.take(2).forEach { Chip(it.title, kind == it, { kind = it }) }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(Space.xs), modifier = Modifier.fillMaxWidth()) {
                    ValuationKind.entries.drop(2).forEach { Chip(if (it == ValuationKind.agreedValue) "Agreed value" else it.title, kind == it, { kind = it }) }
                }
                Field(source, { source = it }, when (kind) {
                    ValuationKind.appraisal -> "Appraiser"
                    ValuationKind.agreedValue -> "Insurer"
                    else -> "Source, such as KBB trade-in"
                }, tag = "value.source")
            }
        },
        confirmButton = {
            TextButton(enabled = parseNumber(amount) != null, modifier = Modifier.testTag("value.save"), onClick = {
                parseNumber(amount)?.let { graph.garage.addValuation(it, source, kind, vehicle) }
                onDismiss()
            }) { Text("Save", color = colors.ink) }
        },
        dismissButton = { TextButton(onDismiss) { Text("Cancel", color = colors.ink) } },
    )
}

// MARK: - Parts and tools

/** The parts and tools for the jobs coming up, most urgent first. */
@Composable
fun GearScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val colors = Keyring.colors
    @Suppress("UNUSED_VARIABLE") val data = graph.data
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    val groups = graph.garage.dues(vehicle).mapNotNull { due ->
        val item = due.task.catalogKey?.let { vehicle.catalogItem(it) } ?: return@mapNotNull null
        if (item.gear.isEmpty()) null else due to item.gear
    }
    ExplorePage("Parts and tools", "gear.list") {
        if (groups.isEmpty()) item {
            Text("Nothing to shop for. Jobs on the schedule with parts or tools show their shopping list here.", style = Type.callout, color = colors.secondaryInk)
        }
        groups.forEach { (due, gear) ->
            val status = due.result.status
            linkSection(due.name + if (status <= DueStatus.DUE_SOON) " · ${status.label}" else "",
                gear.map { suggestion ->
                    val query = AmazonLinks.resolve(suggestion.query, vehicle)
                    LinkItem(suggestion.title, query, "cart", AmazonLinks.search(query))
                })
        }
        item {
            Text(if (AmazonLinks.isAffiliate) "Opens Amazon search. ${AmazonLinks.DISCLOSURE} Check fitment for your exact vehicle before buying."
                else "Opens Amazon search. Check fitment for your exact vehicle before buying.", style = Type.footnote, color = colors.secondaryInk)
        }
    }
}

// MARK: - Upgrades

@Composable
fun UpgradesScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    val upgrades = UpgradeCatalog.upgrades(vehicle.kind, vehicle.powertrain)
    ExplorePage("Upgrades", "upgrades.list") {
        for (category in UpgradeCategory.entries) {
            val items = upgrades.filter { it.category == category }
            if (items.isEmpty()) continue
            linkSection(category.title, items.map { LinkItem(it.title, it.why, it.symbol, AmazonLinks.search(AmazonLinks.resolve(it.query, vehicle))) })
        }
        item {
            Text(if (AmazonLinks.isAffiliate) "Picked from what owners recommend to each other. ${AmazonLinks.DISCLOSURE}"
                else "Picked from what owners recommend to each other. Opens Amazon search.", style = Type.footnote, color = Keyring.colors.secondaryInk)
        }
    }
}

// MARK: - Clubs

@Composable
fun ClubsScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    val clubs = ClubDirectory.clubs(vehicle.kind, vehicle.make, vehicle.model)
    ExplorePage("Clubs and forums", "clubs.list") {
        for (kind in listOf(ClubKind.club, ClubKind.organization, ClubKind.forum, ClubKind.subreddit)) {
            val items = clubs.filter { it.kind == kind }
            if (items.isEmpty()) continue
            val title = when (kind) {
                ClubKind.club -> "Clubs"
                ClubKind.organization -> "Organizations"
                ClubKind.forum -> "Forums"
                ClubKind.subreddit -> "Reddit"
            }
            linkSection(title, items.map { LinkItem(it.name, it.detail, it.kind.symbol, it.url) })
        }
        item {
            Text(if (vehicle.make == null) "Add the make and model to see clubs and forums for yours."
                else "Independent communities. This app isn't affiliated with any of them.", style = Type.footnote, color = Keyring.colors.secondaryInk)
        }
    }
}

// MARK: - Service nearby

/** Shops, mobile mechanics and detailers. Map searches open around wherever the owner is; booking sites open in the browser. */
@Composable
fun ServiceNearbyScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    val services = ServiceFinder.services(vehicle.kind, vehicle.make, isUSRegion)
    ExplorePage("Service nearby", "service.list") {
        for (group in ServiceGroup.entries) {
            val items = services.filter { it.group == group }
            if (items.isEmpty()) continue
            linkSection(group.title, items.map { LinkItem(it.title, it.detail, it.symbol, it.url) })
        }
        item {
            Text("Map searches open your maps app near you. Check reviews and get a written quote before work starts.",
                style = Type.footnote, color = Keyring.colors.secondaryInk)
        }
    }
}

// MARK: - Trip check

/** Before a long trip: what comes due on the way, by the distance and the days away. */
@Composable
fun TripCheckScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val colors = Keyring.colors
    @Suppress("UNUSED_VARIABLE") val data = graph.data
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    var distance by remember { mutableStateOf("") }
    var days by remember { mutableStateOf("7") }
    val dues = graph.garage.dues(vehicle)
    val owed = TripCheck.owed(dues, parseNumber(distance) ?: 0.0, parseNumber(days) ?: 0.0, vehicle.reading)
    ExplorePage("Trip check", "trip.list") {
        item {
            Card {
                if (vehicle.meter.hasReading) {
                    Field(distance, { distance = it }, "Distance (${vehicle.meter.short})", number = true, tag = "trip.distance")
                    Spacer(Modifier.height(Space.xs))
                }
                Field(days, { days = it }, "Days away", number = true, tag = "trip.days")
            }
            Spacer(Modifier.height(Space.xs))
            Text("Includes what's already due and what comes due before you're back.", style = Type.footnote, color = colors.secondaryInk)
            Spacer(Modifier.height(Space.sm))
            SectionHeader(if (owed.isEmpty()) "Ready" else "Do before you go")
        }
        item {
            if (owed.isEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("trip.ready")) {
                    Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = colors.good)
                    Spacer(Modifier.padding(start = Space.xs))
                    Text("Nothing comes due on this trip.", style = Type.callout, color = colors.good)
                }
            } else {
                Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                    owed.forEachIndexed { index, due ->
                        if (index > 0) Divider()
                        ListRow(due.name, DueCopy.dueLine(due), Symbols.icon(due.task.symbol), iconTint = colors.status(due.result.status),
                            modifier = Modifier.testTag("trip.owed.${due.task.catalogKey ?: due.task.id}"),
                            onClick = { nav.push(Route.LogService(vehicle.id, taskId = due.task.id)) })
                    }
                }
            }
        }
    }
}
