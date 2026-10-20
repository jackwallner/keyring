package com.jackwallner.keyring.model

import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Currency
import java.util.Locale

/** Every number and date the app shows, formatted one way. Ported from `Format.swift`. */
object Format {
    private fun grouped(value: Long, locale: Locale = Locale.getDefault()): String = NumberFormat.getIntegerInstance(locale).format(value)

    fun reading(value: Double, meter: MeterUnit, locale: Locale = Locale.getDefault()): String = when (meter) {
        MeterUnit.hours -> {
            // Hobbs and tach meters read in tenths.
            val tenths = swiftRound(value * 10) / 10
            val text = if (tenths == swiftRound(tenths)) grouped(tenths.toLong(), locale)
            else NumberFormat.getNumberInstance(locale).apply { minimumFractionDigits = 1; maximumFractionDigits = 1 }.format(tenths)
            "$text hrs"
        }
        MeterUnit.none -> ""
        else -> "${grouped(swiftRound(value).toLong(), locale)} ${meter.short}"
    }

    /** "Every 7,500 mi or 1 year", "Every year", "As needed". */
    fun interval(distance: Double, months: Int, meter: MeterUnit, trigger: UsageEvent? = null, locale: Locale = Locale.getDefault()): String {
        val amounts = if (distance > 0 && meter.hasReading) listOf(reading(distance, meter, locale)) else emptyList()
        val base = when {
            amounts.isNotEmpty() && months > 0 -> "Every ${list(amounts + monthsText(months))}"
            amounts.isNotEmpty() -> "Every ${list(amounts)}"
            months > 0 -> if (months == 12) "Every year" else if (months == 1) "Every month" else "Every ${monthsText(months)}"
            else -> null
        }
        return when {
            base != null && trigger != null -> "$base and ${trigger.dueRule.replaceFirstChar { it.lowercaseChar() }}"
            base != null -> base
            trigger != null -> trigger.dueRule
            else -> "As needed"
        }
    }

    private fun list(items: List<String>): String =
        if (items.size <= 1) items.firstOrNull().orEmpty() else items.dropLast(1).joinToString(", ") + " or " + items.last()

    fun monthsText(months: Int): String {
        if (months % 12 == 0) {
            val years = months / 12
            return if (years == 1) "1 year" else "$years years"
        }
        return if (months == 1) "1 month" else "$months months"
    }

    fun money(value: Double, code: String = defaultCurrency(), locale: Locale = Locale.getDefault()): String {
        val fraction = if (swiftRound(value) == value || value >= 1_000) 0 else 2
        return NumberFormat.getCurrencyInstance(locale).apply {
            runCatching { currency = Currency.getInstance(code) }
            minimumFractionDigits = fraction
            maximumFractionDigits = fraction
        }.format(value)
    }

    /** A per-unit figure, to the tenth of a cent: $0.137. */
    fun unitPrice(value: Double, code: String = defaultCurrency(), locale: Locale = Locale.getDefault()): String =
        NumberFormat.getCurrencyInstance(locale).apply {
            runCatching { currency = Currency.getInstance(code) }
            minimumFractionDigits = 2
            maximumFractionDigits = 3
        }.format(value)

    fun defaultCurrency(): String = runCatching { Currency.getInstance(Locale.getDefault()).currencyCode }.getOrNull() ?: "USD"

    fun count(n: Int, singular: String, plural: String): String = "${grouped(n.toLong())} ${if (n == 1) singular else plural}"

