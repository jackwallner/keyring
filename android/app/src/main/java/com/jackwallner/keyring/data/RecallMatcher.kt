package com.jackwallner.keyring.data

import com.jackwallner.keyring.model.EntryKind

/**
 * Finds recalls the log already shows were done, ported from `RecallMatcher.swift`:
 * a fix logged against the recall, or an entry whose title or notes name its
 * number. NHTSA's per-VIN repair status is behind reCAPTCHA, so the log decides.
 */
object RecallMatcher {
    private val makerPattern = Regex("""numbers? for this recall (?:is|are) ([^.]+)""", RegexOption.IGNORE_CASE)

    /** The maker's own numbers ("Toyota's numbers for this recall are J16/J06"). */
    fun makerCodes(recall: Recall): List<String> {
        val codes = mutableListOf<String>()
        for (match in makerPattern.findAll(recall.remedy)) {
            for (token in match.groupValues[1].uppercase().split(Regex("[^A-Z0-9]+"))) {
                if (token.length !in 3..10 || token.none(Char::isDigit) || (token.none(Char::isLetter) && token.length < 5)) continue
                if (token !in codes) codes.add(token)
            }
        }
        return codes
    }

    /** NHTSA's number as people write it: 20V682000, 20V-682, 20V682. */
    fun nhtsaForms(recall: Recall): List<String> {
        val upper = recall.campaign.uppercase()
        if (upper.length < 6) return listOf(upper)
        val head = upper.take(3)
        val body = upper.drop(3).take(3)
        return listOf(upper, "$head-$body", "$head$body")
    }

    fun mentions(recall: Recall, text: String): Boolean {
        val upper = text.uppercase()
        // A short maker code like J16 could be a part number, so it only counts beside the word recall or campaign.
        val context = listOf("RECALL", "CAMPAIGN", "SSC", "SAFETY").any { it in upper }
        val terms = nhtsaForms(recall) + makerCodes(recall).filter { it.length >= 5 || context }
        return terms.any { term -> Regex("(?<![A-Z0-9])" + Regex.escape(term) + "(?![A-Z0-9])").containsMatchIn(upper) }
    }

    fun fix(recall: Recall, entries: List<ServiceEntry>): ServiceEntry? {
        val candidates = entries.filter { it.kind != EntryKind.fuel }
        candidates.firstOrNull { it.recallCampaign == recall.campaign }?.let { return it }
        return candidates.firstOrNull { entry -> mentions(recall, listOfNotNull(entry.title, entry.notes).joinToString("\n")) }
    }
}
