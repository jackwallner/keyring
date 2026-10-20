package com.jackwallner.keyring.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.keyring.data.ConversionCopy
import com.jackwallner.keyring.data.PackageKind
import com.jackwallner.keyring.data.Plan
import com.jackwallner.keyring.data.PurchaseException
import com.jackwallner.keyring.data.PurchaseOutcome
import com.jackwallner.keyring.data.StoreService
import com.jackwallner.keyring.model.AppLinks
import com.jackwallner.keyring.model.ProFeature
import com.jackwallner.keyring.ui.LocalGraph
import com.jackwallner.keyring.ui.LocalNavigator
import com.jackwallner.keyring.ui.findActivity
import com.jackwallner.keyring.ui.openUrl
import com.jackwallner.keyring.ui.theme.Eyebrow
import com.jackwallner.keyring.ui.theme.Keyring
import com.jackwallner.keyring.ui.theme.LinkButton
import com.jackwallner.keyring.ui.theme.PrimaryButton
import com.jackwallner.keyring.ui.theme.SecondaryButton
import com.jackwallner.keyring.ui.theme.Space
import com.jackwallner.keyring.ui.theme.Symbols
import com.jackwallner.keyring.ui.theme.Type
import kotlinx.coroutines.launch

/**
 * The Pro purchase surface, ported from `PaywallView.swift`. Price, period,
 * renewal terms, restore, Terms and Privacy render in every state, and every
 * price comes from Google Play.
 */
@Composable
fun PaywallScreen(focus: ProFeature?) {
    val graph = LocalGraph.current
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val colors = Keyring.colors
    val store = graph.store
    val scope = rememberCoroutineScope()
    var selectedId by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        store.trackPaywallImpression("keyring_paywall_${focus?.name ?: "settings"}")
        if (store.plans.isEmpty()) store.fetchPlans()
    }
    val plans = store.plans
    val selected = plans.firstOrNull { it.packageId == selectedId } ?: plans.firstOrNull { it.kind == PackageKind.YEARLY } ?: plans.firstOrNull()
    val monthly = plans.firstOrNull { it.kind == PackageKind.MONTHLY }

    Column(Modifier.fillMaxSize().testTag("paywall")) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            IconButton(onClick = { nav.pop() }, modifier = Modifier.testTag("paywall.close")) {
                Icon(Icons.Outlined.Close, contentDescription = "Close", tint = colors.secondaryInk)
            }
        }
        if (store.isPro) {
            ProIsOn(store)
            return@Column
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Space.margin)) {
            Eyebrow("Vehicle Maintenance Log Pro", color = colors.brass)
            Spacer(Modifier.height(Space.xs))
            Text(focus?.headline ?: "Keep every vehicle\nin one place", style = Type.title(32), color = colors.ink)
            Spacer(Modifier.height(Space.lg))
            ProFeature.entries.forEach { feature ->
                Row(Modifier.padding(vertical = Space.xs)) {
                    Icon(Symbols.icon(when (feature) {
                        ProFeature.unlimitedVehicles -> "steeringwheel"
                        ProFeature.serviceRecord -> "doc.text"
                        ProFeature.insights -> "gauge.with.dots.needle.33percent"
                    }), contentDescription = null, tint = colors.brass, modifier = Modifier.size(24.dp))
                    Spacer(Modifier.width(Space.sm))
                    Column {
                        Text(feature.title, style = Type.subheadlineBold, color = colors.ink)
                        Text(feature.detail, style = Type.footnote, color = colors.secondaryInk)
                    }
                }
            }
            Spacer(Modifier.height(Space.lg))
            when {
                plans.isNotEmpty() -> plans.forEach { plan ->
                    PlanRow(plan, plan == selected, plan.savingsPercent(monthly), store.isEligibleForIntroOffer(plan)) { selectedId = plan.packageId }
                    Spacer(Modifier.height(Space.xs))
                }
                store.isLoading -> Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(20.dp), color = colors.ink, strokeWidth = 2.dp)
                    Spacer(Modifier.width(Space.sm))
                    Text("Loading plans", style = Type.subheadline, color = colors.secondaryInk)
                }
                else -> Column(Modifier.testTag("paywall.unavailable")) {
                    Text("Couldn't load plans", style = Type.headline, color = colors.ink)
                    Text(store.errorMessage ?: "Check your connection and try again.", style = Type.footnote, color = colors.secondaryInk)
                    LinkButton("Try again", { scope.launch { store.fetchPlans() } })
                }
            }
        }
        Column(Modifier.padding(horizontal = Space.margin, vertical = Space.sm), horizontalAlignment = Alignment.CenterHorizontally) {
            if (selected != null) {
                val eligible = store.isEligibleForIntroOffer(selected)
                Text(ConversionCopy.billedAmount(selected.priceLabel), style = Type.figure(20), color = colors.ink, modifier = Modifier.testTag("paywall.billedAmount"))
                Text(if (selected.kind == PackageKind.LIFETIME) "One payment · Never renews" else ConversionCopy.billedNote(selected.introOfferLabel, eligible),
                    style = Type.footnote, color = colors.secondaryInk)
                Spacer(Modifier.height(Space.xs))
            }
            PrimaryButton(if (busy) "One moment" else ConversionCopy.CTA, {
                val plan = selected ?: return@PrimaryButton
                val activity = context.findActivity() ?: return@PrimaryButton
                busy = true
                message = null
                scope.launch {
                    try {
                        when (store.purchase(activity, plan)) {
                            PurchaseOutcome.PURCHASED -> nav.pop()
                            PurchaseOutcome.PENDING -> message = StoreService.PENDING_MESSAGE
                            PurchaseOutcome.CANCELLED -> message = ConversionCopy.purchaseCancelledMessage(store.isEligibleForIntroOffer(plan))
                        }
                    } catch (error: PurchaseException) {
                        message = error.message
                    } finally {
                        busy = false
                    }
                }
            }, enabled = selected != null && !busy, tag = "paywall.purchase")
            Spacer(Modifier.height(Space.xs))
            Text(selected?.let { ConversionCopy.disclosure(it.introOfferLabel, it.priceLabel, store.isEligibleForIntroOffer(it), it.kind == PackageKind.LIFETIME) }
                ?: "Subscriptions renew automatically until cancelled.", style = Type.footnote, color = colors.faintInk, textAlign = TextAlign.Center)
            message?.let { Text(it, style = Type.footnote, color = colors.secondaryInk, textAlign = TextAlign.Center, modifier = Modifier.testTag("paywall.message")) }
            Row(horizontalArrangement = Arrangement.Center) {
                LinkButton("Restore", {
                    scope.launch {
                        store.restore()
                        if (store.isPro) nav.pop() else message = store.errorMessage
                    }
                }, color = colors.secondaryInk)
                LinkButton("Terms", { context.openUrl(AppLinks.TERMS) }, color = colors.secondaryInk)
                LinkButton("Privacy", { context.openUrl(AppLinks.PRIVACY) }, color = colors.secondaryInk)
            }
        }
    }
}

