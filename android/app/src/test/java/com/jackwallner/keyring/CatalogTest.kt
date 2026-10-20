package com.jackwallner.keyring

import com.jackwallner.keyring.catalog.CatalogItem
import com.jackwallner.keyring.catalog.MaintenanceCatalog
import com.jackwallner.keyring.model.DueEngine
import com.jackwallner.keyring.model.DueInput
import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.MeterUnit
import com.jackwallner.keyring.model.Powertrain
import com.jackwallner.keyring.model.VehicleKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** `CatalogTests` and the catalog cases of `AuditRoundThreeTests` from KeyringTests.swift. */
class CatalogTest {
    @Test fun everyKindHasACoreSchedule() {
        for (kind in VehicleKind.entries) for (powertrain in kind.powertrainChoices) {
            val items = MaintenanceCatalog.items(kind, powertrain, region = "US")
            assertTrue("$kind $powertrain has no core jobs", items.any { it.isCore })
            assertEquals("$kind $powertrain repeats a key", items.size, items.map { it.key }.toSet().size)
            for (item in items.filter { it.key != "wash" }) {
                assertTrue("${item.key} has no interval", item.miles != null || item.hours != null || item.months != null || item.trigger != null)
            }
            // Core items come first, like iOS.
            val firstOptional = items.indexOfFirst { !it.isCore }
            if (firstOptional >= 0) assertTrue(items.drop(firstOptional).none { it.isCore })
        }
    }

    @Test fun washIsOnTheRoadScheduleWithoutAnInterval() {
        val wash = MaintenanceCatalog.items(VehicleKind.car, Powertrain.gasoline).first { it.key == "wash" }
        assertTrue(wash.isCore)
        assertNull(wash.months)
        assertTrue(MaintenanceCatalog.items(VehicleKind.motorcycle, Powertrain.electric).any { it.key == "wash" })
        assertFalse(MaintenanceCatalog.items(VehicleKind.aircraft, Powertrain.piston).any { it.key == "wash" })
        assertEquals(DueStatus.OK, DueEngine.evaluate(DueInput(0.0, 0, null, null, 0.0, 0.0, MeterUnit.miles)).status)
    }

    @Test fun hourMeterKindsGetHourIntervals() {
        assertTrue(MaintenanceCatalog.items(VehicleKind.boat, Powertrain.outboard).any { it.hours != null })
        assertTrue(MaintenanceCatalog.items(VehicleKind.aircraft, Powertrain.piston).any { it.key == "annual" })
    }

    @Test fun kilometersRoundToSensibleFigures() {
        assertEquals(12_000.0, MeterUnit.kilometers.fromCatalogMiles(7_500.0), 0.0)
        assertEquals(8_000.0, MeterUnit.kilometers.fromCatalogMiles(5_000.0), 0.0)
        assertEquals(100.0, MeterUnit.hours.fromCatalogMiles(100.0), 0.0)
    }

    @Test fun winterTiresAndClassicSchedule() {
        val canada = MaintenanceCatalog.items(VehicleKind.car, Powertrain.gasoline, year = 2020, region = "CA")
        assertEquals(true, canada.first { it.key == "winterTires" }.isCore)
        val us = MaintenanceCatalog.items(VehicleKind.car, Powertrain.gasoline, year = 2020, region = "US")
        assertEquals(false, us.first { it.key == "winterTires" }.isCore)
        val classic = MaintenanceCatalog.items(VehicleKind.car, Powertrain.gasoline, year = 1967, region = "US")
        assertEquals(3_000.0, classic.first { it.key == "oil" }.miles!!, 0.0)
        assertEquals(6, classic.first { it.key == "oil" }.months)
        assertNotNull(classic.firstOrNull { it.key == "chassisLube" })
        assertNull(us.firstOrNull { it.key == "chassisLube" })
        assertEquals(7_500.0, us.first { it.key == "oil" }.miles!!, 0.0)
    }

    @Test fun plugInHybridGetsElectricJobs() {
        val keys = MaintenanceCatalog.items(VehicleKind.suv, Powertrain.plugInHybrid).map { it.key }.toSet()
        assertTrue(keys.containsAll(listOf("oil", "brakes", "charger", "plugs")))
    }

    @Test fun metricDetailText() {
        assertEquals("Most call for 5,000 to 10,000 km.", CatalogItem.metric("Most call for 3,000 to 6,000 miles."))
        assertEquals("Around 161,000 km.", CatalogItem.metric("Around 100,000 miles."))
        assertEquals("Every 500 to 950 km and after rain.", CatalogItem.metric("Every 300 to 600 miles and after rain."))
        assertEquals("No units here.", CatalogItem.metric("No units here."))
    }

    @Test fun regionalInspectionNames() {
        fun inspection(region: String?) = MaintenanceCatalog.items(VehicleKind.car, Powertrain.gasoline, region = region).first { it.key == "inspection" }.name
        assertEquals("MOT test", inspection("GB"))
        assertEquals("NCT test", inspection("IE"))
        assertEquals("State inspection or emissions", inspection("US"))
        assertEquals("State inspection or emissions", inspection(null))
        assertEquals("Roadworthiness inspection", inspection("FR"))
    }

    @Test fun motorcycleDriveSwapsTheChainJob() {
        val belt = MaintenanceCatalog.items(VehicleKind.motorcycle, Powertrain.gasoline, drive = com.jackwallner.keyring.model.FinalDrive.belt).map { it.key }
        assertFalse("chain" in belt)
        assertTrue("driveBelt" in belt)
        val shaft = MaintenanceCatalog.items(VehicleKind.motorcycle, Powertrain.gasoline, drive = com.jackwallner.keyring.model.FinalDrive.shaft).map { it.key }
        assertTrue("finalDrive" in shaft)
        assertTrue("chain" in MaintenanceCatalog.items(VehicleKind.motorcycle, Powertrain.gasoline).map { it.key })
    }

    @Test fun traitsBringTheirJobs() {
        val fourByFour = MaintenanceCatalog.items(VehicleKind.truck, Powertrain.gasoline, traits = setOf(com.jackwallner.keyring.model.VehicleTrait.fourByFour))
        assertTrue(fourByFour.any { it.key == "transferCase" })
        assertEquals(com.jackwallner.keyring.model.UsageEvent.dust, fourByFour.first { it.key == "airFilter" }.trigger)
        val track = MaintenanceCatalog.items(VehicleKind.car, Powertrain.gasoline, traits = setOf(com.jackwallner.keyring.model.VehicleTrait.track))
        assertEquals(6, track.first { it.key == "brakeFluid" }.months)
        assertTrue(track.any { it.key == "trackPrep" })
        val collector = MaintenanceCatalog.items(VehicleKind.car, Powertrain.gasoline, traits = setOf(com.jackwallner.keyring.model.VehicleTrait.collector))
        assertEquals(12, collector.first { it.key == "oil" }.months)
        assertTrue(collector.any { it.key == "layup" })
        assertFalse(MaintenanceCatalog.items(VehicleKind.car, Powertrain.electric, traits = setOf(com.jackwallner.keyring.model.VehicleTrait.collector)).any { it.key == "layup" })
    }
}
