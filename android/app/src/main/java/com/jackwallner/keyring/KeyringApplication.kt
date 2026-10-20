package com.jackwallner.keyring

import android.app.Application

class KeyringApplication : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        graph = AppGraph(this)
        graph.reminders.ensureChannel()
    }
}
