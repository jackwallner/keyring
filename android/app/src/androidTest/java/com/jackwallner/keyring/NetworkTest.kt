package com.jackwallner.keyring

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jackwallner.keyring.data.NHTSAClient
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** The two production NHTSA feeds the app depends on, live from the device. */
@RunWith(AndroidJUnit4::class)
class NetworkTest {
    @Test fun decodesARealVIN() = runBlocking {
        val decoded = NHTSAClient.decode("3TMCZ5AN2KM198431")
        assertEquals(2019, decoded.year)
        assertEquals("Toyota", decoded.make)
        assertEquals("Tacoma", decoded.model)
    }

    @Test fun listsRecallsForAKnownModelYear() = runBlocking {
        val recalls = NHTSAClient.recalls(2020, "Toyota", "Tacoma")
        assertTrue("expected NHTSA recalls for a 2020 Tacoma", recalls.isNotEmpty())
        assertTrue(recalls.all { it.campaign.isNotBlank() })
    }
}
