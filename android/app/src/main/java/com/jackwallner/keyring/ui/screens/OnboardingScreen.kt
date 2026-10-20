package com.jackwallner.keyring.ui.screens

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.VehicleKind
import com.jackwallner.keyring.model.VehicleTint
import com.jackwallner.keyring.ui.theme.Card
import com.jackwallner.keyring.ui.theme.Keyring
import com.jackwallner.keyring.ui.theme.PrimaryButton
import com.jackwallner.keyring.ui.theme.Space
import com.jackwallner.keyring.ui.theme.StatusDot
import com.jackwallner.keyring.ui.theme.Symbols
import com.jackwallner.keyring.ui.theme.Type
import com.jackwallner.keyring.ui.theme.color
import com.jackwallner.keyring.ui.theme.foreground

/** Three short pages, ported from `OnboardingView.swift`. The family page waits for Android sharing. */
@Composable
fun OnboardingScreen(onDone: (addFirst: Boolean) -> Unit) {
    var page by rememberSaveable { mutableIntStateOf(0) }
    val colors = Keyring.colors
    Column(Modifier.fillMaxSize().padding(horizontal = Space.margin, vertical = Space.lg)) {
        AnimatedContent(targetState = page, label = "onboarding", modifier = Modifier.weight(1f)) { index ->
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) {
                when (index) {
                    0 -> {
                        TagStack()
                        Spacer(Modifier.height(Space.xl))
                        Text("Every vehicle,\none logbook", style = Type.title(34), color = colors.ink)
                        Spacer(Modifier.height(Space.sm))
                        Text("Cars, trucks, boats, bikes, RVs, planes and the mower. What's due, what was done, and what it cost.",
                            style = Type.body, color = colors.secondaryInk)
                    }
                    1 -> {
                        Card {
                            SampleRow(Symbols.icon("drop.fill"), "Oil and filter", "Due in 3 weeks, by your pace", DueStatus.DUE_SOON)
                            SampleRow(Symbols.icon("arrow.triangle.2.circlepath"), "Tire rotation", "Due in 3 weeks, by your pace", DueStatus.DUE_SOON)
                            SampleRow(Symbols.icon("gearshape.2"), "Impeller", "Due at 250 hrs", DueStatus.OK)
                            SampleRow(Symbols.kind(VehicleKind.aircraft), "Annual inspection", "Due in 5 months", DueStatus.OK)
                        }
                        Spacer(Modifier.height(Space.xl))
                        Text("It knows\nwhat's due", style = Type.title(34), color = colors.ink)
                        Spacer(Modifier.height(Space.sm))
                        Text("Pick the kind of vehicle and its schedule is built for you: miles for the truck, engine hours for the boat. It learns how much you drive and reminds you a week ahead.",
                            style = Type.body, color = colors.secondaryInk)
                    }
                    else -> {
                        Text("Free to start", style = Type.title(34), color = colors.ink)
                        Spacer(Modifier.height(Space.md))
                        listOf(
                            "Your first two vehicles are free, forever",
                            "Unlimited logging, reminders, recalls and CSV export",
                            "Pro adds every vehicle you own",
                            "Service Record PDF for buyers and shops",
                            "Spending by vehicle and cost per mile",
                        ).forEach { Benefit(it) }
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(vertical = Space.md), horizontalArrangement = Arrangement.Center) {
            repeat(3) { i ->
                Box(Modifier.padding(4.dp).size(if (i == page) 8.dp else 6.dp).clip(CircleShape)
                    .background(if (i == page) colors.ink else colors.hairline))
            }
        }
        if (page < 2) PrimaryButton("Continue", { page += 1 }, tag = "onboarding.continue")
        else PrimaryButton("Add your first vehicle", { onDone(true) }, tag = "onboarding.getStarted")
    }
}

@Composable
private fun TagStack() {
    val tags = listOf(Triple(VehicleTint.marine, VehicleKind.boat, "Lake boat"), Triple(VehicleTint.racingGreen, VehicleKind.truck, "Tacoma"),
        Triple(VehicleTint.oxblood, VehicleKind.motorcycle, "Rebel"))
    Column(verticalArrangement = Arrangement.spacedBy((-28).dp)) {
        tags.forEachIndexed { index, (tint, kind, name) ->
            Row(
                Modifier.padding(start = (index * 18).dp).width(260.dp).height(84.dp).clip(RoundedCornerShape(Space.radius))
                    .background(tint.color()).padding(Space.md),
                verticalAlignment = Alignment.Top,
            ) {
                Text(name, style = Type.title(20), color = tint.foreground(), modifier = Modifier.weight(1f))
                Icon(Symbols.kind(kind), contentDescription = null, tint = tint.foreground())
            }
        }
    }
}

@Composable
private fun SampleRow(icon: ImageVector, title: String, line: String, status: DueStatus) {
    val colors = Keyring.colors
    Row(Modifier.fillMaxWidth().padding(vertical = Space.xs), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = colors.secondaryInk, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(Space.sm))
        Column(Modifier.weight(1f)) {
            Text(title, style = Type.subheadlineBold, color = colors.ink)
            Text(line, style = Type.footnote, color = colors.secondaryInk)
        }
        StatusDot(status)
    }
}

@Composable
private fun Benefit(text: String) {
    val colors = Keyring.colors
    Row(Modifier.padding(vertical = Space.xs), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = colors.good, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(Space.sm))
        Text(text, style = Type.callout, color = colors.ink)
    }
}
