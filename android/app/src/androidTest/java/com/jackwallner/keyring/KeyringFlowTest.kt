package com.jackwallner.keyring

import android.content.Intent
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The first-run path and the paid boundary on a real device, like
 * `KeyringUITests`. The orchestrator clears app data before each test.
 */
@RunWith(AndroidJUnit4::class)
class KeyringFlowTest {
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

    private val graph: AppGraph get() = (ApplicationProvider.getApplicationContext<KeyringApplication>()).graph

    @After fun tearDown() {
        scenario?.close()
    }

    @Test fun firstRunAddsAVehicleAndLogsAService() {
        launch()
        compose.onNodeWithText("Every vehicle,\none logbook").assertIsDisplayed()
        compose.onNodeWithTag("onboarding.continue").performClick()
        compose.onNodeWithTag("onboarding.continue").performClick()
        compose.onNodeWithTag("onboarding.getStarted").performClick()
        compose.onNodeWithText("What is it?").assertIsDisplayed()
        compose.onNodeWithTag("add.kind.truck").performClick()
        compose.onNodeWithTag("add.year").performTextInput("2019")
        compose.onNodeWithTag("add.make").performTextInput("Toyota")
        compose.onNodeWithTag("add.model").performTextInput("Tacoma")
        compose.onNodeWithTag("add.reading").performTextInput("48210")
        compose.onNodeWithTag("add.save").performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Schedule").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("48,210 mi").assertIsDisplayed()
        compose.onNodeWithTag("vehicle.log").performClick()
        compose.onNodeWithTag("log.task.oil").performClick()
        compose.onNodeWithTag("log.cost").performTextInput("89.95")
        compose.onNodeWithTag("log.save").performClick()
        compose.waitForIdle()

        val vehicle = graph.garage.activeVehicles.single()
        assertEquals("Tacoma", vehicle.displayName)
        val entry = graph.garage.entries(vehicle).single()
        assertEquals("Oil and filter", entry.title)
        assertEquals(89.95, entry.cost, 0.001)
        compose.onNodeWithTag("vehicle.list").performScrollToNode(hasText("Oil and filter").and(hasText("Oil and filter")))
        assertTrue(compose.onAllNodesWithText("Oil and filter").fetchSemanticsNodes().isNotEmpty())
    }

    @Test fun aThirdVehicleNeedsProAndThePaywallKeepsItsTerms() {
        launch("skipOnboarding" to true)
        graph.garage.addVehicle(com.jackwallner.keyring.data.NewVehicle(kind = com.jackwallner.keyring.model.VehicleKind.car, model = "Civic"))
        graph.garage.addVehicle(com.jackwallner.keyring.data.NewVehicle(kind = com.jackwallner.keyring.model.VehicleKind.boat, model = "SPX 190"))
        compose.waitForIdle()
        compose.onNodeWithTag("garage.add").performClick()
        compose.onNodeWithTag("paywall").assertIsDisplayed()
        compose.onNodeWithText("Room for the\nwhole garage").assertIsDisplayed()
        // No store key in this build: the paywall says so and still shows restore, terms and privacy.
        compose.waitUntil(10_000) { compose.onAllNodesWithText("Couldn't load plans").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Restore").assertIsDisplayed()
        compose.onNodeWithText("Terms").assertIsDisplayed()
        compose.onNodeWithText("Privacy").assertIsDisplayed()
        compose.onNodeWithTag("paywall.close").performClick()
        assertEquals(2, graph.garage.activeVehicles.size)
    }

    @Test fun previewPlansRenderTheUSLadderAndUnlockPro() {
        launch("skipOnboarding" to true, "previewStore" to true, "route" to "paywall", "focus" to "serviceRecord")
        compose.onNodeWithText("A service record\nthat sells the car").assertIsDisplayed()
        compose.onNodeWithTag("paywall.plan.yearly").assertIsDisplayed()
        compose.onNodeWithText("$14.99 / year").assertIsDisplayed()
        compose.onNodeWithText("$1.99 / month").assertIsDisplayed()
        compose.onNodeWithText("$29.99").assertIsDisplayed()
        compose.onNodeWithTag("paywall.billedAmount").assertIsDisplayed()
        compose.onNode(hasTestTag("paywall.billedAmount").and(hasText("$14.99 per year"))).assertIsDisplayed()
        compose.onNodeWithTag("paywall.purchase").performClick()
        compose.waitForIdle()
        assertTrue(graph.store.isPro)
    }

    @Test fun demoGarageOpensEveryMainScreen() {
        launch("seedDemo" to true, "demoPro" to true)
        compose.onNodeWithText("Maintenance Log").assertIsDisplayed()
        compose.onNodeWithText("The Tacoma").assertIsDisplayed()
        compose.onNodeWithText("The Tacoma").performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Schedule").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("vehicle.list").performScrollToNode(hasTestTag("vehicle.insights"))
        compose.onNodeWithTag("vehicle.insights").performClick()
        compose.onNodeWithTag("insights.summary").assertIsDisplayed()
        compose.onNodeWithTag("nav.back").performClick()
        compose.onNodeWithTag("nav.back").performClick()
        compose.onNodeWithTag("garage.history").performClick()
        compose.onNodeWithTag("history.list").assertIsDisplayed()
        compose.onNodeWithTag("nav.back").performClick()
        compose.onNodeWithTag("garage.settings").performClick()
        compose.onNodeWithText("Pro is on").assertIsDisplayed()
    }

    @Test fun reviewerCodeIsRejectedWithoutTheReleaseDigest() {
        launch("skipOnboarding" to true, "route" to "settings")
        compose.onNodeWithTag("settings.reviewCode").performTextInput("not-the-code")
        compose.onNodeWithTag("settings.reviewUnlock").performClick()
        compose.onNodeWithText("That code didn't work.").assertIsDisplayed()
        assertTrue(!graph.store.isPro)
    }
}
