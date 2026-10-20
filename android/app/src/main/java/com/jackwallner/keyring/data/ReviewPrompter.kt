package com.jackwallner.keyring.data

/**
 * When to ask for a Play rating, ported from `ReviewPrompter.swift`: after a
 * logged service, from the second launch, at most once a month. Google's
 * In-App Review rules forbid any question first, so there is no gate.
 */
class ReviewPrompter(private val defaults: KeyValueStore, private val now: () -> Long = System::currentTimeMillis) {
    /** Screenshot and test runs never trigger the store card. */
    var isAutomationRun = false

    fun recordLaunch() = defaults.putInt(LAUNCH_COUNT, defaults.getInt(LAUNCH_COUNT) + 1)

    fun shouldAsk(): Boolean {
        if (isAutomationRun || defaults.getInt(LAUNCH_COUNT) < 2) return false
        if (!defaults.contains(LAST_REQUEST)) return true
        return now() - defaults.getLong(LAST_REQUEST) >= COOLDOWN_MS
    }

    fun markAsked() = defaults.putLong(LAST_REQUEST, now())

    companion object {
        const val LAUNCH_COUNT = "launchCount"
        const val LAST_REQUEST = "lastReviewRequest"
        const val COOLDOWN_MS = 30L * 86_400_000L
    }
}
