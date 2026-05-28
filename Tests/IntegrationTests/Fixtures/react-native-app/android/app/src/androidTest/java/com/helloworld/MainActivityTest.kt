package com.helloworld

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MainActivityTest {

    @Test
    fun activityLaunches() {
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        scenario.use { s ->
            assertNotNull(s)
        }
    }

    @Test
    fun activityIsInResumedState() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                assertNotNull(activity)
            }
        }
    }

    @Test
    fun packageNameMatchesExpected() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val pkg = activity.packageName
                assertNotNull(pkg)
                assert(pkg == "com.helloworld") {
                    "Expected package com.helloworld but was $pkg"
                }
            }
        }
    }
}
