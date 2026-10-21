package com.jackwallner.keyring.ui.nav

import androidx.compose.runtime.Stable
import androidx.compose.runtime.mutableStateListOf
import com.jackwallner.keyring.model.ProFeature

/** One screen in the stack. Mirrors the iOS navigation destinations. */
sealed interface Route {
    data object Garage : Route
    data object AddVehicle : Route
    data class Vehicle(val id: String) : Route
    data class LogService(val vehicleId: String, val entryId: String? = null, val taskId: String? = null, val fuel: Boolean = false, val recall: String? = null) : Route
    data class Task(val vehicleId: String, val taskId: String) : Route
    data class Catalog(val vehicleId: String) : Route
    data class Recalls(val vehicleId: String) : Route
    data class Insights(val vehicleId: String) : Route
    data class EditVehicle(val vehicleId: String) : Route
    data class Value(val vehicleId: String) : Route
    data class Gear(val vehicleId: String) : Route
    data class Upgrades(val vehicleId: String) : Route
    data class Clubs(val vehicleId: String) : Route
    data class ServiceNearby(val vehicleId: String) : Route
    data class TripCheck(val vehicleId: String) : Route
    data class Documents(val vehicleId: String) : Route
    data class Storage(val vehicleId: String) : Route
    data class Retire(val vehicleId: String) : Route
    data class VinCheck(val vehicleId: String) : Route
    data class Import(val vehicleId: String? = null, val text: String? = null) : Route
    data object History : Route
    data object Settings : Route
    data class Paywall(val focus: ProFeature? = null) : Route
}

/** A single back stack; the system back gesture pops it. */
@Stable
class Navigator(start: Route = Route.Garage) {
    val stack = mutableStateListOf(start)
    val current: Route get() = stack.last()

    fun push(route: Route) {
        stack.add(route)
    }

    fun pop(): Boolean {
        if (stack.size <= 1) return false
        stack.removeAt(stack.lastIndex)
        return true
    }

    /** Replaces the top screen, so back skips a finished form. */
    fun replace(route: Route) {
        stack.removeAt(stack.lastIndex)
        stack.add(route)
    }

    fun reset(vararg routes: Route) {
        stack.clear()
        stack.addAll(if (routes.isEmpty()) listOf(Route.Garage) else routes.toList())
    }
}
