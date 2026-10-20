package com.jackwallner.keyring.ui.screens

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import com.jackwallner.keyring.BuildConfig
import com.jackwallner.keyring.model.AppLinks
import com.jackwallner.keyring.ui.LocalGraph
import com.jackwallner.keyring.ui.LocalNavigator
import com.jackwallner.keyring.ui.nav.Route
import com.jackwallner.keyring.ui.openUrl
import com.jackwallner.keyring.ui.sendEmail
import com.jackwallner.keyring.ui.theme.Card
import com.jackwallner.keyring.ui.theme.Divider
import com.jackwallner.keyring.ui.theme.Eyebrow
import com.jackwallner.keyring.ui.theme.Field
import com.jackwallner.keyring.ui.theme.Keyring
import com.jackwallner.keyring.ui.theme.ListRow
import com.jackwallner.keyring.ui.theme.SecondaryButton
import com.jackwallner.keyring.ui.theme.Space
import com.jackwallner.keyring.ui.theme.Symbols
import com.jackwallner.keyring.ui.theme.TopBar
import com.jackwallner.keyring.ui.theme.Type
import kotlinx.coroutines.launch

/** Pro, reminders, export, retired vehicles and the links. Ported from `SettingsView.swift`. */
@Composable
fun SettingsScreen() {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val colors = Keyring.colors
    val scope = rememberCoroutineScope()
    @Suppress("UNUSED_VARIABLE") val data = graph.data
    var reminders by remember { mutableStateOf(graph.reminders.enabled) }
    var restoreMessage by remember { mutableStateOf<String?>(null) }
    var code by remember { mutableStateOf("") }
    var codeMessage by remember { mutableStateOf<String?>(null) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        graph.reminders.enabled = granted
        reminders = granted
        graph.reminders.refresh(graph.garage)
    }
    val retired = graph.garage.retiredVehicles

    Column(Modifier.fillMaxSize().imePadding()) {
        TopBar("Settings", { nav.pop() })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Space.margin), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
            Eyebrow("Pro")
            Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                ListRow(if (graph.store.isPro) "Pro is on" else "Vehicle Maintenance Log Pro",
                    if (graph.store.isPro) "Thank you for supporting the app" else "Every vehicle, the Service Record PDF and insights",
                    Symbols.icon("checkmark.seal"), iconTint = colors.brass, modifier = Modifier.testTag("settings.pro"),
                    onClick = { nav.push(Route.Paywall()) })
                Divider()
                ListRow("Restore purchases", restoreMessage, Symbols.icon("arrow.triangle.2.circlepath"), modifier = Modifier.testTag("settings.restore"), onClick = {
                    scope.launch {
                        graph.store.restore()
                        restoreMessage = if (graph.store.isPro) "Pro restored" else graph.store.errorMessage
                    }
                })
                if (graph.store.activeProductId != null) {
                    Divider()
                    ListRow("Manage subscription", "Google Play › Payments & subscriptions", Symbols.icon("slider.horizontal.3"),
                        onClick = { context.openUrl(AppLinks.manageSubscription(graph.store.activeProductId)) })
                }
            }
            Spacer(Modifier.height(Space.md))
            Eyebrow("Reminders")
            Card {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Reminders on this phone", style = Type.subheadlineBold, color = colors.ink)
                        Text("A week ahead, on the day, and a Saturday note for anything overdue.", style = Type.footnote, color = colors.secondaryInk)
                    }
                    Switch(reminders, { on ->
                        if (on && Build.VERSION.SDK_INT >= 33 && !graph.reminders.hasPermission) {
                            permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                        } else {
                            graph.reminders.enabled = on
                            reminders = on
                            graph.reminders.refresh(graph.garage)
                        }
                    }, modifier = Modifier.testTag("settings.reminders"), colors = SwitchDefaults.colors(checkedTrackColor = colors.ink, checkedThumbColor = colors.onAction))
                }
            }
            Spacer(Modifier.height(Space.md))
            Eyebrow("Your data")
            Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                ListRow("Export everything (CSV)", "Every entry on every vehicle, free", Symbols.icon("checklist"), modifier = Modifier.testTag("settings.csv"),
                    onClick = { shareFile(context, writeCsv(context, graph.garage, graph.garage.activeVehicles + retired), "text/csv") })
                retired.forEach { vehicle ->
                    Divider()
                    ListRow(vehicle.displayName, "Retired · tap to bring it back", Symbols.kind(vehicle.kind), onClick = { graph.garage.retire(vehicle, false) })
                }
            }
            Text("Your log stays on this phone. Family sharing and iPhone sync use iCloud and aren't on Android yet.",
                style = Type.footnote, color = colors.faintInk)
            Spacer(Modifier.height(Space.md))
            Eyebrow("About")
            Card(padding = PaddingValues(horizontal = Space.cardPadding)) {
                ListRow("Rate on Google Play", icon = Symbols.icon("sparkles"), onClick = { context.openUrl(AppLinks.PLAY_LISTING) })
                Divider()
                ListRow("Send feedback", AppLinks.SUPPORT_EMAIL, Symbols.icon("doc.text"), onClick = { context.sendEmail(AppLinks.SUPPORT_EMAIL, "Vehicle Maintenance Log feedback") })
                Divider()
                ListRow("Support", icon = Symbols.icon("lifepreserver"), onClick = { context.openUrl(AppLinks.SUPPORT) })
                Divider()
                ListRow("Privacy Policy", icon = Symbols.icon("shield.lefthalf.filled"), onClick = { context.openUrl(AppLinks.PRIVACY) })
                Divider()
                ListRow("Terms of Use", icon = Symbols.icon("doc.text"), onClick = { context.openUrl(AppLinks.TERMS) })
            }
            if (!graph.store.isPro) {
                Spacer(Modifier.height(Space.md))
                Eyebrow("App review access")
                Field(code, { code = it; codeMessage = null }, "Access code", tag = "settings.reviewCode", supporting = codeMessage)
                SecondaryButton("Unlock for review", {
                    codeMessage = if (graph.store.activateReviewAccess(code)) "Pro unlocked for review." else "That code didn't work."
                }, tag = "settings.reviewUnlock")
            }
            Text("Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", style = Type.footnote, color = colors.faintInk,
                modifier = Modifier.padding(vertical = Space.lg))
        }
    }
}
