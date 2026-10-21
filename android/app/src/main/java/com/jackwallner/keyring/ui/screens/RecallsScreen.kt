package com.jackwallner.keyring.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.jackwallner.keyring.data.LookupException
import com.jackwallner.keyring.data.NHTSAClient
import com.jackwallner.keyring.data.Recall
import com.jackwallner.keyring.data.RecallMatcher
import com.jackwallner.keyring.model.Format
import com.jackwallner.keyring.ui.LocalGraph
import com.jackwallner.keyring.ui.LocalNavigator
import com.jackwallner.keyring.ui.nav.Route
import com.jackwallner.keyring.ui.openUrl
import com.jackwallner.keyring.ui.theme.Card
import com.jackwallner.keyring.ui.theme.Eyebrow
import com.jackwallner.keyring.ui.theme.Keyring
import com.jackwallner.keyring.ui.theme.LinkButton
import com.jackwallner.keyring.ui.theme.SecondaryButton
import com.jackwallner.keyring.ui.theme.Space
import com.jackwallner.keyring.ui.theme.TopBar
import com.jackwallner.keyring.ui.theme.Type

/** NHTSA recalls for the year, make and model, closed from the log. Ported from `ExploreViews.swift`. */
@Composable
fun RecallsScreen(vehicleId: String) {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val colors = Keyring.colors
    val vehicle = graph.garage.vehicle(vehicleId) ?: return
    var recalls by remember { mutableStateOf<List<Recall>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    val ready = vehicle.year > 0 && !vehicle.make.isNullOrBlank() && !vehicle.model.isNullOrBlank()
    LaunchedEffect(attempt) {
        if (!ready) return@LaunchedEffect
        error = null
        try {
            recalls = NHTSAClient.recalls(vehicle.year, vehicle.make!!, vehicle.model!!)
        } catch (e: LookupException) {
            error = e.error.message
        }
    }
    val entries = graph.garage.entries(vehicle)
    @Suppress("UNUSED_VARIABLE") val data = graph.data
    val check = graph.vinChecks.check(vehicle)
    val listed = recalls?.let { all -> if (check == null) all else all.filter(check::shows) + check.unlisted(all) }
    Column(Modifier.fillMaxSize()) {
        TopBar("Safety recalls", { nav.pop() })
        LazyColumn(contentPadding = PaddingValues(horizontal = Space.margin, vertical = Space.xs), verticalArrangement = Arrangement.spacedBy(Space.stackGap),
            modifier = Modifier.testTag("recalls.list")) {
            item {
                Text(if (check?.covered == true) "From NHTSA for the ${vehicle.descriptor}, narrowed to what's still open on your VIN. Log the fix when it's done."
                    else "From NHTSA for the ${vehicle.descriptor}. A recall may not apply to every one built; check your VIN, then log the fix.",
                    style = Type.footnote, color = colors.secondaryInk)
                if (!vehicle.vin.isNullOrBlank() && ready) {
                    check?.let { Text(vinCheckedLine(it), style = Type.footnote, color = colors.good, modifier = Modifier.testTag("recalls.vinChecked")) }
                    LinkButton(if (check == null) "Check what's open on your VIN" else "Check your VIN again", { nav.push(Route.VinCheck(vehicle.id)) },
                        color = colors.brass, modifier = Modifier.testTag("recalls.vinCheck"))
                }
            }
            when {
                !ready -> item { Text("Add the year, make and model to check recalls.", style = Type.callout, color = colors.ink) }
                error != null -> item {
                    Text(error!!, style = Type.callout, color = colors.ink, modifier = Modifier.testTag("recalls.error"))
                    SecondaryButton("Try again", { attempt += 1 })
                }
                recalls == null -> item { CircularProgressIndicator(Modifier.padding(Space.lg).size(28.dp), color = colors.ink) }
                listed!!.isEmpty() -> item { Text(if (check?.covered == true) "Nothing open on your VIN." else "No recalls on record for this model year.", style = Type.callout, color = colors.ink, modifier = Modifier.testTag("recalls.none")) }
                else -> items(listed!!, key = { it.campaign }) { recall ->
                    val fixed = RecallMatcher.fix(recall, entries)
                    Card(Modifier.testTag("recall.${recall.campaign}")) {
                        Eyebrow(if (fixed != null) "Fixed ${Format.shortDate(fixed.date)}" else if (recall.parkIt) "Don't drive it" else "Open",
                            color = if (fixed != null) colors.good else colors.overdue)
                        Text(recall.componentTitle, style = Type.headline, color = colors.ink)
                        Text("NHTSA ${recall.campaign}" + (recall.reported?.let { " · reported ${Format.longDate(it)}" } ?: ""), style = Type.footnote, color = colors.secondaryInk)
                        Spacer(Modifier.height(Space.xs))
                        Text(recall.summary, style = Type.subheadline, color = colors.ink)
                        if (recall.remedy.isNotEmpty()) {
                            Spacer(Modifier.height(Space.xs))
                            Text(recall.remedy, style = Type.footnote, color = colors.secondaryInk)
                        }
                        if (fixed == null) LinkButton("Log the fix", { nav.push(Route.LogService(vehicle.id, recall = recall.campaign)) }, color = colors.brass)
                        LinkButton("Check your VIN on nhtsa.gov", { context.openUrl(recall.nhtsaUrl) }, color = colors.secondaryInk)
                    }
                }
            }
        }
    }
}
