package com.jackwallner.keyring.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.jackwallner.keyring.data.LookupException
import com.jackwallner.keyring.data.NHTSAClient
import com.jackwallner.keyring.data.NewVehicle
import com.jackwallner.keyring.data.Vehicle
import com.jackwallner.keyring.model.FinalDrive
import com.jackwallner.keyring.model.Format
import com.jackwallner.keyring.model.MeterUnit
import com.jackwallner.keyring.model.Powertrain
import com.jackwallner.keyring.model.ProFeature
import com.jackwallner.keyring.model.VehicleKind
import com.jackwallner.keyring.model.VehicleTint
import com.jackwallner.keyring.model.VehicleTrait
import com.jackwallner.keyring.ui.LocalGraph
import com.jackwallner.keyring.ui.LocalNavigator
import com.jackwallner.keyring.ui.nav.Route
import com.jackwallner.keyring.ui.theme.Chip
import com.jackwallner.keyring.ui.theme.Eyebrow
import com.jackwallner.keyring.ui.theme.Field
import com.jackwallner.keyring.ui.theme.Keyring
import com.jackwallner.keyring.ui.theme.PrimaryButton
import com.jackwallner.keyring.ui.theme.SecondaryButton
import com.jackwallner.keyring.ui.theme.Space
import com.jackwallner.keyring.ui.theme.Symbols
import com.jackwallner.keyring.ui.theme.TopBar
import com.jackwallner.keyring.ui.theme.Type
import com.jackwallner.keyring.ui.theme.color
import com.jackwallner.keyring.ui.theme.parseNumber
import kotlinx.coroutines.launch

