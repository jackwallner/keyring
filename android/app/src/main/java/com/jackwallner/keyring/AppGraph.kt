package com.jackwallner.keyring

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.keyring.data.GarageData
import com.jackwallner.keyring.data.GarageFile
import com.jackwallner.keyring.data.GarageStore
import com.jackwallner.keyring.data.KeyValueStore
import com.jackwallner.keyring.data.ReminderScheduler
import com.jackwallner.keyring.data.ReviewPrompter
import com.jackwallner.keyring.data.SharedPreferencesStore
import com.jackwallner.keyring.data.StoreService
import java.io.File

/** The log as one JSON file in app storage, written atomically. */
class DeviceGarageFile(private val file: File) : GarageFile {
    override fun read(): String? = if (file.exists()) file.readText() else null

    override fun write(text: String) {
        val temp = File(file.parentFile, file.name + ".tmp")
        temp.writeText(text)
        if (!temp.renameTo(file)) {
            file.writeText(text)
            temp.delete()
        }
    }
}

/** Every shared object, built once per process. */
class AppGraph(context: Context) {
    val app: Context = context.applicationContext
    val defaults: KeyValueStore = SharedPreferencesStore(app)
    val garage = GarageStore(DeviceGarageFile(File(app.filesDir, "garage.json")))
    val store = StoreService(app, defaults)
    val review = ReviewPrompter(defaults)
    val reminders = ReminderScheduler(app, defaults)

    /** Compose reads this; every store write bumps it. */
    var data by mutableStateOf(garage.data)
        private set

    var hasOnboarded: Boolean
        get() = defaults.getBoolean(ONBOARDED)
        set(value) = defaults.putBoolean(ONBOARDED, value)

    init {
        garage.onChange = { next: GarageData ->
            data = next
            reminders.refresh(garage)
        }
    }

    companion object {
        const val ONBOARDED = "hasCompletedOnboarding"
    }
}
