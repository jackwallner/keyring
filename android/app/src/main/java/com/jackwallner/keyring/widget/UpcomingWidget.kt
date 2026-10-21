package com.jackwallner.keyring.widget

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.jackwallner.keyring.MainActivity
import com.jackwallner.keyring.data.ReminderScheduler
import com.jackwallner.keyring.data.SharedPreferencesStore
import com.jackwallner.keyring.data.WidgetSnapshot
import com.jackwallner.keyring.model.DueStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** What's next across the garage, from the snapshot the app writes after every change. Ported from `KeyringWidget.swift`. */
class UpcomingWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(SMALL, MEDIUM, LARGE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = WidgetSnapshot.decode(SharedPreferencesStore(context).getString(WidgetSnapshot.KEY))
        provideContent { Content(context, snapshot) }
    }

    @Composable
    private fun Content(context: Context, snapshot: WidgetSnapshot) {
        val size = LocalSize.current
        val items = snapshot.upcoming
        Column(GlanceModifier.fillMaxSize().background(PAPER).cornerRadius(20.dp).padding(14.dp)) {
            when {
                items.isEmpty() -> {
                    Text("Maintenance Log", style = TextStyle(color = ColorProvider(BRASS), fontSize = 12.sp, fontWeight = FontWeight.Bold))
                    Spacer(GlanceModifier.height(6.dp))
                    Text(if (snapshot.vehicles.isEmpty()) "Add a vehicle in the app" else "All caught up",
                        style = TextStyle(color = ColorProvider(INK), fontSize = 15.sp, fontWeight = FontWeight.Bold),
                        modifier = GlanceModifier.clickable(actionStartActivity(open(context, null))))
                }
                size.width < MEDIUM.width -> Small(context, items.first())
                else -> {
                    Text("Up next", style = TextStyle(color = ColorProvider(INK), fontSize = 14.sp, fontWeight = FontWeight.Bold))
                    Spacer(GlanceModifier.height(8.dp))
                    items.take(if (size.height >= LARGE.height) 6 else 3).forEach { (vehicle, item) ->
                        ListRow(context, vehicle, item)
                        Spacer(GlanceModifier.height(8.dp))
                    }
                }
            }
        }
    }

    @Composable
    private fun Small(context: Context, pair: Pair<WidgetSnapshot.VehicleSummary, WidgetSnapshot.Item>) {
        val (vehicle, item) = pair
        Column(GlanceModifier.fillMaxSize().clickable(actionStartActivity(open(context, vehicle.id)))) {
            Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(GlanceModifier.size(24.dp).background(Color(0xFF000000 or vehicle.tintHex)).cornerRadius(7.dp)) {}
                Spacer(GlanceModifier.defaultWeight())
                Box(GlanceModifier.size(8.dp).background(statusColor(item.status)).cornerRadius(4.dp)) {}
            }
            Spacer(GlanceModifier.defaultWeight())
            Text(vehicle.name, maxLines = 1, style = TextStyle(color = ColorProvider(SECONDARY), fontSize = 12.sp, fontWeight = FontWeight.Medium))
            Text(item.name, maxLines = 2, style = TextStyle(color = ColorProvider(INK), fontSize = 16.sp, fontWeight = FontWeight.Bold))
            Text(WidgetSnapshot.whenText(item), style = TextStyle(color = ColorProvider(statusColor(item.status)), fontSize = 12.sp, fontWeight = FontWeight.Bold))
        }
    }

    @Composable
    private fun ListRow(context: Context, vehicle: WidgetSnapshot.VehicleSummary, item: WidgetSnapshot.Item) {
        Row(GlanceModifier.fillMaxWidth().clickable(actionStartActivity(open(context, vehicle.id))), verticalAlignment = Alignment.CenterVertically) {
            Box(GlanceModifier.size(22.dp).background(Color(0xFF000000 or vehicle.tintHex)).cornerRadius(6.dp)) {}
            Spacer(GlanceModifier.width(8.dp))
            Column(GlanceModifier.defaultWeight()) {
                Text(item.name, maxLines = 1, style = TextStyle(color = ColorProvider(INK), fontSize = 13.sp, fontWeight = FontWeight.Bold))
                Text(vehicle.name, maxLines = 1, style = TextStyle(color = ColorProvider(SECONDARY), fontSize = 11.sp))
            }
            Text(WidgetSnapshot.whenText(item), maxLines = 1, style = TextStyle(color = ColorProvider(statusColor(item.status)), fontSize = 11.sp, fontWeight = FontWeight.Bold))
        }
    }

    private fun statusColor(status: DueStatus): Color = when (status) {
        DueStatus.OVERDUE -> OVERDUE
        DueStatus.DUE_SOON -> DUE_SOON
        else -> GOOD
    }

    private fun open(context: Context, vehicleId: String?): Intent =
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .apply { if (vehicleId != null) putExtra(ReminderScheduler.EXTRA_VEHICLE, vehicleId) }

    companion object {
        private val SMALL = DpSize(120.dp, 120.dp)
        private val MEDIUM = DpSize(250.dp, 120.dp)
        private val LARGE = DpSize(250.dp, 280.dp)
        private val PAPER = Color(0xFFF4F1EA)
        private val INK = Color(0xFF1C1B19)
        private val SECONDARY = Color(0xFF69655C)
        private val BRASS = Color(0xFFA9771F)
        private val OVERDUE = Color(0xFFB9381A)
        private val DUE_SOON = Color(0xFFA86A0C)
        private val GOOD = Color(0xFF2E6E50)

        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

        fun refresh(context: Context) {
            scope.launch { runCatching { UpcomingWidget().updateAll(context) } }
        }
    }
}

class UpcomingWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = UpcomingWidget()
}
