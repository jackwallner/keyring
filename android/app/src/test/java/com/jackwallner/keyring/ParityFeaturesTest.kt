package com.jackwallner.keyring

import com.jackwallner.keyring.data.CSVExport
import com.jackwallner.keyring.data.DueCopy
import com.jackwallner.keyring.data.GarageCodec
import com.jackwallner.keyring.data.GarageStore
import com.jackwallner.keyring.data.MemoryAttachmentFiles
import com.jackwallner.keyring.data.MemoryGarageFile
import com.jackwallner.keyring.data.NewVehicle
import com.jackwallner.keyring.data.ReminderScheduler
import com.jackwallner.keyring.data.ServiceDraft
import com.jackwallner.keyring.data.ValuationKind
import com.jackwallner.keyring.data.WidgetSnapshot
import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.MeterUnit
import com.jackwallner.keyring.model.Powertrain
import com.jackwallner.keyring.model.Storage
import com.jackwallner.keyring.model.TripCheck
import com.jackwallner.keyring.model.VehicleKind
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Second meters, storage, selling, documents, values, trip check and the widget, ported from the iOS tests. */
class ParityFeaturesTest {
    private val files = MemoryAttachmentFiles()
    private val file = MemoryGarageFile()
    private fun store() = GarageStore(file, files)
    private val day = 86_400L

    // MARK: - Second meter

    @Test fun generatorCountsOnItsOwnMeter() {
        val store = store()
        val rv = store.addVehicle(NewVehicle(kind = VehicleKind.rv, reading = 20_000.0, auxMeterName = "Generator"))
        val generator = store.enabledTasks(rv).first { it.catalogKey == "generator" }
        assertTrue(generator.usesAuxMeter)
        assertEquals(150.0, generator.intervalDistance, 0.0)
        store.log(ServiceDraft(taskIds = listOf(generator.id), auxReading = 100.0), store.vehicle(rv.id)!!)
        store.updateAuxReading(store.vehicle(rv.id)!!, 260.0)
        val updated = store.vehicle(rv.id)!!
        val due = store.dues(updated).first { it.task.catalogKey == "generator" }
        assertEquals(MeterUnit.hours, due.meter)
        assertEquals(DueStatus.OVERDUE, due.result.status)
        assertEquals("Overdue by 10 hrs", DueCopy.dueLine(due))
        assertEquals(20_000.0, updated.reading, 0.0)
        assertEquals("Generator hours", updated.auxMeterLabel)
        store.setAuxMeter(updated, null)
        assertFalse(store.tasks(store.vehicle(rv.id)!!).first { it.catalogKey == "generator" }.usesAuxMeter)
    }

    @Test fun utvCountsHoursAndMilesWhicheverFirst() {
        val store = store()
        val rzr = store.addVehicle(NewVehicle(kind = VehicleKind.atv, powertrain = Powertrain.gasoline, meter = MeterUnit.hours, year = 2022,
            make = "Polaris", model = "RZR", reading = 120.0, auxMeterName = "Odometer", auxMeter = MeterUnit.miles,
            lastDone = mapOf("oil" to Instant.now().minusSeconds(5 * day))))
        val oil = store.tasks(rzr).first { it.catalogKey == "oil" }
        assertEquals(100.0, oil.intervalDistance, 0.0)
        assertEquals(1_000.0, oil.auxInterval, 0.0)
        // Logged at 120 hrs and 2,000 mi; then 1,100 trail miles but few hours.
        store.log(ServiceDraft(taskIds = listOf(oil.id), reading = 120.0, auxReading = 2_000.0, date = Instant.now().minusSeconds(day)), rzr)
        assertTrue(store.dues(store.vehicle(rzr.id)!!).first { it.task.catalogKey == "oil" }.result.status != DueStatus.OVERDUE)
        store.updateAuxReading(store.vehicle(rzr.id)!!, 3_100.0)
        assertEquals(DueStatus.OVERDUE, store.dues(store.vehicle(rzr.id)!!).first { it.task.catalogKey == "oil" }.result.status)
    }

    @Test fun anyVehicleCanAddTrackHours() {
        val store = store()
        val car = store.addVehicle(NewVehicle(kind = VehicleKind.car, make = "Mazda", model = "MX-5", reading = 40_000.0))
        store.setAuxMeter(car, "Track", MeterUnit.hours)
        val updated = store.vehicle(car.id)!!
        assertTrue(updated.hasAuxMeter)
        assertEquals("Track hours", updated.auxMeterLabel)
    }

    // MARK: - Selling and storage

