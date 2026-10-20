package com.jackwallner.keyring.data

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.keyring.BuildConfig
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Offering
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PackageType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesException
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.models.Period
import com.revenuecat.purchases.paywalls.events.CustomPaywallImpressionParams
import kotlin.coroutines.cancellation.CancellationException

enum class PurchaseOutcome { PURCHASED, PENDING, CANCELLED }

class PurchaseException(message: String) : Exception(message)

internal fun purchaseOutcome(code: PurchasesErrorCode, userCancelled: Boolean): PurchaseOutcome? = when {
    userCancelled || code == PurchasesErrorCode.PurchaseCancelledError -> PurchaseOutcome.CANCELLED
    code == PurchasesErrorCode.PaymentPendingError -> PurchaseOutcome.PENDING
    else -> null
}

private fun Period.toPlanPeriod(): PlanPeriod? {
    val unit = when (unit) {
        Period.Unit.DAY -> PeriodUnit.DAY
        Period.Unit.WEEK -> PeriodUnit.WEEK
        Period.Unit.MONTH -> PeriodUnit.MONTH
        Period.Unit.YEAR -> PeriodUnit.YEAR
        else -> return null
    }
    return PlanPeriod(value, unit)
}

/**
 * RevenueCat behind the single `pro` entitlement, ported from `StoreService.swift`.
 * Debug builds take only a Test Store key and release builds only the Play
 * key; a missing key leaves the app fully usable on the free tier.
 */
class StoreService(private val context: Context, private val defaults: KeyValueStore) {
    private val reviewAccess = ReviewAccess(defaults, BuildConfig.PLAY_REVIEW_CODE_SHA256)
    private var entitlementActive by mutableStateOf(defaults.getBoolean(CACHED_PRO))
    private var reviewGranted by mutableStateOf(reviewAccess.isGranted)
    private var forcePro by mutableStateOf(false)

    /** The single gate the whole app reads. */
    val isPro: Boolean get() = entitlementActive || reviewGranted || forcePro

    var isConfigured by mutableStateOf(false)
        private set
    var isLoading by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set
    var plans by mutableStateOf<List<Plan>>(emptyList())
        private set
    var hasSubscriptionHistory by mutableStateOf(false)
        private set
    var introEligibilityResolved by mutableStateOf(false)
        private set
    var activeProductId by mutableStateOf<String?>(null)
        private set

    private var packages: List<Package> = emptyList()
    private var offering: Offering? = null
    private var isPreview = false

    fun forceProForDebug(value: Boolean = true) {
        if (BuildConfig.DEBUG) forcePro = value
    }

    /** Debug screenshots and UI tests: the US ladder with no store behind it. */
    fun loadPreviewPlans(plans: List<Plan>) {
        if (!BuildConfig.DEBUG) return
        this.plans = plans
        packages = emptyList()
        introEligibilityResolved = true
        isConfigured = true
        isPreview = true
        errorMessage = null
    }

    fun activateReviewAccess(code: String): Boolean {
        if (!reviewAccess.activate(code)) return false
        reviewGranted = true
        return true
    }

    suspend fun start() {
        if (!configureIfNeeded()) {
            errorMessage = if (plans.isEmpty()) UNAVAILABLE else null
            return
        }
        refreshCustomerInfo()
        fetchPlans()
    }

    suspend fun refreshCustomerInfo() {
        if (!configureIfNeeded() || isPreview) return
        runCatching { Purchases.sharedInstance.awaitCustomerInfo() }
            .onSuccess(::apply)
            .onFailure { if (it is CancellationException) throw it }
    }

    suspend fun fetchPlans() {
        if (isPreview) return
        if (!configureIfNeeded()) {
            errorMessage = UNAVAILABLE
            return
        }
        if (isLoading) return
        isLoading = true
        try {
            val offerings = Purchases.sharedInstance.awaitOfferings()
            val offering = offerings.all[OFFERING_ID] ?: offerings.current
            val loaded = offering?.availablePackages.orEmpty().sortedBy { kind(it).ordinal }
            this.offering = offering
            packages = loaded
            plans = loaded.map(::plan)
            errorMessage = if (loaded.isEmpty()) "Plans are temporarily unavailable. Please try again in a moment." else null
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            packages = emptyList()
            plans = emptyList()
            errorMessage = "Couldn't load plans. Check your connection and try again."
        } finally {
            isLoading = false
        }
    }

