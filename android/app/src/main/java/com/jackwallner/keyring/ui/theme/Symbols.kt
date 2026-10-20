package com.jackwallner.keyring.ui.theme

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AcUnit
import androidx.compose.material.icons.outlined.Air
import androidx.compose.material.icons.outlined.AirportShuttle
import androidx.compose.material.icons.outlined.Agriculture
import androidx.compose.material.icons.outlined.BatteryChargingFull
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.CleaningServices
import androidx.compose.material.icons.outlined.ContentCut
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.DirectionsBike
import androidx.compose.material.icons.outlined.DirectionsBoat
import androidx.compose.material.icons.outlined.DirectionsCar
import androidx.compose.material.icons.outlined.ElectricScooter
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.FormatPaint
import androidx.compose.material.icons.outlined.GolfCourse
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Hexagon
import androidx.compose.material.icons.outlined.LocalGasStation
import androidx.compose.material.icons.outlined.LocalShipping
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.LocalFireDepartment
import androidx.compose.material.icons.outlined.Opacity
import androidx.compose.material.icons.outlined.Power
import androidx.compose.material.icons.outlined.RvHookup
import androidx.compose.material.icons.outlined.Sailing
import androidx.compose.material.icons.outlined.Science
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Snowmobile
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Thermostat
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.TwoWheeler
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material.icons.outlined.WaterDrop
import androidx.compose.material.icons.outlined.Waves
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.material.icons.outlined.Flight
import androidx.compose.material.icons.outlined.Cable
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Cyclone
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.SettingsInputAntenna
import androidx.compose.material.icons.outlined.CallSplit
import androidx.compose.material.icons.outlined.Height
import androidx.compose.material.icons.outlined.SwapHoriz
import androidx.compose.material.icons.outlined.ChangeHistory
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Sensors
import androidx.compose.material.icons.outlined.Navigation
import androidx.compose.material.icons.outlined.TireRepair
import androidx.compose.ui.graphics.vector.ImageVector
import com.jackwallner.keyring.model.EntryKind
import com.jackwallner.keyring.model.VehicleKind

