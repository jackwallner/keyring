package com.jackwallner.keyring

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.keyring.data.AttachmentFiles
import com.jackwallner.keyring.data.GarageData
import com.jackwallner.keyring.data.GarageFile
import com.jackwallner.keyring.data.GarageStore
import com.jackwallner.keyring.data.KeyValueStore
import com.jackwallner.keyring.data.ReminderScheduler
import com.jackwallner.keyring.data.ReviewPrompter
import com.jackwallner.keyring.data.SharedPreferencesStore
import com.jackwallner.keyring.data.StoreService
import com.jackwallner.keyring.data.VINRecallChecks
import com.jackwallner.keyring.data.WidgetSnapshot
import com.jackwallner.keyring.widget.UpcomingWidget
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

/** Photos and documents as files in `files/attachments`, beside the log and excluded from backup like it. */
class DeviceAttachmentFiles(private val dir: File) : AttachmentFiles {
    override fun save(id: String, extension: String, bytes: ByteArray): String {
        dir.mkdirs()
        val name = "$id.$extension"
        File(dir, name).writeBytes(bytes)
        return name
    }

    override fun read(file: String): ByteArray? = File(dir, file).takeIf { it.isFile }?.readBytes()

    override fun delete(file: String) {
        File(dir, file).delete()
    }

    fun file(name: String): File = File(dir, name)
}

/** Every shared object, built once per process. */
class AppGraph(context: Context) {
    val app: Context = context.applicationContext
    val defaults: KeyValueStore = SharedPreferencesStore(app)
    val attachmentFiles = DeviceAttachmentFiles(File(app.filesDir, "attachments"))
    val garage = GarageStore(DeviceGarageFile(File(app.filesDir, "garage.json")), attachmentFiles)
    val vinChecks = VINRecallChecks(defaults)
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
            publishWidget()
        }
    }

    /** Writes the widget's snapshot and redraws it only when what it shows changed. */
    fun publishWidget() {
        val snapshot = WidgetSnapshot.build(garage).encode()
        if (defaults.getString(WidgetSnapshot.KEY) == snapshot) return
        defaults.putString(WidgetSnapshot.KEY, snapshot)
        UpcomingWidget.refresh(app)
    }

    companion object {
        const val ONBOARDED = "hasCompletedOnboarding"
    }
}