    fun isEligibleForIntroOffer(plan: Plan): Boolean = plan.trial != null && introEligibilityResolved && !hasSubscriptionHistory

    fun trackPaywallImpression(id: String) {
        if (!isConfigured || isPreview) return
        val params = offering?.let { CustomPaywallImpressionParams(id, it) } ?: CustomPaywallImpressionParams(id)
        runCatching { Purchases.sharedInstance.trackCustomPaywallImpression(params) }
    }

    /** A cancel is an outcome, not an error. Throws only with a user-facing message. */
    suspend fun purchase(activity: Activity, plan: Plan): PurchaseOutcome {
        if (isPreview) {
            forceProForDebug()
            return PurchaseOutcome.PURCHASED
        }
        val pkg = packages.firstOrNull { it.identifier == plan.packageId }
        if (!configureIfNeeded() || pkg == null) throw PurchaseException(UNAVAILABLE)
        val option = if (isEligibleForIntroOffer(plan)) pkg.product.defaultOption else pkg.product.subscriptionOptions?.basePlan
        val params = if (option != null) {
            PurchaseParams.Builder(activity, option).presentedOfferingContext(pkg.presentedOfferingContext).build()
        } else PurchaseParams.Builder(activity, pkg).build()
        return try {
            val result = Purchases.sharedInstance.awaitPurchase(params)
            apply(result.customerInfo)
            if (!entitlementActive) refreshCustomerInfo()
            if (entitlementActive) PurchaseOutcome.PURCHASED else PurchaseOutcome.PENDING
        } catch (error: PurchasesTransactionException) {
            purchaseOutcome(error.code, error.userCancelled) ?: throw PurchaseException(
                if (isEligibleForIntroOffer(plan)) "Couldn't start your trial. Please try again." else "Couldn't complete the purchase. Please try again.",
            )
        }
    }

    /** Leaves `errorMessage` set when nothing was restored, like iOS. */
    suspend fun restore() {
        errorMessage = null
        if (isPreview) return
        if (!configureIfNeeded()) {
            errorMessage = UNAVAILABLE
            return
        }
        try {
            apply(Purchases.sharedInstance.awaitRestore())
            if (!entitlementActive) errorMessage = "No active Pro purchase was found for this Google Play account."
        } catch (error: CancellationException) {
            throw error
        } catch (error: PurchasesException) {
            errorMessage = if (error.code == PurchasesErrorCode.PaymentPendingError) {
                "Google Play is still processing your payment. Pro unlocks as soon as it completes."
            } else "Couldn't restore purchases. Try again."
        } catch (_: Throwable) {
            errorMessage = "Couldn't restore purchases. Try again."
        }
    }

    private fun apply(info: CustomerInfo) {
        hasSubscriptionHistory = info.allExpirationDatesByProduct.isNotEmpty()
        introEligibilityResolved = true
        // Single premium tier: any active entitlement unlocks Pro, which survives renames in the dashboard.
        entitlementActive = info.entitlements.active.isNotEmpty()
        defaults.putBoolean(CACHED_PRO, entitlementActive)
        activeProductId = info.activeSubscriptions.map { it.substringBefore(":") }.sorted().firstOrNull()
    }

    private fun configureIfNeeded(): Boolean {
        if (isConfigured) return true
        val key = BuildConfig.REVENUECAT_API_KEY
        if (key.isBlank()) return false
        // Never the production Play key in a debug build, and never a test key in release.
        if (BuildConfig.DEBUG && key.startsWith("goog_")) return false
        if (!BuildConfig.DEBUG && !key.startsWith("goog_")) return false
        Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.ERROR
        Purchases.configure(PurchasesConfiguration.Builder(context, key).build())
        Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener { apply(it) }
        isConfigured = true
        return true
    }

