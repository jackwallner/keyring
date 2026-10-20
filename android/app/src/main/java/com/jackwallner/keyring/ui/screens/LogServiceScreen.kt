package com.jackwallner.keyring.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import com.jackwallner.keyring.data.FuelUnit
import com.jackwallner.keyring.data.ServiceDraft
import com.jackwallner.keyring.model.EntryKind
import com.jackwallner.keyring.model.Format
import com.jackwallner.keyring.model.UsageEvent
import com.jackwallner.keyring.ui.LocalGraph
import com.jackwallner.keyring.ui.LocalNavigator
import com.jackwallner.keyring.ui.findActivity
import com.jackwallner.keyring.ui.requestReviewIfDue
import com.jackwallner.keyring.ui.theme.Chip
import com.jackwallner.keyring.ui.theme.Eyebrow
import com.jackwallner.keyring.ui.theme.Field
import com.jackwallner.keyring.ui.theme.Keyring
import com.jackwallner.keyring.ui.theme.PrimaryButton
import com.jackwallner.keyring.ui.theme.SecondaryButton
import com.jackwallner.keyring.ui.theme.Space
import com.jackwallner.keyring.ui.theme.TopBar
import com.jackwallner.keyring.ui.theme.Type
import com.jackwallner.keyring.ui.theme.parseNumber
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

private fun Double.plain(): String = if (this % 1.0 == 0.0) toLong().toString() else "%.2f".format(this).trimEnd('0').trimEnd('.')