    @Test fun sellingKeepsTheDateAndPriceUntilRestored() {
        val store = store()
        val car = store.addVehicle(NewVehicle())
        store.markSold(car, Instant.now(), 12_500.0)
        val sold = store.vehicle(car.id)!!
        assertTrue(sold.isRetired)
        assertEquals(12_500.0, sold.soldPrice, 0.0)
        assertEquals(0, store.activeVehicles.size)
        store.retire(sold, false)
        val restored = store.vehicle(car.id)!!
        assertNull(restored.soldDate)
        assertEquals(0.0, restored.soldPrice, 0.0)
    }

    @Test fun storageFreezesThePaceAndPausesReminders() {
        val store = store()
        val car = store.addVehicle(NewVehicle(kind = VehicleKind.car, powertrain = Powertrain.gasoline, meter = MeterUnit.miles, year = 2018,
            make = "Mazda", model = "MX-5", reading = 30_000.0, yearlyUse = 12_000.0, lastDone = mapOf("oil" to Instant.now().minusSeconds(30 * day))))
        assertEquals(12_000.0 / 365, store.typicalDailyUse(car), 0.01)
        assertTrue(store.dues(car).first { it.task.catalogKey == "oil" }.result.dateIsEstimated)
        val back = ZonedDateTime.now().plusMonths(5).toInstant()
        store.store(car, back)
        val stored = store.vehicle(car.id)!!
        assertNotNull(stored.storedSince)
        // Only the calendar runs while it's stored.
        assertFalse(store.dues(stored).first { it.task.catalogKey == "oil" }.result.dateIsEstimated)
        val plan = ReminderScheduler.plan(emptyList(), Instant.now(), 9, ZoneId.systemDefault(), listOf(ReminderScheduler.Return(stored.displayName, stored.id, back)))
        assertEquals(1, plan.size)
        assertEquals("storage-${stored.id}", plan[0].id)
        store.returnFromStorage(stored, 30_400.0)
        val back2 = store.vehicle(car.id)!!
        assertNull(back2.storedSince)
        assertNull(back2.storedUntil)
        assertEquals(30_400.0, back2.reading, 0.0)
    }

    @Test fun storageReturnsMidAprilAfterAFallLayUp() {
        assertEquals(LocalDate.of(2027, 4, 15), Storage.defaultReturn(LocalDate.of(2026, 10, 20)))
        assertEquals(LocalDate.of(2026, 4, 15), Storage.defaultReturn(LocalDate.of(2026, 1, 5)))
        assertEquals(LocalDate.of(2026, 9, 1), Storage.defaultReturn(LocalDate.of(2026, 6, 1)))
    }

    // MARK: - Documents, photos and values

    @Test fun documentsAndPhotosLiveInFilesAndLeaveWithTheirOwner() {
        val store = store()
        val car = store.addVehicle(NewVehicle(make = "Honda", model = "Civic", reading = 10_000.0))
        val pdf = "%PDF-1.4 title".toByteArray()
        val doc = store.addDocument("Title", pdf, car)
        assertTrue(doc.isPDF)
        assertEquals(1, store.documents(car).size)
        store.rename(doc, "Title (front)")
        assertEquals("Title (front)", store.documents(car)[0].name)
        val entry = store.log(ServiceDraft(title = "Detail", photos = listOf(byteArrayOf(1, 2, 3)), files = listOf("Invoice.pdf" to pdf)), car)
        val attached = store.attachments(entry)
        assertEquals(listOf("photo", "pdf"), attached.map { it.kind })
        assertEquals(3, files.files.size)
        // Visit attachments aren't vehicle documents.
        assertEquals(1, store.documents(car).size)
        store.delete(entry)
        assertEquals(1, files.files.size)
        store.delete(store.vehicle(car.id)!!)
        assertTrue(files.files.isEmpty())
        assertTrue(store.data.attachments.isEmpty())
    }

    @Test fun valuationsKeepTheirKindAndSurviveAReload() {
        val store = store()
        val car = store.addVehicle(NewVehicle(make = "Porsche", model = "911", year = 1987))
        store.addValuation(62_000.0, "Hagerty", ValuationKind.appraisal, car, Instant.now().minusSeconds(30 * day))
        store.addValuation(65_000.0, " ", ValuationKind.estimate, car)
        val reloaded = GarageStore(MemoryGarageFile(file.text), files)
        val values = reloaded.valuations(car)
        assertEquals(listOf(65_000.0, 62_000.0), values.map { it.amount })
        assertEquals(ValuationKind.appraisal, values[1].kind)
        assertNull(values[0].source)
        reloaded.delete(values[0])
        assertEquals(1, reloaded.valuations(car).size)
    }

