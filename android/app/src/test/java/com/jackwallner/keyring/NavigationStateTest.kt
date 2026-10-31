package com.jackwallner.keyring

import androidx.compose.runtime.saveable.SaverScope
import com.jackwallner.keyring.model.ProFeature
import com.jackwallner.keyring.ui.nav.Navigator
import com.jackwallner.keyring.ui.nav.Route
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.ObjectInputStream
import java.io.ObjectOutputStream
import java.io.Serializable
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A rotation, a dark-mode switch or the system reclaiming the app starts the activity again. The screen the person
 * was on, and the form they were typing into, only come back if the back stack is written into the saved state.
 */
class NavigationStateTest {
    private val routes: List<Route> = listOf(
        Route.Garage, Route.AddVehicle, Route.Vehicle("v1"),
        Route.LogService("v1", entryId = "e1", taskId = "t1", fuel = true, recall = "24V123000"), Route.LogService("v1"),
        Route.Task("v1", "t1"), Route.Catalog("v1"), Route.Recalls("v1"), Route.Insights("v1"), Route.EditVehicle("v1"), Route.Value("v1"),
        Route.Gear("v1"), Route.Upgrades("v1"), Route.Clubs("v1"), Route.ServiceNearby("v1"), Route.TripCheck("v1"), Route.Documents("v1"),
        Route.Storage("v1"), Route.Retire("v1"), Route.VinCheck("v1"), Route.Import("v1", "Date,Work\n2025-01-01,Oil"), Route.Import(),
        Route.History, Route.Settings, Route.Paywall(ProFeature.insights), Route.Paywall(),
    )

    @Suppress("UNCHECKED_CAST")
    private fun <T> throughSavedState(value: T): T {
        val bytes = ByteArrayOutputStream().also { out -> ObjectOutputStream(out).use { it.writeObject(value) } }.toByteArray()
        return ObjectInputStream(ByteArrayInputStream(bytes)).use { it.readObject() } as T
    }

    @Test fun everyScreenCanBeWrittenIntoSavedState() {
        for (route in routes) {
            assertTrue("$route can't be saved", route is Serializable)
            assertEquals(route, throughSavedState(route))
        }
    }

    @Test fun theBackStackComesBackAfterTheActivityIsRecreated() {
        val navigator = Navigator()
        navigator.push(Route.Vehicle("v1"))
        navigator.push(Route.LogService("v1", taskId = "t1"))
        val saved = with(Navigator.Saver) { SaverScope { true }.save(navigator) }!!
        val back = Navigator.Saver.restore(throughSavedState(saved))!!
        assertEquals(navigator.stack.toList(), back.stack.toList())
        assertEquals(Route.LogService("v1", taskId = "t1"), back.current)
        assertTrue(back.pop())
        assertEquals(Route.Vehicle("v1"), back.current)
    }

    @Test fun anEmptyGarageStartsOnTheGarage() {
        val saved = with(Navigator.Saver) { SaverScope { true }.save(Navigator()) }!!
        assertEquals(listOf<Route>(Route.Garage), Navigator.Saver.restore(throughSavedState(saved))!!.stack.toList())
    }
}