@Composable
private fun PlanRow(plan: Plan, selected: Boolean, savings: Int?, eligible: Boolean, onClick: () -> Unit) {
    val colors = Keyring.colors
    val shape = RoundedCornerShape(Space.smallRadius)
    Row(
        Modifier.fillMaxWidth().heightIn(min = 64.dp).clip(shape).background(colors.surface)
            .border(if (selected) 2.dp else 1.dp, if (selected) colors.ink else colors.hairline, shape)
            .clickable(role = Role.RadioButton, onClick = onClick).testTag("paywall.plan.${plan.kind.name.lowercase()}")
            .padding(horizontal = Space.md, vertical = Space.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(plan.displayName, style = Type.subheadlineBold, color = colors.ink)
                val badge = when {
                    savings != null -> "SAVE $savings%"
                    plan.kind == PackageKind.LIFETIME -> "PAY ONCE"
                    else -> null
                }
                if (badge != null) {
                    Spacer(Modifier.width(Space.xs))
                    Box(Modifier.clip(RoundedCornerShape(6.dp)).background(colors.brassSoft).padding(horizontal = 6.dp, vertical = 2.dp)) {
                        Text(badge, style = Type.caption, color = colors.brass)
                    }
                }
            }
            val secondary = listOfNotNull(plan.perMonthLabel, plan.introOfferLabel?.takeIf { eligible }, if (plan.kind == PackageKind.LIFETIME) "One-time purchase" else null)
            if (secondary.isNotEmpty()) Text(secondary.joinToString(" · "), style = Type.footnote, color = colors.secondaryInk)
        }
        Text(plan.priceLabel, style = Type.figure(15), color = colors.ink)
    }
}

@Composable
private fun ProIsOn(store: StoreService) {
    val context = LocalContext.current
    val colors = Keyring.colors
    Column(Modifier.fillMaxSize().padding(Space.xl), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Icon(Icons.Outlined.Verified, contentDescription = null, tint = colors.brass, modifier = Modifier.size(48.dp))
        Spacer(Modifier.height(Space.md))
        Text("Pro is on", style = Type.title(30), color = colors.ink)
        Spacer(Modifier.height(Space.xs))
        Text("Unlimited vehicles, the Service Record and insights, on this Google Play account.", style = Type.callout, color = colors.secondaryInk, textAlign = TextAlign.Center)
        if (store.activeProductId != null) {
            Spacer(Modifier.height(Space.lg))
            SecondaryButton("Manage subscription", { context.openUrl(AppLinks.manageSubscription(store.activeProductId)) })
        }
    }
}
