package com.jackwallner.keyring

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.lifecycle.lifecycleScope
import com.jackwallner.keyring.ui.RootScreen
import com.jackwallner.keyring.ui.theme.KeyringTheme
import kotlinx.coroutines.launch

@OptIn(ExperimentalComposeUiApi::class)
class MainActivity : ComponentActivity() {
    private val graph: AppGraph get() = (application as KeyringApplication).graph
    private var openVehicle by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            graph.review.recordLaunch()
            DebugLaunchOptions.apply(graph, intent)
        }
        enableEdgeToEdge()
        openVehicle = intent?.getStringExtra(EXTRA_VEHICLE)
        lifecycleScope.launch { graph.store.start() }
        graph.reminders.refresh(graph.garage)
        setContent {
            KeyringTheme(dark = DebugLaunchOptions.forceDark ?: androidx.compose.foundation.isSystemInDarkTheme()) {
                // Test tags double as resource ids so UI Automator and capture scripts can find controls.
                Box(Modifier.semantics { testTagsAsResourceId = true }) {
                    RootScreen(graph, openVehicle, onOpened = { openVehicle = null })
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(EXTRA_VEHICLE)?.let { openVehicle = it }
    }

    override fun onResume() {
        super.onResume()
        // Renewals, restores and late grants flip the app promptly, like iOS's foreground refresh.
        lifecycleScope.launch { graph.store.refreshCustomerInfo() }
    }

    companion object {
        const val EXTRA_VEHICLE = "vehicleId"
    }
}
