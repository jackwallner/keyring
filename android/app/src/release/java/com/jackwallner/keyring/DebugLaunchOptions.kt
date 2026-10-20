package com.jackwallner.keyring

import android.content.Intent
import com.jackwallner.keyring.ui.nav.Route

/** Release and QA builds: launch extras never change anything. */
object DebugLaunchOptions {
    @Suppress("UNUSED_PARAMETER")
    fun apply(graph: AppGraph, intent: Intent?) = Unit

    val startRoutes: List<Route>? = null
    val forceDark: Boolean? = null
}