    /** "in 3 weeks", "today", "2 months ago", in plain words. */
    fun relative(date: Instant, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String {
        val days = ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), date.atZone(zone).toLocalDate()).toInt()
        return when (days) {
            0 -> "today"
            1 -> "tomorrow"
            -1 -> "yesterday"
            in 2..13 -> "in $days days"
            in -13..-2 -> "${-days} days ago"
            in 14..59 -> "in ${days / 7} weeks"
            in -59..-14 -> "${-days / 7} weeks ago"
            in 60..729 -> "in ${swiftRound(days / 30.4).toInt()} months"
            in -729..-60 -> "${swiftRound(-days / 30.4).toInt()} months ago"
            else -> {
                val years = swiftRound(Math.abs(days) / 365.0).toInt()
                if (days > 0) "in $years years" else "$years years ago"
            }
        }
    }

    fun shortDate(date: Instant, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String {
        val day = date.atZone(zone).toLocalDate()
        val sameYear = day.year == now.atZone(zone).year
        return day.format(DateTimeFormatter.ofPattern(if (sameYear) "MMM d" else "MMM d, yyyy", Locale.getDefault()))
    }

    fun longDate(day: LocalDate): String = day.format(DateTimeFormatter.ofPattern("MMMM d, yyyy", Locale.getDefault()))
}

/** What Pro adds, ported from `ProFeature` in `PaywallView.swift`. */
enum class ProFeature(val title: String, val detail: String, val headline: String) {
    unlimitedVehicles("Every vehicle you own", "Your first two are free forever. Pro adds the boat, the bikes, the RV and the mower.", "Room for the\nwhole garage"),
    serviceRecord("Service Record PDF", "Every job, receipt and reading on clean pages. Print it for the glovebox or send it to a buyer.", "A service record\nthat sells the car"),
    insights("Where the money goes", "Spending by vehicle and by kind of work, and your real cost per mile.", "See where the\nmoney goes");

    companion object {
        const val FREE_VEHICLE_LIMIT = 2

        fun canAddVehicle(activeCount: Int, isPro: Boolean): Boolean = isPro || activeCount < FREE_VEHICLE_LIMIT
    }
}

/** Outside links. Amazon and values open in the browser, never inside the app. */
object AppLinks {
    const val PRIVACY = "https://jackwallner.github.io/keyring/privacy-policy.html"
    const val TERMS = "https://jackwallner.github.io/keyring/terms.html"
    const val SUPPORT = "https://jackwallner.github.io/keyring/support.html"
    const val SUPPORT_EMAIL = "jackwallner@gmail.com"
    const val PACKAGE = "com.jackwallner.keyring"
    const val PLAY_LISTING = "https://play.google.com/store/apps/details?id=$PACKAGE"

    fun manageSubscription(productId: String?): String =
        if (productId == null) "https://play.google.com/store/account/subscriptions"
        else "https://play.google.com/store/account/subscriptions?sku=$productId&package=$PACKAGE"
}

object AmazonLinks {
    const val ASSOCIATE_TAG = ""
    val isAffiliate: Boolean get() = ASSOCIATE_TAG.isNotEmpty()

    fun host(region: String?): String = when (region) {
        "CA" -> "www.amazon.ca"
        "GB", "IE" -> "www.amazon.co.uk"
        "AU", "NZ" -> "www.amazon.com.au"
        "DE", "AT", "CH" -> "www.amazon.de"
        "FR", "BE" -> "www.amazon.fr"
        "IT" -> "www.amazon.it"
        "ES" -> "www.amazon.es"
        "NL" -> "www.amazon.nl"
        "MX" -> "www.amazon.com.mx"
        "JP" -> "www.amazon.co.jp"
        "IN" -> "www.amazon.in"
        else -> "www.amazon.com"
    }

    fun search(query: String, region: String? = Locale.getDefault().country): String {
        val k = java.net.URLEncoder.encode(query, "UTF-8").replace("+", "%20")
        val tag = if (isAffiliate) "&tag=$ASSOCIATE_TAG" else ""
        return "https://${host(region)}/s?k=$k$tag"
    }

    /** Fills `{vehicle}` and `{make}`; a vehicle with no make or model falls back to its kind. */
    fun resolve(template: String, descriptor: String, make: String?, kindTitle: String): String {
        val vehicle = descriptor.ifEmpty { kindTitle.lowercase() }
        return template.replace("{vehicle}", vehicle).replace("{make}", make?.ifEmpty { null } ?: kindTitle.lowercase())
    }
}