/** Kind first, then the details that shape its schedule. Ported from `AddVehicleFlow.swift`. */
@Composable
fun AddVehicleScreen() {
    val nav = LocalNavigator.current
    var kind by rememberSaveable { mutableStateOf<VehicleKind?>(null) }
    val chosen = kind
    if (chosen == null) {
        KindPicker(onBack = { nav.pop() }) { kind = it }
    } else {
        VehicleDetailsForm(chosen, existing = null, onBack = { kind = null })
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun KindPicker(onBack: () -> Unit, onPick: (VehicleKind) -> Unit) {
    val colors = Keyring.colors
    Column(Modifier.fillMaxSize()) {
        TopBar("Add a vehicle", onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Space.margin).padding(bottom = Space.xxl)) {
            Text("What is it?", style = Type.title(28), color = colors.ink)
            Spacer(Modifier.height(Space.xs))
            Text("The kind picks the meter and the schedule. You can change everything later.", style = Type.callout, color = colors.secondaryInk)
            VehicleKind.pickerSections.forEach { (title, kinds) ->
                Spacer(Modifier.height(Space.lg))
                Eyebrow(title)
                Spacer(Modifier.height(Space.xs))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.xs), verticalArrangement = Arrangement.spacedBy(Space.xs), maxItemsInEachRow = 3) {
                    kinds.forEach { kind ->
                        Column(
                            Modifier.weight(1f).heightIn(min = 88.dp).clip(RoundedCornerShape(Space.smallRadius)).background(colors.surface)
                                .border(1.dp, colors.hairline, RoundedCornerShape(Space.smallRadius))
                                .clickable(role = Role.Button) { onPick(kind) }.testTag("add.kind.${kind.name}").padding(Space.sm),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center,
                        ) {
                            Icon(Symbols.kind(kind), contentDescription = null, tint = VehicleTint.defaultTint(kind).color(), modifier = Modifier.size(28.dp))
                            Spacer(Modifier.height(Space.xxs))
                            Text(kind.title, style = Type.footnote.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = colors.ink,
                                textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                        }
                    }
                    repeat((3 - kinds.size % 3) % 3) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

/** The details form, used for a new vehicle and for editing one. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun VehicleDetailsForm(kind: VehicleKind, existing: Vehicle?, onBack: () -> Unit) {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val colors = Keyring.colors
    val scope = rememberCoroutineScope()
    var year by rememberSaveable { mutableStateOf(existing?.year?.takeIf { it > 0 }?.toString().orEmpty()) }
    var make by rememberSaveable { mutableStateOf(existing?.make.orEmpty()) }
    var model by rememberSaveable { mutableStateOf(existing?.model.orEmpty()) }
    var nickname by rememberSaveable { mutableStateOf(existing?.nickname.orEmpty()) }
    var vin by rememberSaveable { mutableStateOf(existing?.vin.orEmpty()) }
    var plate by rememberSaveable { mutableStateOf(existing?.plate.orEmpty()) }
    var powertrain by rememberSaveable { mutableStateOf(existing?.powertrain ?: kind.defaultPowertrain) }
    var meter by rememberSaveable { mutableStateOf(existing?.meter ?: kind.defaultMeter) }
    var reading by rememberSaveable { mutableStateOf(existing?.reading?.takeIf { it > 0 }?.let { if (it % 1.0 == 0.0) it.toLong().toString() else it.toString() }.orEmpty()) }
    var yearlyUse by rememberSaveable { mutableStateOf(existing?.yearlyUse ?: 0.0) }
    var traits by remember { mutableStateOf(existing?.traits ?: emptySet()) }
    var drive by rememberSaveable { mutableStateOf(existing?.drive) }
    var tint by rememberSaveable { mutableStateOf(existing?.tint ?: VehicleTint.defaultTint(kind)) }
    var auxName by rememberSaveable { mutableStateOf(existing?.auxMeterName.orEmpty()) }
    var auxMeter by rememberSaveable { mutableStateOf(existing?.auxMeter ?: MeterUnit.hours) }
    var photo by remember { mutableStateOf<ByteArray?>(null) }
    var photoRemoved by remember { mutableStateOf(false) }
    val context = androidx.compose.ui.platform.LocalContext.current
    val photoPicker = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia(),
    ) { uri -> uri?.let { com.jackwallner.keyring.ui.PickedFiles.read(context, it) }?.second?.let { photo = it; photoRemoved = false } }
    var decoding by remember { mutableStateOf(false) }
    var vinMessage by remember { mutableStateOf<String?>(null) }

    fun save() {
        val parsedReading = parseNumber(reading) ?: 0.0
        if (existing == null) {
            if (!ProFeature.canAddVehicle(graph.garage.activeVehicles.size, graph.store.isPro)) {
                nav.replace(Route.Paywall(ProFeature.unlimitedVehicles))
                return
            }
            val added = graph.garage.addVehicle(NewVehicle(
                kind = kind, powertrain = powertrain, meter = meter, year = year.toIntOrNull() ?: 0, make = make, model = model,
                nickname = nickname, vin = vin, plate = plate, reading = parsedReading, yearlyUse = yearlyUse, traits = traits,
                drive = drive, tint = tint, auxMeterName = auxName, auxMeter = auxMeter,
            ))
            photo?.let { graph.garage.setPhoto(added, it) }
            nav.replace(Route.Vehicle(added.id))
        } else {
            graph.garage.updateVehicle(existing.copy(
                year = year.toIntOrNull() ?: 0, make = make.trim().ifEmpty { null }, model = model.trim().ifEmpty { null },
                nickname = nickname.trim().ifEmpty { null }, vin = vin.trim().uppercase().ifEmpty { null },
                plate = plate.trim().uppercase().ifEmpty { null }, powertrain = powertrain, yearlyUse = yearlyUse,
                traits = traits, drive = drive, tint = tint,
            ))
            if (parsedReading > existing.reading) graph.garage.updateReading(graph.garage.vehicle(existing.id)!!, parsedReading)
            val name = auxName.trim().ifEmpty { null }
            if (name != existing.auxMeterName || (name != null && auxMeter != existing.auxMeter)) {
                graph.garage.setAuxMeter(graph.garage.vehicle(existing.id)!!, name, auxMeter)
            }
            when {
                photo != null -> graph.garage.setPhoto(graph.garage.vehicle(existing.id)!!, photo)
                photoRemoved -> graph.garage.setPhoto(graph.garage.vehicle(existing.id)!!, null)
            }
            nav.pop()
        }
    }

    Column(Modifier.fillMaxSize().imePadding()) {
        TopBar(if (existing == null) kind.title else "Edit ${existing.displayName}", onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Space.margin), verticalArrangement = Arrangement.spacedBy(Space.sm)) {
            if (kind.hasNHTSARecords) {
                Field(vin, { vin = it; vinMessage = null }, kind.identifierLabel, tag = "add.vin",
                    supporting = vinMessage ?: "Optional. Fills in the year, make and model from NHTSA.")
                if (NHTSAClient.normalizedVIN(vin) != null) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        SecondaryButton(if (decoding) "Looking it up" else "Fill in from VIN", {
                            decoding = true
                            scope.launch {
                                try {
                                    val decoded = NHTSAClient.decode(vin)
                                    decoded.year?.let { year = it.toString() }
                                    if (decoded.make.isNotEmpty()) make = decoded.make
                                    if (decoded.model.isNotEmpty()) model = decoded.model
                                    decoded.powertrain?.takeIf { it in kind.powertrainChoices }?.let { powertrain = it }
                                    vinMessage = decoded.summary.ifEmpty { null } ?: "Found it."
                                } catch (error: LookupException) {
                                    vinMessage = error.error.message
                                } finally {
                                    decoding = false
                                }
                            }
                        }, tag = "add.decode", modifier = Modifier.weight(1f))
                        if (decoding) CircularProgressIndicator(Modifier.padding(start = Space.sm).size(24.dp), color = colors.ink, strokeWidth = 2.dp)
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
                Field(year, { year = it.filter(Char::isDigit).take(4) }, "Year", number = true, tag = "add.year", modifier = Modifier.width(110.dp))
                Field(make, { make = it }, "Make", tag = "add.make", modifier = Modifier.weight(1f))
            }
            Field(model, { model = it }, "Model", tag = "add.model")
            Field(nickname, { nickname = it }, "Nickname (optional)", tag = "add.nickname")
            if (kind.powertrainChoices.size > 1) {
                Eyebrow("Powertrain")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.xs), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                    kind.powertrainChoices.forEach { p -> Chip(p.title, powertrain == p, { powertrain = p }, tag = "add.powertrain.${p.name}") }
                }
            }
            if (existing == null) {
                Eyebrow("Meter")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.xs), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                    MeterUnit.entries.forEach { m -> Chip(m.title, meter == m, { meter = m }, tag = "add.meter.${m.name}") }
                }
            }
            if (meter.hasReading) {
                Field(reading, { reading = it }, "${meter.meterName} now (${meter.short})", number = true, tag = "add.reading")
                Eyebrow("How much is it used a year?")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.xs), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                    meter.yearlyUseChoices.forEach { choice ->
                        Chip(Format.reading(choice, meter), yearlyUse == choice, { yearlyUse = if (yearlyUse == choice) 0.0 else choice })
                    }
                }
            }
            val traitChoices = VehicleTrait.choices(kind)
            if (traitChoices.isNotEmpty()) {
                Eyebrow("Anything special?")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.xs), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                    traitChoices.forEach { t -> Chip(t.title, t in traits, { traits = if (t in traits) traits - t else traits + t }, tag = "add.trait.${t.name}") }
                }
            }
            if (kind == VehicleKind.motorcycle && powertrain != Powertrain.electric) {
                Eyebrow("Final drive")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
                    FinalDrive.entries.forEach { d -> Chip(d.title, (drive ?: FinalDrive.chain) == d, { drive = d }) }
                }
            }
            if (kind.hasNHTSARecords || kind.registrationLabel != "Plate") Field(plate, { plate = it }, kind.registrationLabel + " (optional)")
            Eyebrow("Second meter")
            Field(auxName, { auxName = it }, "Name (optional)", tag = "add.auxName",
                supporting = "A generator, track hours or trail miles, counted apart from the ${meter.meterName.lowercase()}.")
            if (auxName.isNotBlank()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.xs), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                    listOf(MeterUnit.hours, MeterUnit.miles, MeterUnit.kilometers).forEach { m ->
                        Chip(if (m == MeterUnit.hours) "Hours" else m.title, auxMeter == m, { auxMeter = m }, tag = "add.auxMeter.${m.name}")
                    }
                }
            }
            Eyebrow("Photo")
            val hasPhoto = photo != null || (existing?.photo != null && !photoRemoved)
            Row(horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
                SecondaryButton(if (hasPhoto) "Change photo" else "Add a photo", {
                    photoPicker.launch(androidx.activity.result.PickVisualMediaRequest(androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia.ImageOnly))
                }, Modifier.weight(1f), tag = "add.photo")
                if (hasPhoto) SecondaryButton("Remove", { photo = null; photoRemoved = true }, Modifier.weight(0.6f))
            }
            Eyebrow("Color")
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.xs), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                VehicleTint.entries.forEach { t ->
                    val selected = t == tint
                    androidx.compose.foundation.layout.Box(
                        Modifier.size(40.dp).clip(androidx.compose.foundation.shape.CircleShape).background(t.color())
                            .border(if (selected) 3.dp else 1.dp, if (selected) colors.ink else colors.hairline, androidx.compose.foundation.shape.CircleShape)
                            .clickable(role = Role.RadioButton) { tint = t }
                            .then(Modifier.padding(2.dp)),
                    )
                }
            }
            Spacer(Modifier.height(Space.md))
        }
        Column(Modifier.padding(horizontal = Space.margin, vertical = Space.sm)) {
            PrimaryButton(if (existing == null) "Add to garage" else "Save", ::save, tag = "add.save")
        }
    }
}

@Composable
fun EditVehicleScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val vehicle = graph.garage.vehicle(vehicleId) ?: run { nav.pop(); return }
    VehicleDetailsForm(vehicle.kind, vehicle, onBack = { nav.pop() })
}
