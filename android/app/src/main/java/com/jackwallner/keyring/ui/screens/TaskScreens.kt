package com.jackwallner.keyring.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import com.jackwallner.keyring.data.DueCopy
import com.jackwallner.keyring.catalog.AmazonLinks
import com.jackwallner.keyring.model.Format
import com.jackwallner.keyring.ui.LocalGraph
import com.jackwallner.keyring.ui.LocalNavigator
import com.jackwallner.keyring.ui.nav.Route
import com.jackwallner.keyring.ui.openUrl
import com.jackwallner.keyring.ui.theme.Card
import com.jackwallner.keyring.ui.theme.Divider
import com.jackwallner.keyring.ui.theme.Eyebrow
import com.jackwallner.keyring.ui.theme.Field
import com.jackwallner.keyring.ui.theme.Keyring
import com.jackwallner.keyring.ui.theme.ListRow
import com.jackwallner.keyring.ui.theme.PrimaryButton
import com.jackwallner.keyring.ui.theme.SecondaryButton
import com.jackwallner.keyring.ui.theme.Space
import com.jackwallner.keyring.ui.theme.StatusDot
import com.jackwallner.keyring.ui.theme.Symbols
import com.jackwallner.keyring.ui.theme.TopBar
import com.jackwallner.keyring.ui.theme.Type
import com.jackwallner.keyring.ui.theme.parseNumber
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

