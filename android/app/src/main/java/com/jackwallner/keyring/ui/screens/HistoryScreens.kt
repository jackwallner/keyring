package com.jackwallner.keyring.ui.screens

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
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.jackwallner.keyring.data.CostInsights
import com.jackwallner.keyring.model.EntryKind
import com.jackwallner.keyring.model.Format
import com.jackwallner.keyring.ui.LocalGraph
import com.jackwallner.keyring.ui.LocalNavigator
import com.jackwallner.keyring.ui.nav.Route
import com.jackwallner.keyring.ui.theme.Card
import com.jackwallner.keyring.ui.theme.Divider
import com.jackwallner.keyring.ui.theme.Eyebrow
import com.jackwallner.keyring.ui.theme.Keyring
import com.jackwallner.keyring.ui.theme.ListRow
import com.jackwallner.keyring.ui.theme.Space
import com.jackwallner.keyring.ui.theme.Symbols
import com.jackwallner.keyring.ui.theme.TopBar
import com.jackwallner.keyring.ui.theme.Type
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Every entry in the garage, newest first, by month. Ported from `HistoryViews.swift`. */
@Composable
fun HistoryScreen() {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val colors = Keyring.colors
    @Suppress("UNUSED_VARIABLE") val data = graph.data
    val zone = ZoneId.systemDefault()
    val month = DateTimeFormatter.ofPattern("MMMM yyyy", Locale.getDefault())
    val groups = graph.garage.allEntries().groupBy { it.date.atZone(zone).toLocalDate().withDayOfMonth(1) }
    Column(Modifier.fillMaxSize()) {
        TopBar("History", { nav.pop() })
        LazyColumn(contentPadding = PaddingValues(horizontal = Space.margin, vertical = Space.xs), modifier = Modifier.testTag("history.list")) {
            if (groups.isEmpty()) item { Text("Nothing logged yet. Every job you log, on every vehicle, shows here.", style = Type.callout, color = colors.secondaryInk) }
            groups.forEach { (start, entries) ->
                item(key = start.toString()) {
                    Spacer(Modifier.height(Space.md))
                    Row(Modifier.fillMaxWidth().padding(bottom = Space.xs)) {
                        Eyebrow(start.format(month), modifier = Modifier.weight(1f))
                        val spent = entries.sumOf { it.cost }
                        if (spent > 0) Eyebrow(Format.money(spent))
                    }
                    Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                        entries.forEachIndexed { index, entry ->
                            if (index > 0) Divider()
                            val vehicle = graph.garage.vehicle(entry.vehicleId)
                            ListRow(
                                title = entry.title,
                                subtitle = listOfNotNull(vehicle?.displayName, Format.shortDate(entry.date), entry.shop ?: if (entry.isDIY) "DIY" else null).joinToString(" · "),
                                icon = Symbols.entry(entry.kind),
                                trailing = entry.cost.takeIf { it > 0 }?.let { Format.money(it) },
                                onClick = { if (vehicle != null) nav.push(Route.LogService(vehicle.id, entryId = entry.id)) },
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Pro: what it costs to keep running, by kind of work. */
@Composable
fun InsightsScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val colors = Keyring.colors
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    if (!graph.store.isPro) {
        nav.replace(Route.Paywall(com.jackwallner.keyring.model.ProFeature.insights))
        return
    }
    val summary = CostInsights.summary(graph.garage, vehicle)
    val byJob = graph.garage.entries(vehicle).filter { it.kind.isUpkeep && it.cost > 0 }
        .groupBy { it.title }.mapValues { (_, list) -> list.sumOf { it.cost } }.entries.sortedByDescending { it.value }.take(6)
    Column(Modifier.fillMaxSize()) {
        TopBar("Where the money goes", { nav.pop() })
        Column(Modifier.padding(horizontal = Space.margin), verticalArrangement = Arrangement.spacedBy(Space.stackGap)) {
            Card(Modifier.testTag("insights.summary")) {
                Eyebrow("To keep it running")
                Text(Format.money(summary.upkeep + summary.fuel), style = Type.figure(34, androidx.compose.ui.text.font.FontWeight.Bold), color = colors.ink)
                Text("${Format.money(summary.upkeep)} upkeep · ${Format.money(summary.fuel)} ${EntryKind.fuel.title.lowercase()}s", style = Type.footnote, color = colors.secondaryInk)
                summary.perUnit?.let {
                    Spacer(Modifier.height(Space.sm))
                    Text("${Format.unitPrice(it)} per ${vehicle.meter.short}", style = Type.headline, color = colors.ink)
                    Text("Upkeep and fuel over the distance in the log", style = Type.footnote, color = colors.secondaryInk)
                }
                if (summary.mods > 0) {
                    Spacer(Modifier.height(Space.sm))
                    Text("${Format.money(summary.mods)} on mods, kept apart", style = Type.footnote, color = colors.secondaryInk)
                }
            }
            if (byJob.isNotEmpty()) {
                Eyebrow("Biggest jobs")
                Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                    byJob.forEachIndexed { index, (title, total) ->
                        if (index > 0) Divider()
                        ListRow(title, trailing = Format.money(total))
                    }
                }
            }
        }
    }
}