/** Log a visit: which jobs, when, at what reading and what it cost. Ported from `LogServiceView.swift` and `FuelLogView.swift`. */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun LogServiceScreen(vehicleId: String, entryId: String?, preselectTask: String?, fuel: Boolean, recall: String? = null) {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val colors = Keyring.colors
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    val existing = entryId?.let { id -> graph.data.entries.firstOrNull { it.id == id } }
    val tasks = graph.garage.enabledTasks(vehicle)
    val unit = remember { FuelUnit.current() }
    val zone = ZoneId.systemDefault()

    var kind by rememberSaveable { mutableStateOf(existing?.kind ?: if (fuel) EntryKind.fuel else if (recall != null) EntryKind.recall else EntryKind.service) }
    var selected by rememberSaveable { mutableStateOf(existing?.taskIds ?: listOfNotNull(preselectTask)) }
    var day by rememberSaveable { mutableStateOf((existing?.date ?: Instant.now()).atZone(zone).toLocalDate().toEpochDay()) }
    var reading by rememberSaveable { mutableStateOf(existing?.reading?.takeIf { it >= 0 }?.plain() ?: "") }
    var title by rememberSaveable { mutableStateOf(existing?.title ?: recall?.let { "Recall $it" }.orEmpty()) }
    var cost by rememberSaveable { mutableStateOf(existing?.cost?.takeIf { it > 0 }?.plain().orEmpty()) }
    var shop by rememberSaveable { mutableStateOf(existing?.shop.orEmpty()) }
    var diy by rememberSaveable { mutableStateOf(existing?.isDIY ?: false) }
    var notes by rememberSaveable { mutableStateOf(existing?.notes.orEmpty()) }
    var volume by rememberSaveable { mutableStateOf(existing?.fuelVolume?.takeIf { it > 0 }?.let { unit.fromLiters(it).plain() }.orEmpty()) }
    var unitPrice by rememberSaveable { mutableStateOf(existing?.fuelUnitPrice?.takeIf { it > 0 }?.let { unit.fromPerLiter(it).plain() }.orEmpty()) }
    var event by rememberSaveable { mutableStateOf(existing?.event ?: UsageEvent.choices(vehicle.kind).first()) }
    var pickingDate by remember { mutableStateOf(false) }

    val date = LocalDate.ofEpochDay(day)
    fun save() {
        val instant = if (date == LocalDate.now(zone)) Instant.now() else date.atTime(12, 0).atZone(zone).toInstant()
        val gallons = parseNumber(volume)
        val price = parseNumber(unitPrice)
        var total = parseNumber(cost) ?: 0.0
        if (kind == EntryKind.fuel && total == 0.0 && gallons != null && price != null) total = Math.round(gallons * price * 100) / 100.0
        val draft = ServiceDraft(
            kind = kind, date = instant, reading = parseNumber(reading).takeIf { vehicle.meter.hasReading },
            taskIds = if (kind == EntryKind.service || kind == EntryKind.repair || kind == EntryKind.recall) selected else emptyList(),
            title = title, cost = total, shop = shop, isDIY = diy, notes = notes, recallCampaign = existing?.recallCampaign ?: recall,
            fuelVolume = gallons?.let { unit.toLiters(it) } ?: 0.0, fuelUnitPrice = price?.let { unit.toPerLiter(it) } ?: 0.0,
            event = if (kind == EntryKind.event) event else null,
        )
        graph.garage.log(draft, graph.garage.vehicle(vehicle.id)!!, editing = existing)
        if (existing == null && kind != EntryKind.fuel) requestReviewIfDue(context.findActivity(), graph)
        nav.pop()
    }

    Column(Modifier.fillMaxSize().imePadding()) {
        TopBar(if (existing != null) "Edit entry" else if (kind == EntryKind.fuel) "Fill-up" else "Log service", { nav.pop() }) {
            if (existing != null) {
                IconButton(onClick = { graph.garage.delete(existing); nav.pop() }, modifier = Modifier.testTag("log.delete")) {
                    Icon(Icons.Outlined.Delete, contentDescription = "Delete entry", tint = colors.overdue)
                }
            }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Space.margin), verticalArrangement = Arrangement.spacedBy(Space.sm)) {
            Text(vehicle.displayName, style = Type.footnote, color = colors.secondaryInk)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.xs), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                val kinds = buildList {
                    add(EntryKind.service); add(EntryKind.repair)
                    if (vehicle.powertrain.burnsFuel) add(EntryKind.fuel)
                    add(EntryKind.mod); add(EntryKind.event)
                    if (vehicle.kind.hasNHTSARecords) add(EntryKind.recall)
                }
                kinds.forEach { k -> Chip(k.title, kind == k, { kind = k }, tag = "log.kind.${k.name}") }
            }
            if ((kind == EntryKind.service || kind == EntryKind.repair || kind == EntryKind.recall) && tasks.isNotEmpty()) {
                Eyebrow("What was done")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.xs), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                    tasks.forEach { task ->
                        Chip(task.name, task.id in selected, { selected = if (task.id in selected) selected - task.id else selected + task.id },
                            tag = "log.task.${task.catalogKey ?: task.id}")
                    }
                }
            }
            if (kind == EntryKind.event) {
                Eyebrow("What happened")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
                    UsageEvent.choices(vehicle.kind).forEach { e -> Chip(e.title, event == e, { event = e }) }
                }
                val due = graph.garage.tasks(vehicle).filter { it.isEnabled && it.trigger == event }
                if (due.isNotEmpty()) Text("Brings due: " + due.joinToString(", ") { it.name }, style = Type.footnote, color = colors.secondaryInk)
            }
            if (kind != EntryKind.fuel) Field(title, { title = it }, if (kind == EntryKind.mod) "What went on" else "Title (optional)", tag = "log.title")
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Eyebrow("Date")
                    Text(Format.longDate(date), style = Type.body, color = colors.ink)
                }
                SecondaryButton("Change", { pickingDate = true }, Modifier.weight(0.6f), tag = "log.date")
            }
            if (vehicle.meter.hasReading) {
                Field(reading, { reading = it }, "${vehicle.meter.meterName} (${vehicle.meter.short})", number = true, tag = "log.reading",
                    supporting = "Last ${Format.reading(vehicle.reading, vehicle.meter)}")
            }
            if (kind == EntryKind.fuel) {
                Row(horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
                    Field(volume, { volume = it }, unit.title, number = true, tag = "log.volume", modifier = Modifier.weight(1f))
                    Field(unitPrice, { unitPrice = it }, "Price per ${unit.short}", number = true, tag = "log.unitPrice", modifier = Modifier.weight(1f))
                }
            }
            Field(cost, { cost = it }, if (kind == EntryKind.fuel) "Total (optional)" else "Cost", number = true, tag = "log.cost")
            if (kind != EntryKind.fuel) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("I did it myself", style = Type.body, color = colors.ink, modifier = Modifier.weight(1f))
                    Switch(diy, { diy = it }, modifier = Modifier.testTag("log.diy"),
                        colors = SwitchDefaults.colors(checkedTrackColor = colors.ink, checkedThumbColor = colors.onAction))
                }
            }
            if (!diy) Field(shop, { shop = it }, if (kind == EntryKind.fuel) "Station" else "Shop", tag = "log.shop")
            Field(notes, { notes = it }, "Notes", singleLine = false, tag = "log.notes")
            Spacer(Modifier.height(Space.md))
        }
        Column(Modifier.padding(horizontal = Space.margin, vertical = Space.sm)) {
            PrimaryButton("Save", ::save, tag = "log.save")
        }
    }
    if (pickingDate) {
        val state = rememberDatePickerState(initialSelectedDateMillis = date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { pickingDate = false },
            confirmButton = {
                TextButton({
                    state.selectedDateMillis?.let { day = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toEpochDay() }
                    pickingDate = false
                }) { Text("Done", color = colors.ink) }
            },
            dismissButton = { TextButton({ pickingDate = false }) { Text("Cancel", color = colors.ink) } },
        ) { DatePicker(state) }
    }
}