    @Test fun newFieldsRoundTripThroughJson() {
        val store = store()
        val rv = store.addVehicle(NewVehicle(kind = VehicleKind.rv, reading = 20_000.0, auxMeterName = "Generator"))
        store.updateAuxReading(rv, 40.0)
        store.store(store.vehicle(rv.id)!!, Instant.ofEpochMilli(1_900_000_000_000))
        val decoded = GarageCodec.decode(file.text)
        val vehicle = decoded.vehicles.single()
        assertEquals("Generator", vehicle.auxMeterName)
        assertEquals(40.0, vehicle.auxReading, 0.0)
        assertEquals(Instant.ofEpochMilli(1_900_000_000_000), vehicle.storedUntil)
        assertTrue(decoded.readings.any { it.isAux && it.value == 40.0 })
        assertTrue(decoded.tasks.any { it.usesAuxMeter })
    }

    // MARK: - Trip check

    @Test fun tripCheckFindsWhatComesDueOnTheWay() {
        val store = store()
        val truck = store.addVehicle(NewVehicle(kind = VehicleKind.truck, powertrain = Powertrain.gasoline, meter = MeterUnit.miles, year = 2020,
            make = "Toyota", model = "Tacoma", reading = 40_000.0,
            lastDone = mapOf("oil" to Instant.now().minusSeconds(10 * day), "rotate" to Instant.now().minusSeconds(10 * day))))
        val dues = store.dues(truck)
        assertFalse(TripCheck.owed(dues, 100.0, 3.0, truck.reading).any { it.task.catalogKey == "oil" })
        assertTrue(TripCheck.owed(dues, 8_000.0, 14.0, truck.reading).any { it.task.catalogKey == "oil" })
    }

    // MARK: - Widget

    @Test fun widgetShowsTheMostUrgentJobsAndSkipsStoredVehicles() {
        val store = store()
        val truck = store.addVehicle(NewVehicle(kind = VehicleKind.truck, make = "Toyota", model = "Tacoma", reading = 40_000.0,
            lastDone = mapOf("oil" to Instant.now().minusSeconds(400 * day))))
        val boat = store.addVehicle(NewVehicle(kind = VehicleKind.boat, make = "Boston Whaler", model = "Montauk",
            lastDone = mapOf("impeller" to Instant.now().minusSeconds(10 * day))))
        val snapshot = WidgetSnapshot.build(store)
        assertEquals(2, snapshot.vehicles.size)
        assertTrue(snapshot.vehicles.all { it.items.size <= 3 })
        assertEquals(DueStatus.OVERDUE, snapshot.upcoming.first().second.status)
        assertEquals("Overdue", WidgetSnapshot.whenText(snapshot.upcoming.first().second))
        assertEquals(snapshot.encode(), WidgetSnapshot.decode(snapshot.encode()).encode())
        store.store(store.vehicle(boat.id)!!, null)
        assertEquals(listOf(truck.id), WidgetSnapshot.build(store).vehicles.map { it.id })
    }

    @Test fun widgetDatesReadLikeIOS() {
        val zone = ZoneId.of("America/Los_Angeles")
        val now = ZonedDateTime.of(2026, 10, 20, 9, 0, 0, 0, zone).toInstant()
        fun item(days: Long, estimated: Boolean = false) =
            WidgetSnapshot.Item("Oil", DueStatus.OK, now.plusSeconds(days * day), estimated, null)
        assertEquals("Today", WidgetSnapshot.whenText(item(0), now, zone))
        assertEquals("Tomorrow", WidgetSnapshot.whenText(item(1), now, zone))
        assertEquals("~9 days", WidgetSnapshot.whenText(item(9, true), now, zone))
        assertEquals("3 wks", WidgetSnapshot.whenText(item(21), now, zone))
        assertEquals("Up to date", WidgetSnapshot.whenText(WidgetSnapshot.Item("Oil", DueStatus.OK, null, false, null), now, zone))
        assertEquals("At 54,000 mi", WidgetSnapshot.whenText(WidgetSnapshot.Item("Oil", DueStatus.OK, null, false, "At 54,000 mi"), now, zone))
    }

    @Test fun csvCarriesTheSecondMeter() {
        val store = store()
        val rv = store.addVehicle(NewVehicle(kind = VehicleKind.rv, reading = 20_000.0, auxMeterName = "Generator"))
        store.log(ServiceDraft(title = "Generator service", auxReading = 210.0), rv)
        val csv = CSVExport.csv(store, listOf(store.vehicle(rv.id)!!))
        assertTrue(csv.lines()[1].endsWith(",210"))
    }
}