    private fun kind(pkg: Package): PackageKind = when (pkg.packageType) {
        PackageType.LIFETIME -> PackageKind.LIFETIME
        PackageType.ANNUAL -> PackageKind.YEARLY
        PackageType.MONTHLY -> PackageKind.MONTHLY
        else -> PackageKind.fromIdentifiers(pkg.identifier, pkg.product.id)
    }

    private fun plan(pkg: Package): Plan {
        val price = pkg.product.price
        val free = pkg.product.subscriptionOptions?.firstOrNull { it.freePhase != null }?.freePhase
            ?: pkg.product.defaultOption?.freePhase
        return Plan(
            packageId = pkg.identifier,
            productId = pkg.product.id,
            kind = kind(pkg),
            priceMicros = price.amountMicros,
            priceFormatted = price.formatted,
            currencyCode = price.currencyCode,
            period = pkg.product.period?.toPlanPeriod(),
            trial = free?.billingPeriod?.toPlanPeriod(),
            title = pkg.product.title,
        )
    }

    companion object {
        const val ENTITLEMENT = "pro"
        const val OFFERING_ID = "default"
        const val MONTHLY = "com.jackwallner.keyring.monthly"
        const val YEARLY = "com.jackwallner.keyring.yearly"
        const val LIFETIME = "com.jackwallner.keyring.lifetime"
        private const val CACHED_PRO = "cachedPro"
        private const val UNAVAILABLE = "Google Play isn't reachable right now. Check your connection and try again."

        const val PENDING_MESSAGE =
            "Waiting on Google Play to confirm this purchase. Pro turns on by itself as soon as it goes through, so there is nothing to tap again."
        const val RENEW_CLAUSE = "Auto-renews unless cancelled before the end of the current period. Manage or cancel in Google Play › Payments & subscriptions."

        /** `PaywallPreviewStore`: the US ladder, so the real paywall renders without a store. */
        fun previewPlans(): List<Plan> {
            val week = PlanPeriod(1, PeriodUnit.WEEK)
            return listOf(
                Plan("\$rc_annual", YEARLY, PackageKind.YEARLY, 14_990_000, "$14.99", "USD", PlanPeriod(1, PeriodUnit.YEAR), week, "Pro Yearly"),
                Plan("\$rc_monthly", MONTHLY, PackageKind.MONTHLY, 1_990_000, "$1.99", "USD", PlanPeriod(1, PeriodUnit.MONTH), week, "Pro Monthly"),
                Plan("\$rc_lifetime", LIFETIME, PackageKind.LIFETIME, 29_990_000, "$29.99", "USD", null, null, "Pro Lifetime"),
            )
        }
    }
}

/** Pure copy for Pro conversion surfaces, ported from `ConversionCopy.swift`. */
object ConversionCopy {
    const val CTA = "Continue with Pro"

    /** "$14.99 / year" -> "$14.99 per year". */
    fun billedAmount(priceLabel: String): String = priceLabel.replace(" / ", " per ")

    fun billedNote(trialLabel: String?, eligibleForTrial: Boolean): String =
        if (eligibleForTrial && !trialLabel.isNullOrEmpty()) "${trialLabel.lowercase()} included · Cancel anytime"
        else "Billed automatically · Cancel anytime"

    fun disclosure(trialLabel: String?, priceLabel: String, eligibleForTrial: Boolean, lifetime: Boolean): String = when {
        lifetime -> "$priceLabel. One-time purchase. Nothing renews."
        eligibleForTrial && !trialLabel.isNullOrEmpty() -> "$priceLabel after the ${trialLabel.lowercase()}. ${StoreService.RENEW_CLAUSE}"
        else -> "$priceLabel. ${StoreService.RENEW_CLAUSE}"
    }

    fun purchaseCancelledMessage(eligibleForTrial: Boolean): String =
        if (eligibleForTrial) "Trial wasn't started. Tap again to continue." else "Purchase wasn't completed. Tap again to continue."
}
