package com.jackwallner.keyring

import com.jackwallner.keyring.data.ConversionCopy
import com.jackwallner.keyring.data.DueCopy
import com.jackwallner.keyring.data.FuelUnit
import com.jackwallner.keyring.data.InMemoryStore
import com.jackwallner.keyring.data.MaintenanceTask
import com.jackwallner.keyring.data.NHTSAClient
import com.jackwallner.keyring.data.PackageKind
import com.jackwallner.keyring.data.PeriodUnit
import com.jackwallner.keyring.data.Plan
import com.jackwallner.keyring.data.PlanPeriod
import com.jackwallner.keyring.data.Recall
import com.jackwallner.keyring.data.RecallMatcher
import com.jackwallner.keyring.data.ReminderScheduler
import com.jackwallner.keyring.data.ReviewAccess
import com.jackwallner.keyring.data.ReviewPrompter
import com.jackwallner.keyring.data.ServiceEntry
import com.jackwallner.keyring.data.StoreService
import com.jackwallner.keyring.data.TaskDue
import com.jackwallner.keyring.catalog.AmazonLinks
import com.jackwallner.keyring.model.DueResult
import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.EntryKind
import com.jackwallner.keyring.model.Format
import com.jackwallner.keyring.model.MeterUnit
import com.jackwallner.keyring.model.Powertrain
import com.jackwallner.keyring.model.VehicleKind
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneOffset
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ServicesTest {
    private val now = Instant.ofEpochSecond(1_790_000_000)

    private fun due(status: DueStatus, days: Double, name: String, months: Int = 12) = TaskDue(
        task = MaintenanceTask(id = name, vehicleId = "v", createdAt = now, name = name, intervalMonths = months),
        result = DueResult(status, now.plusSeconds((days * 86_400).toLong()), null, 0.5, false),
        lastDate = null, lastReading = null, meter = MeterUnit.miles, currentReading = 0.0,
    )

    @Test fun weekAheadDayOfAndOneOverdueRoundup() {
        val plan = ReminderScheduler.plan(listOf(
            ReminderScheduler.PlanInput("Tacoma", "1", due(DueStatus.OK, 30.0, "Oil and filter")),
            ReminderScheduler.PlanInput("Boat", "2", due(DueStatus.OVERDUE, -3.0, "Impeller")),
            ReminderScheduler.PlanInput("RAV4", "3", due(DueStatus.OVERDUE, -10.0, "Tire rotation")),
        ), now, 9, ZoneOffset.UTC)
        assertEquals(1, plan.count { it.id.startsWith("week-") })
        assertEquals(1, plan.count { it.id.startsWith("day-") })
        assertEquals(1, plan.count { it.id == "weekend-overdue" })
        assertEquals("2 jobs are overdue", plan.first { it.id == "weekend-overdue" }.title)
        assertEquals(ReminderScheduler.OVERDUE_WEEKS, plan.count { it.id.startsWith("weekend-overdue") })
        assertEquals("Boat impeller, RAV4 tire rotation.", plan.first { it.id == "weekend-overdue" }.body)
        assertEquals(java.time.DayOfWeek.SATURDAY, plan.first { it.id == "weekend-overdue" }.fireAt.atZone(ZoneOffset.UTC).dayOfWeek)
    }

    @Test fun intervalWording() {
        Locale.setDefault(Locale.US)
        assertEquals("Every 7,500 mi or 1 year", Format.interval(7_500.0, 12, MeterUnit.miles))
        assertEquals("Every year", Format.interval(0.0, 12, MeterUnit.miles))
        assertEquals("Every 6 months", Format.interval(0.0, 6, MeterUnit.miles))
        assertEquals("As needed", Format.interval(0.0, 0, MeterUnit.miles))
        assertEquals("Every year and every track day", Format.interval(0.0, 12, MeterUnit.miles, com.jackwallner.keyring.model.UsageEvent.trackDay))
        assertEquals("1,234.5 hrs", Format.reading(1_234.5, MeterUnit.hours))
        assertEquals("1,234 hrs", Format.reading(1_234.0, MeterUnit.hours))
        assertEquals("48,210 mi", Format.reading(48_210.0, MeterUnit.miles))
        assertEquals("18 months", Format.monthsText(18))
        assertEquals("2 years", Format.monthsText(24))
    }

    @Test fun relativeDates() {
        val zone = ZoneOffset.UTC
        fun rel(days: Long) = Format.relative(now.plusSeconds(days * 86_400), now, zone)
        assertEquals("today", rel(0))
        assertEquals("tomorrow", rel(1))
        assertEquals("yesterday", rel(-1))
        assertEquals("in 5 days", rel(5))
        assertEquals("3 weeks ago", rel(-21))
        assertEquals("in 3 months", rel(90))
        assertEquals("in 2 years", rel(800))
    }

    @Test fun asNeededJobShowsWhenItWasLastDone() {
        fun wash(last: Instant?) = TaskDue(
            task = MaintenanceTask(id = "w", vehicleId = "v", createdAt = now, catalogKey = "wash", name = "Wash"),
            result = DueResult(DueStatus.OK, null, null, 0.0, false), lastDate = last, lastReading = null,
            meter = MeterUnit.miles, currentReading = 0.0,
        )
        assertFalse(wash(null).hasInterval)
        assertEquals("Not logged yet", DueCopy.dueLine(wash(null), now))
        assertEquals("Last done 5 days ago", DueCopy.dueLine(wash(now.minusSeconds(5 * 86_400)), now))
    }

    @Test fun vinValidation() {
        assertEquals("3TMCZ5AN2KM198431", NHTSAClient.normalizedVIN("3tmcz5an2km198431"))
        assertNull(NHTSAClient.normalizedVIN("3TMCZ5AN2KM19843"))
        assertNull(NHTSAClient.normalizedVIN("3TMCZ5AN2KMO98431"))
    }

    @Test fun vinDecodeParsing() {
        val json = """{"Results":[{"ModelYear":"2019","Make":"TOYOTA","Model":"Tacoma","Trim":"SR5","VehicleType":"TRUCK","BodyClass":"Pickup","FuelTypePrimary":"Gasoline","ElectrificationLevel":"","DisplacementL":"3.5","EngineCylinders":"6","DriveType":"4WD/4-Wheel Drive/4x4"}]}"""
        val decoded = NHTSAClient.parseDecode(json)!!
        assertEquals(2019, decoded.year)
        assertEquals("Toyota", decoded.make)
        assertEquals(VehicleKind.truck, decoded.kind)
        assertEquals(Powertrain.gasoline, decoded.powertrain)
        assertEquals("3.5L V6 · 4WD · Pickup", decoded.summary)
        assertNull(NHTSAClient.parseDecode("""{"Results":[{"Make":"","Model":""}]}"""))
    }

    @Test fun recallParsing() {
        val json = """{"Count":1,"results":[{"NHTSACampaignNumber":"20V682000","Component":"FUEL SYSTEM, GASOLINE:DELIVERY:FUEL PUMP","Summary":"Pump may fail.","Consequence":"Stall.","Remedy":"Replace.","ReportReceivedDate":"04/11/2020","parkIt":false,"parkOutSide":false}]}"""
        val recalls = NHTSAClient.parseRecalls(json)
        assertEquals(1, recalls.size)
        assertEquals("Fuel System, Gasoline", recalls[0].componentTitle)
        assertEquals(11, recalls[0].reported!!.monthValue)
        assertTrue(NHTSAClient.parseRecalls("garbage").isEmpty())
    }

    private val pump = Recall("20V682000", "FUEL SYSTEM, GASOLINE", "", "",
        "Dealers will replace the fuel pump free of charge. Toyota's numbers for this recall are 20TB02 and 20TA02 for Toyota vehicles and J16/J06.",
        null, parkIt = false, parkOutside = false)

    @Test fun makerCodesAndNHTSAForms() {
        assertEquals(listOf("20TB02", "20TA02", "J16", "J06"), RecallMatcher.makerCodes(pump))
        assertEquals(listOf("20V682000", "20V-682", "20V682"), RecallMatcher.nhtsaForms(pump))
    }

    @Test fun mentionsNeedsRecallContextForShortCodes() {
        assertTrue(RecallMatcher.mentions(pump, "Performed campaign 20TA02 fuel pump"))
        assertTrue(RecallMatcher.mentions(pump, "NHTSA 20V-682 complete"))
        assertTrue(RecallMatcher.mentions(pump, "SAFETY RECALL J16 COMPLETED"))
        assertFalse(RecallMatcher.mentions(pump, "Part J16 wiper insert"))
        assertFalse(RecallMatcher.mentions(pump, "Invoice 120TA021"))
    }

    @Test fun notesOrALoggedFixCloseTheRecall() {
        fun entry(title: String, notes: String? = null, campaign: String? = null, kind: EntryKind = EntryKind.service) =
            ServiceEntry(id = title, vehicleId = "v", createdAt = now, date = now, title = title, notes = notes, recallCampaign = campaign, kind = kind)
        assertNull(RecallMatcher.fix(pump, listOf(entry("Oil change"))))
        assertEquals("Oil change", RecallMatcher.fix(pump, listOf(entry("Oil change", "Dealer also did safety recall 20TA02.")))?.title)
        assertEquals("Fix", RecallMatcher.fix(pump, listOf(entry("Fix", campaign = "20V682000", kind = EntryKind.recall)))?.title)
        assertNull(RecallMatcher.fix(pump, listOf(entry("Fuel", "20V682000", kind = EntryKind.fuel))))
    }

    @Test fun amazonLinks() {
        val url = AmazonLinks.search("2019 Toyota Tacoma oil filter", "US")
        assertTrue(url.startsWith("https://www.amazon.com/s?"))
        assertTrue(AmazonLinks.search("wipers", "CA").startsWith("https://www.amazon.ca/"))
        assertTrue(url.contains("k=2019%20Toyota%20Tacoma%20oil%20filter"))
        assertFalse(url.contains("tag="))
        fun truck(year: Int, make: String?, model: String?) = com.jackwallner.keyring.data.Vehicle("t", java.time.Instant.EPOCH,
            com.jackwallner.keyring.model.VehicleKind.truck, com.jackwallner.keyring.model.Powertrain.gasoline, com.jackwallner.keyring.model.MeterUnit.miles,
            year = year, make = make, model = model)
        assertEquals("2019 Toyota Tacoma oil filter", AmazonLinks.resolve("{vehicle} oil filter", truck(2019, "Toyota", "Tacoma")))
        assertEquals("truck oil filter", AmazonLinks.resolve("{vehicle} oil filter", truck(0, null, null)))
    }

    @Test fun fuelIsStoredInLiters() {
        assertEquals(FuelUnit.GALLONS, FuelUnit.current("US"))
        assertEquals(FuelUnit.LITERS, FuelUnit.current("DE"))
        assertEquals(37.854, FuelUnit.GALLONS.toLiters(10.0), 0.001)
        assertEquals(3.659, FuelUnit.GALLONS.fromPerLiter(FuelUnit.GALLONS.toPerLiter(3.659)), 1e-9)
    }

    @Test fun paywallCopyStaysHonest() {
        val plans = StoreService.previewPlans()
        assertEquals(listOf(StoreService.YEARLY, StoreService.MONTHLY, StoreService.LIFETIME), plans.map { it.productId })
        assertEquals(listOf("$14.99", "$1.99", "$29.99"), plans.map { it.priceFormatted })
        val yearly = plans[0]
        val monthly = plans[1]
        assertEquals("$14.99 / year", yearly.priceLabel)
        assertEquals("$14.99 per year", ConversionCopy.billedAmount(yearly.priceLabel))
        assertEquals("7-day free trial", yearly.introOfferLabel)
        assertEquals(37, yearly.savingsPercent(monthly))
        assertEquals("7-day free trial included · Cancel anytime", ConversionCopy.billedNote(yearly.introOfferLabel, true))
        assertEquals("Billed automatically · Cancel anytime", ConversionCopy.billedNote(yearly.introOfferLabel, false))
        assertTrue(ConversionCopy.disclosure(yearly.introOfferLabel, yearly.priceLabel, true, false).startsWith("$14.99 / year after the 7-day free trial."))
        assertEquals("$29.99. One-time purchase. Nothing renews.", ConversionCopy.disclosure(null, "$29.99", false, true))
        assertEquals("Continue with Pro", ConversionCopy.CTA)
        assertEquals("Purchase wasn't completed. Tap again to continue.", ConversionCopy.purchaseCancelledMessage(false))
        assertEquals(PackageKind.LIFETIME, PackageKind.fromIdentifiers("\$rc_lifetime", StoreService.LIFETIME))
        val week = Plan("m", "x", PackageKind.MONTHLY, 1, "$1", "USD", PlanPeriod(1, PeriodUnit.MONTH), PlanPeriod(3, PeriodUnit.DAY))
        assertEquals("3-day free trial", week.introOfferLabel)
    }

    @Test fun reviewerAccessNeedsTheExactCode() {
        val digest = MessageDigest.getInstance("SHA-256").digest("garage-review".toByteArray()).joinToString("") { "%02x".format(it) }
        val defaults = InMemoryStore()
        val access = ReviewAccess(defaults, digest)
        assertFalse(access.isGranted)
        assertFalse(access.activate("wrong"))
        assertTrue(access.activate(" garage-review "))
        assertTrue(ReviewAccess(defaults, digest).isGranted)
        // A build without a configured digest never grants anything.
        assertFalse(ReviewAccess(InMemoryStore(), "").activate("garage-review"))
    }

    @Test fun reviewPromptFromTheSecondLaunchMonthly() {
        var clock = 1_000_000_000_000L
        val prompter = ReviewPrompter(InMemoryStore()) { clock }
        prompter.recordLaunch()
        assertFalse(prompter.shouldAsk())
        prompter.recordLaunch()
        assertTrue(prompter.shouldAsk())
        prompter.markAsked()
        assertFalse(prompter.shouldAsk())
        clock += ReviewPrompter.COOLDOWN_MS
        assertTrue(prompter.shouldAsk())
        prompter.isAutomationRun = true
        assertFalse(prompter.shouldAsk())
    }
}
