package com.jackwallner.keyring

import android.appwidget.AppWidgetManager
import android.content.Intent
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jackwallner.keyring.data.NewVehicle
import com.jackwallner.keyring.data.VINRecallCheck
import com.jackwallner.keyring.data.WidgetSnapshot
import com.jackwallner.keyring.model.EntryKind
import com.jackwallner.keyring.model.VehicleKind
import java.time.Instant
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The features this port added for iOS parity, on a real device. The orchestrator clears app data before each test. */
@RunWith(AndroidJUnit4::class)
class ParityFlowTest {
    @get:Rule val compose = createEmptyComposeRule()
    private var scenario: ActivityScenario<MainActivity>? = null

    private fun launch(vararg extras: Pair<String, Any>) {
        val intent = Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java).putExtra("uiTest", true)
        extras.forEach { (key, value) ->
            when (value) {
                is Boolean -> intent.putExtra(key, value)
                is String -> intent.putExtra(key, value)
            }
        }
        scenario = ActivityScenario.launch(intent)
        compose.waitForIdle()
    }

    private val graph: AppGraph get() = ApplicationProvider.getApplicationContext<KeyringApplication>().graph
    private val tacoma get() = graph.garage.activeVehicles.first { it.model == "Tacoma" }

    @After fun tearDown() {
        scenario?.close()
    }

    private fun scrollTo(tag: String) = compose.onNodeWithTag("vehicle.list").performScrollToNode(hasTestTag(tag))

    @Test fun exploreTilesOpenValueGearUpgradesClubsAndService() {
        launch("seedDemo" to true, "route" to "vehicle")
        scrollTo("explore.value")
        compose.onNodeWithTag("explore.value").performClick()
        compose.onNodeWithText("Kelley Blue Book").assertIsDisplayed()
        compose.onNodeWithTag("value.list").performScrollToNode(hasTestTag("value.add"))
        compose.onNodeWithTag("value.add").performClick()
        compose.onNodeWithTag("value.amount").performTextInput("31900")
        compose.onNodeWithTag("value.save").performClick()
        compose.waitForIdle()
        assertEquals(31_900.0, graph.garage.valuations(tacoma).first().amount, 0.0)
        compose.onNodeWithTag("nav.back").performClick()

        scrollTo("explore.gear")
        compose.onNodeWithTag("explore.gear").performClick()
        compose.onNodeWithTag("gear.list").assertIsDisplayed()
        compose.onNodeWithTag("nav.back").performClick()

        scrollTo("explore.upgrades")
        compose.onNodeWithTag("explore.upgrades").performClick()
        compose.onNodeWithText("Leveling kit").assertExists()
        compose.onNodeWithTag("nav.back").performClick()

        scrollTo("explore.clubs")
        compose.onNodeWithTag("explore.clubs").performClick()
        compose.onNodeWithText("Tacoma World").assertIsDisplayed()
        compose.onNodeWithTag("nav.back").performClick()

        scrollTo("explore.service")
        compose.onNodeWithTag("explore.service").performClick()
        compose.onNodeWithText("Toyota dealer service").assertIsDisplayed()
    }

    @Test fun storagePausesAndBringsItBack() {
        launch("seedDemo" to true, "route" to "vehicle")
        scrollTo("vehicle.store")
        compose.onNodeWithTag("vehicle.store").performClick()
        compose.onNodeWithTag("storage.save").performClick()
        compose.waitForIdle()
        assertNotNull(tacoma.storedSince)
        assertNotNull(tacoma.storedUntil)
        // Stored vehicles leave the widget.
        assertFalse(WidgetSnapshot.decode(graph.defaults.getString(WidgetSnapshot.KEY)).vehicles.any { it.id == tacoma.id })
        compose.onNodeWithTag("vehicle.stored").assertIsDisplayed()
        compose.onNodeWithTag("vehicle.unstore").performClick()
        compose.onNodeWithTag("storage.reading").performTextInput("48400")
        compose.onNodeWithTag("storage.list").performScrollToNode(hasTestTag("storage.save"))
        compose.onNodeWithTag("storage.save").performClick()
        compose.waitForIdle()
        assertEquals(null, tacoma.storedSince)
        assertEquals(48_400.0, tacoma.reading, 0.0)
    }

    @Test fun sellingKeepsThePriceAndHandsOverTheHistory() {
        launch("seedDemo" to true, "demoPro" to true, "route" to "retire")
        val id = tacoma.id
        compose.onNodeWithTag("retire.price").performTextInput("29500")
        compose.onNodeWithTag("retire.save").performClick()
        compose.onNodeWithText("Hand over its history").assertIsDisplayed()
        compose.onNodeWithTag("retire.record").assertIsDisplayed()
        val sold = graph.garage.vehicle(id)!!
        assertTrue(sold.isRetired)
        assertEquals(29_500.0, sold.soldPrice, 0.0)
        compose.onNodeWithTag("retire.done").performClick()
        compose.onNodeWithTag("garage.settings").performClick()
        compose.onNodeWithTag("settings.retired.The Tacoma", useUnmergedTree = true).assertExists()
    }

    @Test fun importAddsHistoryAndSkipsExpenses() {
        launch("seedDemo" to true, "route" to "import")
        compose.onNodeWithText("From your spreadsheet").assertIsDisplayed()
        compose.onNodeWithTag("import.summary").assertIsDisplayed()
        compose.onNodeWithText("3 services · 1 expense skipped").assertIsDisplayed()
        val before = graph.garage.entries(tacoma).size
        compose.onNodeWithTag("import.list").performScrollToNode(hasTestTag("import.save"))
        compose.onNodeWithTag("import.save").performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("import.outcome").assertExists()
        assertEquals(before + 3, graph.garage.entries(tacoma).size)
        assertTrue(graph.garage.entries(tacoma).any { it.title == "Brake pads" && it.shop == "Les Schwab" })
    }

    @Test fun secondMeterCountsGeneratorHours() {
        launch("skipOnboarding" to true)
        val rv = graph.garage.addVehicle(NewVehicle(kind = VehicleKind.rv, make = "Winnebago", model = "View", reading = 20_000.0, auxMeterName = "Generator"))
        scenario?.close()
        launch("route" to "vehicle")
        compose.onNodeWithTag("vehicle.auxMeter").performClick()
        compose.onNodeWithTag("auxMeter.field").performTextInput("140")
        compose.onNodeWithTag("auxMeter.save").performClick()
        compose.waitForIdle()
        val updated = graph.garage.vehicle(rv.id)!!
        assertEquals(140.0, updated.auxReading, 0.0)
        assertTrue(graph.garage.dues(updated).first { it.task.catalogKey == "generator" }.usesAuxMeter)
        compose.onNodeWithText("GENERATOR HOURS").assertIsDisplayed()
    }

    @Test fun tripCheckAndDocuments() {
        launch("seedDemo" to true, "route" to "trip")
        compose.onNodeWithTag("trip.distance").performTextInput("9000")
        compose.waitForIdle()
        compose.onNodeWithTag("trip.owed.oil", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("nav.back").performClick()
        scrollTo("vehicle.documents")
        compose.onNodeWithTag("vehicle.documents").performClick()
        compose.onNodeWithText("Title").assertIsDisplayed()
        compose.onNodeWithText("Window sticker").assertIsDisplayed()
        assertEquals(2, graph.garage.documents(tacoma).size)
    }

    @Test fun savedVinCheckNarrowsRecallsAndTheWidgetIsRegistered() {
        launch("seedDemo" to true)
        graph.vinChecks.save(VINRecallCheck(tacoma.vin!!, Instant.now(), true, emptyList(), emptyList()), tacoma)
        scenario?.close()
        launch("route" to "recalls")
        compose.onNodeWithTag("recalls.vinChecked").assertIsDisplayed()
        compose.onNodeWithTag("recalls.vinCheck").assertIsDisplayed()
        val providers = AppWidgetManager.getInstance(ApplicationProvider.getApplicationContext()).installedProviders
        assertTrue(providers.any { it.provider.className == "com.jackwallner.keyring.widget.UpcomingWidgetReceiver" })
        val snapshot = WidgetSnapshot.decode(graph.defaults.getString(WidgetSnapshot.KEY))
        assertTrue(snapshot.vehicles.isNotEmpty())
        assertTrue(graph.garage.entries(tacoma).any { it.kind == EntryKind.fuel })
    }
}
