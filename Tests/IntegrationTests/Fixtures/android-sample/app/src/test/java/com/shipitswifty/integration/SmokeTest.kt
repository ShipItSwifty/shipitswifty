package com.shipitswifty.integration

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Trivial JUnit test in the Android fixture project.
 * Exists so `./gradlew testDebugUnitTest` has something to run.
 */
class SmokeTest {
    @Test
    fun arithmeticPasses() {
        assertEquals(2, 1 + 1)
    }

    @Test
    fun bundleIdIsCorrect() {
        assertEquals("com.shipitswifty.integration", "com.shipitswifty.integration")
    }
}
