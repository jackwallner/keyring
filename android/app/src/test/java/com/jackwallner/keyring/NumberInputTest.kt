package com.jackwallner.keyring

import com.jackwallner.keyring.model.NumberInput
import com.jackwallner.keyring.ui.theme.parseNumber
import java.util.Locale
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/**
 * What a person types into the number fields. The decimal key on the keyboard follows the phone's language, so a
 * German or French phone types "59,99" for fifty-nine ninety-nine; reading every comma as a thousands mark made it 5999.
 */
class NumberInputTest {
    private lateinit var saved: Locale

    @Before fun rememberLocale() { saved = Locale.getDefault() }

    @After fun restoreLocale() { Locale.setDefault(saved) }

    private fun typed(text: String, locale: Locale): Double? {
        Locale.setDefault(locale)
        return parseNumber(text)
    }

    private val spain = Locale.forLanguageTag("es-ES")

    @Test fun aCommaIsTheDecimalMarkWhereTheKeyboardTypesOne() {
        assertEquals(59.99, typed("59,99", Locale.GERMANY)!!, 0.0)
        assertEquals(12.5, typed("12,5", Locale.FRANCE)!!, 0.0)
        assertEquals(1.759, typed("1,759", spain)!!, 0.0)
    }

    @Test fun aDotGroupsThousandsInThoseLocales() {
        assertEquals(12_500.0, typed("12.500", Locale.GERMANY)!!, 0.0)
        assertEquals(1_234_567.0, typed("1.234.567", spain)!!, 0.0)
        assertEquals(1_234.56, typed("1.234,56", Locale.GERMANY)!!, 0.0)
    }

    @Test fun englishKeepsCommaGroupsAndDotDecimals() {
        assertEquals(45_210.0, typed("45,210", Locale.US)!!, 0.0)
        assertEquals(45_210.0, typed("45 210", Locale.US)!!, 0.0)
        assertEquals(12.5, typed("12.5", Locale.US)!!, 0.0)
        assertEquals(1_234.56, typed("1,234.56", Locale.US)!!, 0.0)
        assertEquals(0.5, typed(".5", Locale.US)!!, 0.0)
    }

    @Test fun aDecimalDotTypedOnAnyKeyboardStillReadsAsADecimal() {
        assertEquals(59.99, typed("59.99", Locale.GERMANY)!!, 0.0)
        assertEquals(123.4, typed("123.4", Locale.FRANCE)!!, 0.0)
    }

    @Test fun whatIsNotANumberIsNotOne() {
        for (text in listOf("", " ", "-", ",", "abc", "NaN", "Infinity", "-Infinity", "1e999")) {
            assertNull("'$text' read as a number", typed(text, Locale.US))
        }
    }

    @Test fun editingShowsTheFigureInThePhonesDecimalMarkAndSavesTheSameFigure() {
        assertEquals("59,99", NumberInput.plain(59.99, Locale.GERMANY))
        assertEquals("59.99", NumberInput.plain(59.99, Locale.US))
        assertEquals("3,659", NumberInput.plain(3.659, Locale.FRANCE))
        assertEquals("52000", NumberInput.plain(52_000.0, Locale.GERMANY))
        for (locale in listOf(Locale.US, Locale.GERMANY, Locale.FRANCE, spain, Locale.UK)) {
            for (figure in listOf(59.99, 3.659, 1_234.5, 0.5, 12.0, 123_456.789)) {
                assertEquals("$figure in $locale", figure, NumberInput.parse(NumberInput.plain(figure, locale), locale)!!, 0.0005)
            }
        }
    }
}