/** One job: when it comes due, its interval, when it was last done, and the parts for it. Ported from `ScheduleViews.swift`. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TaskScreen(vehicleId: String, taskId: String) {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val colors = Keyring.colors
    @Suppress("UNUSED_VARIABLE") val data = graph.data
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    val due = graph.garage.dues(vehicle).firstOrNull { it.task.id == taskId }
    val task = due?.task ?: graph.data.tasks.firstOrNull { it.id == taskId } ?: return
    val item = task.catalogKey?.let { vehicle.catalogItem(it) }
    var name by rememberSaveable { mutableStateOf(task.name) }
    var distance by rememberSaveable { mutableStateOf(task.intervalDistance.takeIf { it > 0 }?.toLong()?.toString().orEmpty()) }
    var months by rememberSaveable { mutableStateOf(task.intervalMonths.takeIf { it > 0 }?.toString().orEmpty()) }
    var notes by rememberSaveable { mutableStateOf(task.notes.orEmpty()) }
    var settingLast by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().imePadding()) {
        TopBar(task.name, { nav.pop() })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Space.margin), verticalArrangement = Arrangement.spacedBy(Space.sm)) {
            if (due != null) {
                Card {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        StatusDot(due.result.status)
                        Spacer(Modifier.padding(start = Space.xs))
                        Text(due.result.status.label, style = Type.subheadlineBold, color = colors.status(due.result.status))
                    }
                    Text(DueCopy.dueLine(due), style = Type.title(22), color = colors.ink, modifier = Modifier.testTag("task.dueLine"))
                    val last = due.lastDate?.let { "Last done ${Format.shortDate(it)}" + (due.lastReading?.let { r -> " at ${Format.reading(r, vehicle.meter)}" } ?: "") }
                    Text(last ?: "No record yet", style = Type.footnote, color = colors.secondaryInk)
                }
            }
            SecondaryButton(if (due?.lastDate == null) "When was it last done?" else "Change when it was last done", { settingLast = true }, tag = "task.setLast")
            PrimaryButton("Log it now", { nav.push(Route.LogService(vehicle.id, taskId = task.id)) }, tag = "task.log")
            item?.let { catalog ->
                Spacer(Modifier.height(Space.xs))
                Text(catalog.detail(vehicle.meter), style = Type.callout, color = colors.secondaryInk)
                Text(catalog.difficulty.title, style = Type.footnote, color = colors.faintInk)
            }
            Eyebrow("Interval")
            Field(name, { name = it }, "Name", tag = "task.name")
            Row(horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
                if (vehicle.meter.hasReading) Field(distance, { distance = it }, "Every (${vehicle.meter.short})", number = true, tag = "task.distance", modifier = Modifier.weight(1f))
                Field(months, { months = it.filter(Char::isDigit) }, "Or months", number = true, tag = "task.months", modifier = Modifier.weight(1f))
            }
            Text(Format.interval(parseNumber(distance) ?: 0.0, months.toIntOrNull() ?: 0, vehicle.meter, task.trigger), style = Type.footnote, color = colors.secondaryInk)
            Field(notes, { notes = it }, "Notes", singleLine = false)
            SecondaryButton("Save changes", {
                graph.garage.updateTask(task, name, parseNumber(distance) ?: 0.0, months.toIntOrNull() ?: 0, notes)
                nav.pop()
            }, tag = "task.save")
            if (item != null && item.gear.isNotEmpty()) {
                Spacer(Modifier.height(Space.xs))
                Eyebrow("Parts and tools")
                Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                    item.gear.forEachIndexed { index, gear ->
                        if (index > 0) Divider()
                        ListRow(gear.title, "Search on Amazon", Symbols.icon("link"), onClick = {
                            context.openUrl(AmazonLinks.search(AmazonLinks.resolve(gear.query, vehicle)))
                        })
                    }
                }
            }
            TextButton(onClick = { graph.garage.remove(task); nav.pop() }, modifier = Modifier.fillMaxWidth().testTag("task.remove")) {
                Text("Remove from schedule", style = Type.subheadlineBold, color = colors.overdue)
            }
            Spacer(Modifier.height(Space.lg))
        }
    }
    if (settingLast) {
        val state = rememberDatePickerState(initialSelectedDateMillis = (due?.lastDate ?: Instant.now()).toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { settingLast = false },
            confirmButton = {
                TextButton({
                    state.selectedDateMillis?.let { millis ->
                        val day = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                        val date = day.atTime(12, 0).atZone(ZoneId.systemDefault()).toInstant()
                        // A date in the last few weeks most likely came at today's reading.
                        val recent = Instant.now().toEpochMilli() - date.toEpochMilli() < 45L * 86_400_000L
                        graph.garage.setBaseline(task, date, if (recent && vehicle.meter.hasReading) vehicle.reading else null)
                    }
                    settingLast = false
                }, modifier = Modifier.testTag("task.setLast.done")) { Text("Done", color = colors.ink) }
            },
            dismissButton = { TextButton({ settingLast = false }) { Text("Cancel", color = colors.ink) } },
        ) { DatePicker(state) }
    }
}

/** Jobs that apply to this vehicle but aren't on its schedule yet. */
@Composable
fun CatalogScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val colors = Keyring.colors
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    val available = remember(graph.data) { graph.garage.availableCatalogItems(vehicle) }
    var picked by remember { mutableStateOf(setOf<String>()) }
    var custom by rememberSaveable { mutableStateOf("") }
    Column(Modifier.fillMaxSize().imePadding()) {
        TopBar("Add from the catalog", { nav.pop() })
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(horizontal = Space.margin, vertical = Space.xs)) {
            if (available.isEmpty()) item { Text("Every catalog job for this ${vehicle.kind.title.lowercase()} is already on the schedule.", style = Type.callout, color = colors.secondaryInk) }
            items(available, key = { it.key }) { item ->
                Row(Modifier.fillMaxWidth().padding(vertical = Space.xxs), verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(item.key in picked, { picked = if (item.key in picked) picked - item.key else picked + item.key },
                        colors = CheckboxDefaults.colors(checkedColor = colors.ink), modifier = Modifier.testTag("catalog.${item.key}"))
                    Column(Modifier.weight(1f)) {
                        Text(item.name, style = Type.subheadlineBold, color = colors.ink)
                        Text(Format.interval(item.distanceInterval(vehicle.meter) ?: 0.0, item.months ?: 0, vehicle.meter, item.trigger),
                            style = Type.footnote, color = colors.secondaryInk)
                    }
                }
            }
            item {
                Spacer(Modifier.height(Space.lg))
                Eyebrow("Something else")
                Field(custom, { custom = it }, "Job name", tag = "catalog.custom")
            }
        }
        Column(Modifier.padding(horizontal = Space.margin, vertical = Space.sm)) {
            PrimaryButton("Add to schedule", {
                graph.garage.addCatalogItems(available.filter { it.key in picked }, vehicle)
                if (custom.isNotBlank()) graph.garage.addCustomTask(custom, 0.0, 12, graph.garage.vehicle(vehicle.id)!!)
                nav.pop()
            }, enabled = picked.isNotEmpty() || custom.isNotBlank(), tag = "catalog.add")
        }
    }
}
