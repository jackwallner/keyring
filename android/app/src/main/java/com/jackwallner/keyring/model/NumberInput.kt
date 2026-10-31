package com.jackwallner.keyring.model

import java.text.DecimalFormatSymbols
import java.util.Locale

/**
 * Numbers a person types into a field, and an existing figure shown back for editing. The decimal key follows the
 * phone's language: a German or French keyboard types "59,99" where an English one types "59.99", and each writes
 * the other's decimal mark as a group ("12.500", "12,500"). Both read back to the figure that was meant.
 */
object NumberInput {
    /** The number in [text], or null when it isn't one. Never NaN or infinite. */
    fun parse(text: String, locale: Locale = Locale.getDefault()): Double? {
        var negative = false
        var signSeen = false
        val marked = StringBuilder()
        for (char in text) {
            when {
                char.isWhitespace() || char == ' ' || char == ' ' || char == '\'' || char == '’' -> Unit
                // Arabic decimal and group marks arrive as their own characters.
                char == '٫' -> marked.append('.')
                char == '٬' -> marked.append(',')
                char == '.' || char == ',' -> marked.append(char)
                (char == '-' || char == '+') && marked.isEmpty() && !signSeen -> {
                    signSeen = true
                    negative = char == '-'
                }
                Character.digit(char, 10) >= 0 -> marked.append(Character.digit(char, 10))
                else -> return null
            }
        }
        val digits = marked.toString()
        if (digits.none { it.isDigit() }) return null
        val localeDecimal = DecimalFormatSymbols.getInstance(locale).decimalSeparator
        val dots = digits.count { it == '.' }
        val commas = digits.count { it == ',' }
        val plain = when {
            dots == 0 && commas == 0 -> digits
            // Both marks: the later one is the decimal ("1.234,56", "1,234.56"), the other groups.
            dots > 0 && commas > 0 ->
                if (digits.lastIndexOf('.') > digits.lastIndexOf(',')) digits.replace(",", "")
                else digits.replace(".", "").replace(',', '.')
            else -> {
                val mark = if (dots > 0) '.' else ','
                val afterMark = digits.length - digits.lastIndexOf(mark) - 1
                val isDecimal = when {
                    dots + commas > 1 -> false    // "1,234,567"
                    mark == localeDecimal -> true // this keyboard's own decimal key
                    afterMark == 3 -> false       // the other mark with three digits after it groups: "45,210"
                    else -> true                  // "12.5" typed with a dot on a comma keyboard
                }
                if (isDecimal) digits.replace(mark, '.') else digits.replace(mark.toString(), "")
            }
        }
        return ((if (negative) "-" else "") + plain).toDoubleOrNull()?.takeIf { it.isFinite() }
    }

    /** A figure for a field being edited: whole numbers bare, otherwise up to three decimals in this phone's decimal mark. */
    fun plain(value: Double, locale: Locale = Locale.getDefault()): String {
        if (value % 1.0 == 0.0 && Math.abs(value) < 1e15) return value.toLong().toString()
        val text = String.format(Locale.ROOT, "%.3f", value).trimEnd('0').trimEnd('.')
        return text.replace('.', DecimalFormatSymbols.getInstance(locale).decimalSeparator)
    }
}
