package com.jackwallner.keyring.ui.screens

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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.jackwallner.keyring.data.DueCopy
import com.jackwallner.keyring.data.Vehicle
import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.Format
import com.jackwallner.keyring.model.ProFeature
import com.jackwallner.keyring.ui.LocalGraph
import com.jackwallner.keyring.ui.LocalNavigator
import com.jackwallner.keyring.ui.nav.Route
import com.jackwallner.keyring.ui.theme.Eyebrow
import com.jackwallner.keyring.ui.theme.Keyring
import com.jackwallner.keyring.ui.theme.PrimaryButton
import com.jackwallner.keyring.ui.theme.SecondaryButton
import com.jackwallner.keyring.ui.theme.Space
import com.jackwallner.keyring.ui.theme.StatusDot
import com.jackwallner.keyring.ui.theme.Symbols
import com.jackwallner.keyring.ui.theme.Type
import com.jackwallner.keyring.ui.theme.color
import com.jackwallner.keyring.ui.theme.foreground
import com.jackwallner.keyring.ui.theme.outline

/** Every vehicle as a key tag, most urgent first in its own color. Ported from `GarageView.swift`. */
@Composable
fun GarageScreen() {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val colors = Keyring.colors
    @Suppress("UNUSED_VARIABLE") val data = graph.data
    val vehicles = graph.garage.activeVehicles
    val addVehicle = {
        if (ProFeature.canAddVehicle(vehicles.size, graph.store.isPro)) nav.push(Route.AddVehicle)
        else nav.push(Route.Paywall(ProFeature.unlimitedVehicles))
    }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(start = Space.margin, end = Space.xs, top = Space.xs), verticalAlignment = Alignment.CenterVertically) {
            Text("Maintenance Log", style = Type.title(30), color = colors.ink, modifier = Modifier.weight(1f))
            IconButton(onClick = { nav.push(Route.History) }, modifier = Modifier.testTag("garage.history")) {
                Icon(Icons.Outlined.History, contentDescription = "History", tint = colors.ink)
            }
            IconButton(onClick = { nav.push(Route.Settings) }, modifier = Modifier.testTag("garage.settings")) {
                Icon(Icons.Outlined.Settings, contentDescription = "Settings", tint = colors.ink)
            }
            IconButton(onClick = addVehicle, modifier = Modifier.testTag("garage.add")) {
                Icon(Icons.Outlined.Add, contentDescription = "Add a vehicle", tint = colors.ink)
            }
        }
        if (vehicles.isEmpty()) {
            EmptyGarage(addVehicle)
            return@Column
        }
        val attention = vehicles.flatMap { v -> graph.garage.dues(v).filter { it.result.status <= DueStatus.DUE_SOON }.map { v to it } }
        LazyColumn(
            contentPadding = PaddingValues(start = Space.margin, end = Space.margin, top = Space.sm, bottom = Space.xxl),
            verticalArrangement = Arrangement.spacedBy(Space.stackGap),
            modifier = Modifier.testTag("garage.list"),
        ) {
            items(vehicles, key = { it.id }) { vehicle -> KeyTag(vehicle) { nav.push(Route.Vehicle(vehicle.id)) } }
            if (attention.isNotEmpty()) {
                item {
                    Spacer(Modifier.height(Space.md))
                    Eyebrow(if (attention.any { it.second.result.status == DueStatus.OVERDUE }) "Needs attention" else "Coming up", color = colors.brass)
                }
                items(attention.take(6), key = { "a-" + it.second.task.id }) { (vehicle, due) ->
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(Space.smallRadius)).background(colors.surface)
                            .clickable { nav.push(Route.LogService(vehicle.id, taskId = due.task.id)) }
                            .padding(Space.md),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(Space.sm),
                    ) {
                        StatusDot(due.result.status)
                        Column(Modifier.weight(1f)) {
                            Text("${vehicle.displayName}: ${due.name}", style = Type.subheadlineBold, color = colors.ink)
                            Text(DueCopy.dueLine(due), style = Type.footnote, color = colors.secondaryInk)
                        }
                        Text("Log", style = Type.subheadlineBold, color = colors.brass)
                    }
                }
            }
            item {
                Spacer(Modifier.height(Space.sm))
                SecondaryButton("Add a vehicle", addVehicle, tag = "garage.addBottom")
                if (!graph.store.isPro && vehicles.size >= ProFeature.FREE_VEHICLE_LIMIT) {
                    Text("Your first two vehicles are free forever. Pro adds the rest.", style = Type.footnote, color = colors.secondaryInk,
                        modifier = Modifier.padding(top = Space.xs))
                }
            }
        }
    }
}

@Composable
private fun EmptyGarage(add: () -> Unit) {
    val colors = Keyring.colors
    Column(Modifier.fillMaxSize().padding(Space.xl), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Symbols.kind(com.jackwallner.keyring.model.VehicleKind.car), contentDescription = null, tint = colors.faintInk, modifier = Modifier.size(56.dp))
        Spacer(Modifier.height(Space.md))
        Text("Your garage is empty", style = Type.title(22), color = colors.ink)
        Spacer(Modifier.height(Space.xs))
        Text("Add a car, truck, boat, bike, RV or plane. Its maintenance schedule is built for you.",
            style = Type.callout, color = colors.secondaryInk, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        Spacer(Modifier.height(Space.lg))
        PrimaryButton("Add a vehicle", add, tag = "garage.empty.add")
    }
}

/** A vehicle's card: its color, its name, its meter and what's next. */
@Composable
fun KeyTag(vehicle: Vehicle, onClick: () -> Unit) {
    val graph = LocalGraph.current
    val dues = graph.garage.dues(vehicle)
    val headline = graph.garage.headline(vehicle)
    val status = DueCopy.cardStatus(dues, headline)
    val tint = vehicle.tint
    val fg = tint.foreground()
    val shape = RoundedCornerShape(Space.radius)
    Column(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 168.dp)
            .clip(shape)
            .background(tint.color())
            .let { m -> tint.outline()?.let { m.border(1.5.dp, it, shape) } ?: m }
            .clickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = listOf(vehicle.displayName, vehicle.descriptor, status).filter { it.isNotEmpty() }.joinToString(", ") }
            .testTag("garage.card.${vehicle.id}")
            .padding(Space.lg),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(12.dp).clip(CircleShape).background(fg.copy(alpha = 0.35f)))
            Spacer(Modifier.size(Space.xs))
            Text(vehicle.descriptor.uppercase(), style = Type.caption, color = fg.copy(alpha = 0.8f), maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f))
            Icon(Symbols.kind(vehicle.kind), contentDescription = null, tint = fg.copy(alpha = 0.85f), modifier = Modifier.size(26.dp))
        }
        Spacer(Modifier.height(Space.sm))
        Text(vehicle.displayName, style = Type.title(28), color = fg, maxLines = 2, overflow = TextOverflow.Ellipsis)
        if (vehicle.meter.hasReading) {
            Text(Format.reading(vehicle.reading, vehicle.meter), style = Type.figure(17, androidx.compose.ui.text.font.FontWeight.Medium), color = fg.copy(alpha = 0.85f))
        }
        Spacer(Modifier.weight(1f, fill = false).height(Space.md))
        Row(
            Modifier.clip(RoundedCornerShape(14.dp)).background(Color.Black.copy(alpha = if (tint.isLight) 0.08f else 0.22f))
                .padding(horizontal = Space.sm, vertical = Space.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            StatusDot(headline.status)
            Spacer(Modifier.size(Space.xs))
            Text(status, style = Type.footnote.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = fg)
        }
    }
}
