package com.jackwallner.keyring

import android.content.Intent
import com.jackwallner.keyring.data.GarageData
import com.jackwallner.keyring.data.StoreService
import com.jackwallner.keyring.model.ProFeature
import com.jackwallner.keyring.ui.nav.Route

/**
 * Debug-only launch extras, the Android side of the iOS launch arguments
 * (`-SeedDemo`, `-DemoPro`, `-EmptyLog`, `-ScreenshotRoute`, `-PaywallSnapshot`).
 * None of this is compiled into a release or QA build.
 *
 *     adb shell am start -n com.jackwallner.keyring/.MainActivity \
 *         --ez seedDemo true --ez demoPro true --es route vehicle
 */
object DebugLaunchOptions {
    var startRoutes: List<Route>? = null
        private set
    var forceDark: Boolean? = null
        private set

    fun apply(graph: AppGraph, intent: Intent?) {
        val extras = intent?.extras ?: return
        if (extras.getBoolean("uiTest")) graph.review.isAutomationRun = true
        if (extras.getBoolean("emptyLog") || extras.getBoolean("resetAll")) {
            graph.garage.replaceAll(GarageData())
            graph.defaults.keys().forEach(graph.defaults::remove)
        }
        if (extras.getBoolean("seedDemo")) {
            DemoSeed.seed(graph.garage)
            graph.hasOnboarded = true
        }
        if (extras.getBoolean("skipOnboarding")) graph.hasOnboarded = true
        if (extras.getBoolean("demoPro")) graph.store.forceProForDebug()
        if (extras.getBoolean("previewStore")) graph.store.loadPreviewPlans(StoreService.previewPlans())
        if (extras.containsKey("dark")) forceDark = extras.getBoolean("dark")
        val first = graph.garage.activeVehicles.firstOrNull()?.id
        startRoutes = when (extras.getString("route")) {
            "vehicle" -> first?.let { listOf(Route.Garage, Route.Vehicle(it)) }
            "log" -> first?.let { listOf(Route.Garage, Route.Vehicle(it), Route.LogService(it)) }
            "fuel" -> first?.let { listOf(Route.Garage, Route.Vehicle(it), Route.LogService(it, fuel = true)) }
            "recalls" -> first?.let { listOf(Route.Garage, Route.Vehicle(it), Route.Recalls(it)) }
            "insights" -> first?.let { listOf(Route.Garage, Route.Vehicle(it), Route.Insights(it)) }
            "task" -> first?.let { id -> graph.garage.dues(graph.garage.vehicle(id)!!).firstOrNull()?.let { listOf(Route.Garage, Route.Vehicle(id), Route.Task(id, it.task.id)) } }
            "add" -> listOf(Route.Garage, Route.AddVehicle)
            "history" -> listOf(Route.Garage, Route.History)
            "settings" -> listOf(Route.Garage, Route.Settings)
            "paywall" -> listOf(Route.Garage, Route.Paywall(extras.getString("focus")?.let { f -> ProFeature.entries.firstOrNull { it.name == f } }))
            else -> null
        }
    }
}
