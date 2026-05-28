package com.helloworld

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ExampleUnitTest {
    @Test
    fun addition_isCorrect() {
        assertEquals(4, 2 + 2)
    }

    @Test
    fun string_isNotEmpty() {
        val appName = "HelloWorld"
        assertTrue(appName.isNotEmpty())
    }

    @Test
    fun packageName_isCorrect() {
        val pkg = ExampleUnitTest::class.java.packageName
        assertEquals("com.helloworld", pkg)
    }
}
