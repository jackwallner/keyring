package com.jackwallner.keyring.ui

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import com.google.android.play.core.review.ReviewManagerFactory
import com.jackwallner.keyring.AppGraph
import com.jackwallner.keyring.DebugLaunchOptions
import com.jackwallner.keyring.ui.nav.Navigator
import com.jackwallner.keyring.ui.nav.Route
import com.jackwallner.keyring.ui.screens.AddVehicleScreen
import com.jackwallner.keyring.ui.screens.CatalogScreen
import com.jackwallner.keyring.ui.screens.EditVehicleScreen
import com.jackwallner.keyring.ui.screens.GarageScreen
import com.jackwallner.keyring.ui.screens.HistoryScreen
import com.jackwallner.keyring.ui.screens.InsightsScreen
import com.jackwallner.keyring.ui.screens.LogServiceScreen
import com.jackwallner.keyring.ui.screens.OnboardingScreen
import com.jackwallner.keyring.ui.screens.PaywallScreen
import com.jackwallner.keyring.ui.screens.RecallsScreen
import com.jackwallner.keyring.ui.screens.SettingsScreen
import com.jackwallner.keyring.ui.screens.TaskScreen
import com.jackwallner.keyring.ui.screens.VehicleScreen
import com.jackwallner.keyring.ui.theme.Keyring

val LocalGraph = staticCompositionLocalOf<AppGraph> { error("No graph") }
val LocalNavigator = staticCompositionLocalOf<Navigator> { error("No navigator") }

@Composable
fun RootScreen(graph: AppGraph, openVehicle: String?, onOpened: () -> Unit) {
    val navigator = remember {
        Navigator().also { nav -> DebugLaunchOptions.startRoutes?.let { nav.reset(*it.toTypedArray()) } }
    }
    var onboarded by rememberSaveable { mutableStateOf(graph.hasOnboarded || graph.data.vehicles.isNotEmpty()) }
    LaunchedEffect(openVehicle) {
        val id = openVehicle ?: return@LaunchedEffect
        if (graph.garage.vehicle(id) != null) navigator.reset(Route.Garage, Route.Vehicle(id))
        onOpened()
    }
    androidx.compose.runtime.CompositionLocalProvider(LocalGraph provides graph, LocalNavigator provides navigator) {
        Box(Modifier.fillMaxSize().background(Keyring.colors.paper).safeDrawingPadding()) {
            if (!onboarded) {
                OnboardingScreen(onDone = { addFirst ->
                    graph.hasOnboarded = true
                    onboarded = true
                    if (addFirst) navigator.reset(Route.Garage, Route.AddVehicle)
                })
                return@Box
            }
            BackHandler(enabled = navigator.stack.size > 1) { navigator.pop() }
            val depth = navigator.stack.size
            var lastDepth by remember { mutableStateOf(depth) }
            val forward = depth >= lastDepth
            lastDepth = depth
            AnimatedContent(
                targetState = navigator.current,
                transitionSpec = {
                    val dir = if (forward) 1 else -1
                    (slideInHorizontally(tween(260)) { it * dir / 4 } + fadeIn(tween(200))) togetherWith
                        (slideOutHorizontally(tween(260)) { -it * dir / 4 } + fadeOut(tween(160)))
                },
                label = "route",
            ) { route ->
                Box(Modifier.fillMaxSize().background(Keyring.colors.paper)) { Screen(route) }
            }
        }
    }
}

@Composable
private fun Screen(route: Route) {
    when (route) {
        Route.Garage -> GarageScreen()
        Route.AddVehicle -> AddVehicleScreen()
        is Route.Vehicle -> VehicleScreen(route.id)
        is Route.LogService -> LogServiceScreen(route.vehicleId, route.entryId, route.taskId, route.fuel, route.recall)
        is Route.Task -> TaskScreen(route.vehicleId, route.taskId)
        is Route.Catalog -> CatalogScreen(route.vehicleId)
        is Route.Recalls -> RecallsScreen(route.vehicleId)
        is Route.Insights -> InsightsScreen(route.vehicleId)
        is Route.EditVehicle -> EditVehicleScreen(route.vehicleId)
        Route.History -> HistoryScreen()
        Route.Settings -> SettingsScreen()
        is Route.Paywall -> PaywallScreen(route.focus)
    }
}

/** Outside links open in the browser, never inside the app (Amazon's rule and the iOS behavior). */
fun Context.openUrl(url: String) {
    try {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
    }
}

fun Context.sendEmail(to: String, subject: String) {
    val uri = Uri.parse("mailto:$to?subject=" + Uri.encode(subject))
    try {
        startActivity(Intent(Intent.ACTION_SENDTO, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
    }
}

/** The positive moment: a logged service. Play's card, no question first. */
fun requestReviewIfDue(activity: Activity?, graph: AppGraph) {
    if (activity == null || !graph.review.shouldAsk()) return
    graph.review.markAsked()
    val manager = ReviewManagerFactory.create(activity)
    manager.requestReviewFlow().addOnCompleteListener { request ->
        if (request.isSuccessful) manager.launchReviewFlow(activity, request.result)
    }
}

tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is android.content.ContextWrapper -> baseContext.findActivity()
    else -> null
}