/** SF Symbol names from the shared catalog, drawn with the closest Material icon. Unknown names get a wrench. */
object Symbols {
    private val map: Map<String, ImageVector> = mapOf(
        "gearshape.2" to Icons.Outlined.Settings, "gearshape" to Icons.Outlined.Settings,
        "drop.fill" to Icons.Outlined.WaterDrop, "drop" to Icons.Outlined.WaterDrop, "drop.halffull" to Icons.Outlined.Opacity,
        "drop.triangle" to Icons.Outlined.Opacity, "drop.circle" to Icons.Outlined.WaterDrop, "drop.degreesign" to Icons.Outlined.Thermostat,
        "circle.circle" to Icons.Outlined.TireRepair, "circle.dashed" to Icons.Outlined.Circle,
        "bolt.fill" to Icons.Outlined.Bolt, "bolt.circle" to Icons.Outlined.Bolt,
        "wrench.adjustable" to Icons.Outlined.Build, "wrench.and.screwdriver.fill" to Icons.Outlined.Build,
        "snowflake" to Icons.Outlined.AcUnit, "thermometer.snowflake" to Icons.Outlined.Thermostat,
        "exclamationmark.octagon" to Icons.Outlined.Warning, "aqi.medium" to Icons.Outlined.Air, "wind" to Icons.Outlined.Air,
        "minus.plus.batteryblock" to Icons.Outlined.BatteryChargingFull, "battery.75" to Icons.Outlined.BatteryChargingFull,
        "battery.50" to Icons.Outlined.BatteryChargingFull, "link" to Icons.Outlined.Link,
        "windshield.front.and.wiper" to Icons.Outlined.CleaningServices, "bubbles.and.sparkles" to Icons.Outlined.CleaningServices,
        "sun.max" to Icons.Outlined.WbSunny, "sparkles" to Icons.Outlined.AutoAwesome, "scissors" to Icons.Outlined.ContentCut,
        "powerplug" to Icons.Outlined.Power, "lifepreserver" to Icons.Outlined.Security,
        "gauge.with.dots.needle.33percent" to Icons.Outlined.Speed, "fuelpump" to Icons.Outlined.LocalGasStation,
        "fuelpump.fill" to Icons.Outlined.LocalGasStation, "fanblades" to Icons.Outlined.Cyclone, "fanblades.fill" to Icons.Outlined.Cyclone,
        "fan" to Icons.Outlined.Cyclone, "air.conditioner.horizontal" to Icons.Outlined.AcUnit,
        "doc.text" to Icons.Outlined.Description, "checkmark.seal" to Icons.Outlined.Verified, "checklist" to Icons.Outlined.Checklist,
        "arrow.triangle.2.circlepath" to Icons.Outlined.Sync, "arrow.left.and.right" to Icons.Outlined.SwapHoriz,
        "triangle" to Icons.Outlined.ChangeHistory, "testtube.2" to Icons.Outlined.Science, "steeringwheel" to Icons.Outlined.DirectionsCar,
        "slider.horizontal.3" to Icons.Outlined.Tune, "shield.lefthalf.filled" to Icons.Outlined.Security, "sailboat" to Icons.Outlined.Sailing,
        "rectangle.expand.vertical" to Icons.Outlined.Height, "paintbrush" to Icons.Outlined.FormatPaint, "moon.zzz" to Icons.Outlined.Bedtime,
        "location.north.line" to Icons.Outlined.Navigation, "lightbulb" to Icons.Outlined.Lightbulb, "house.fill" to Icons.Outlined.Home,
        "hexagon" to Icons.Outlined.Hexagon, "flame" to Icons.Outlined.LocalFireDepartment, "dot.radiowaves.right" to Icons.Outlined.Sensors,
        "clock.badge.checkmark" to Icons.Outlined.Schedule, "arrow.up.and.down.and.sparkles" to Icons.Outlined.SwapVert,
        "arrow.up.and.down" to Icons.Outlined.SwapVert, "arrow.triangle.branch" to Icons.Outlined.CallSplit,
        "antenna.radiowaves.left.and.right" to Icons.Outlined.SettingsInputAntenna, "cable" to Icons.Outlined.Cable,
        "hammer.fill" to Icons.Outlined.Build, "exclamationmark.shield.fill" to Icons.Outlined.Warning,
        "flag.checkered" to Icons.Outlined.Flag, "water.waves" to Icons.Outlined.Waves,
    )

    fun icon(name: String?): ImageVector = map[name] ?: Icons.Outlined.Build

    fun kind(kind: VehicleKind): ImageVector = when (kind) {
        VehicleKind.car, VehicleKind.suv -> Icons.Outlined.DirectionsCar
        VehicleKind.truck, VehicleKind.trailer -> Icons.Outlined.LocalShipping
        VehicleKind.van -> Icons.Outlined.AirportShuttle
        VehicleKind.motorcycle -> Icons.Outlined.TwoWheeler
        VehicleKind.scooter -> Icons.Outlined.ElectricScooter
        VehicleKind.rv, VehicleKind.camper -> Icons.Outlined.RvHookup
        VehicleKind.boat -> Icons.Outlined.DirectionsBoat
        VehicleKind.sailboat -> Icons.Outlined.Sailing
        VehicleKind.personalWatercraft -> Icons.Outlined.Waves
        VehicleKind.aircraft -> Icons.Outlined.Flight
        VehicleKind.atv -> Icons.Outlined.Explore
        VehicleKind.snowmobile -> Icons.Outlined.Snowmobile
        VehicleKind.tractor -> Icons.Outlined.Agriculture
        VehicleKind.ebike -> Icons.Outlined.DirectionsBike
        VehicleKind.golfCart -> Icons.Outlined.GolfCourse
        VehicleKind.other -> Icons.Outlined.Build
    }

    fun entry(kind: EntryKind): ImageVector = when (kind) {
        EntryKind.service -> Icons.Outlined.Build
        EntryKind.repair -> Icons.Outlined.Build
        EntryKind.recall -> Icons.Outlined.Warning
        EntryKind.fuel -> Icons.Outlined.LocalGasStation
        EntryKind.mod -> Icons.Outlined.AutoAwesome
        EntryKind.event -> Icons.Outlined.Flag
    }
}
