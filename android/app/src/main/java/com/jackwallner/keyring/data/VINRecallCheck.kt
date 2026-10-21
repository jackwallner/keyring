package com.jackwallner.keyring.data

import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject

/**
 * What NHTSA's VIN lookup said about one vehicle: which recalls are still
 * unrepaired on it. NHTSA guards that lookup with reCAPTCHA, so the app shows
 * its page with the VIN filled in, the owner taps Search, and the result is
 * read off the page. Kept on the device. Ported from `VINRecallCheck.swift`.
 */
data class VINRecallCheck(
    val vin: String,
    val date: Instant,
    /** False when NHTSA has no VIN data from this maker, so nothing can be hidden. */
    val covered: Boolean,
    val open: List<Open>,
    /** Campaigns on the model's list when the check ran; one listed later stays visible until the next check. */
    val known: List<String>,
) {
    data class Open(val nhtsa: String, val maker: String, val status: String, val summary: String)

    fun isOpen(recall: Recall): Boolean = open.any { key(it.nhtsa) == key(recall.campaign) }

    fun knew(recall: Recall): Boolean = known.any { key(it) == key(recall.campaign) }

    /** Still worth showing: open on this VIN, or listed after the check. */
    fun shows(recall: Recall): Boolean = !covered || isOpen(recall) || !knew(recall)

    /** Open on the VIN but missing from the model's list, as rows of their own. */
    fun unlisted(recalls: List<Recall>): List<Recall> {
        val listed = recalls.map { key(it.campaign) }.toSet()
        return open.filter { key(it.nhtsa) !in listed }.map { item ->
            Recall(
                campaign = item.nhtsa,
                component = if (item.maker.isEmpty()) "Recall ${item.nhtsa}" else "Recall ${item.maker}",
                summary = item.summary.lowercase().replaceFirstChar { it.uppercase() },
                consequence = "", remedy = item.status, reported = null, parkIt = false, parkOutside = false,
            )
        }
    }

    fun encode(): String = JSONObject().put("vin", vin).put("date", date.toEpochMilli()).put("covered", covered)
        .put("open", JSONArray(open.map { JSONObject().put("nhtsa", it.nhtsa).put("maker", it.maker).put("status", it.status).put("summary", it.summary) }))
        .put("known", JSONArray(known)).toString()

    companion object {
        const val LOOKUP_URL = "https://www.nhtsa.gov/recalls"
        /** The JavaScript bridge the page script posts the result to. */
        const val BRIDGE = "KeyringRecalls"

        /** NHTSA writes the same campaign as 25V455000 in its data and 25V455 on the VIN page. */
        fun key(campaign: String): String {
            val code = campaign.uppercase().filter { it.isLetterOrDigit() }
            return if (code.length == 9 && code.endsWith("000")) code.take(6) else code
        }

        /** A check from what the page script posted, or null if it isn't a result for this VIN. */
        fun parse(json: String, vin: String, known: List<Recall>, at: Instant = Instant.now()): VINRecallCheck? {
            val page = runCatching { JSONObject(json) }.getOrNull() ?: return null
            val state = page.optString("state")
            if (page.has("vin") && !page.isNull("vin") && !page.getString("vin").equals(vin, ignoreCase = true)) return null
            val campaigns = known.map { it.campaign }
            return when (state) {
                "none" -> VINRecallCheck(vin, at, false, emptyList(), campaigns)
                "ok" -> VINRecallCheck(vin, at, true, opens(page.optJSONArray("recalls")), campaigns)
                else -> null
            }
        }

        fun decode(text: String?): VINRecallCheck? {
            val o = text?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return null
            return runCatching {
                VINRecallCheck(o.getString("vin"), Instant.ofEpochMilli(o.getLong("date")), o.getBoolean("covered"), opens(o.optJSONArray("open")),
                    o.optJSONArray("known")?.let { a -> (0 until a.length()).map { a.getString(it) } }.orEmpty())
            }.getOrNull()
        }

        private fun opens(array: JSONArray?): List<Open> = (0 until (array?.length() ?: 0)).mapNotNull { index ->
            array?.optJSONObject(index)?.let { Open(it.optString("nhtsa"), it.optString("maker"), it.optString("status"), it.optString("summary")) }
        }

        /** Fills the VIN in and watches for the result. It never presses Search: the owner does, on NHTSA's own page. */
        fun pageScript(vin: String): String {
            val clean = vin.uppercase().filter { it.isLetterOrDigit() }
            return """
            (function () {
              const vin = "$clean";
              if (window.__vinCheck) return; window.__vinCheck = true;
              function field() {
                return document.getElementById('ymm-vin-recalls-search-input')
                  || [...document.querySelectorAll('input')].find(i => /VIN/i.test(i.placeholder || ''));
              }
              function fill() {
                const el = field(); if (!el) return false;
                if (el.value !== vin) {
                  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, vin);
                  el.dispatchEvent(new Event('input', { bubbles: true }));
                  el.dispatchEvent(new Event('change', { bubbles: true }));
                }
                el.scrollIntoView({ block: 'center' });
                return true;
              }
              function read() {
                const box = document.querySelector('.active-recalls--list'); if (!box) return null;
                const text = box.innerText;
                const page = document.body.innerText;
                const shown = (page.match(/VIN:\s*([A-HJ-NPR-Z0-9]{17})/) || [])[1];
                if (/No recall information found/i.test(text)) return { state: 'none', vin: shown };
                const count = (text.match(/(\d+)\s*Unrepaired Recall/) || [])[1];
                if (count === undefined) return null;
                const recalls = text.split('Manufacturer Recall Number').slice(1).map(b => ({
                  maker: ((b.match(/^\s*([A-Z0-9-]+)/) || [])[1] || ''),
                  nhtsa: ((b.match(/NHTSA Recall Number\s*([0-9]{2}[A-Z][0-9]{3,6})/) || [])[1] || ''),
                  status: ((b.match(/Recall Status\s*([^\n]+)/) || [])[1] || '').trim(),
                  summary: ((b.match(/Summary\s*\n+([^\n]+)/) || [])[1] || '').trim()
                })).filter(r => r.nhtsa);
                if (recalls.length < Number(count)) return null;
                return { state: 'ok', vin: shown, count: Number(count), recalls };
              }
              let filled = false;
              const timer = setInterval(() => {
                if (!filled) filled = fill();
                const result = read();
                if (result) { clearInterval(timer); window.$BRIDGE.postMessage(JSON.stringify(result)); }
              }, 400);
            })();
            """.trimIndent()
        }
    }
}

/** The last VIN check per vehicle, under the iOS key. A changed VIN drops the old answer. */
class VINRecallChecks(private val defaults: KeyValueStore) {
    fun check(vehicle: Vehicle): VINRecallCheck? {
        val check = VINRecallCheck.decode(defaults.getString(KEY + vehicle.id)) ?: return null
        val vin = vehicle.vin ?: return null
        return check.takeIf { it.vin.equals(vin, ignoreCase = true) }
    }

    fun save(check: VINRecallCheck, vehicle: Vehicle) = defaults.putString(KEY + vehicle.id, check.encode())

    companion object {
        const val KEY = "vinRecallChecks."
    }
}
