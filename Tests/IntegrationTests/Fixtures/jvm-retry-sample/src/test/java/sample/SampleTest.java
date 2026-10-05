package sample;

import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Outcomes are scripted through the environment so one project can play every role:
 *
 * <ul>
 *   <li>{@code SHIPIT_SAMPLE_FAIL=1}: {@code alwaysFailsWhenAsked} fails.
 *   <li>{@code SHIPIT_SAMPLE_FLAKY_DIR=<dir>}: {@code recoversInsideGradle} fails once, and
 *       {@code recoversAcrossRuns} fails three times (a whole Gradle run's worth of retries), each remembered by a
 *       counter file, because separate Gradle runs are separate processes.
 * </ul>
 */
class SampleTest {
    /** How many times this test started before now; "large" when flakiness is not scripted. */
    static int startedBefore(String name) throws Exception {
        String directory = System.getenv("SHIPIT_SAMPLE_FLAKY_DIR");
        if (directory == null) return Integer.MAX_VALUE;
        Path file = Paths.get(directory, name);
        Files.createDirectories(file.getParent());
        int before = Files.exists(file) ? Integer.parseInt(Files.readString(file).trim()) : 0;
        Files.writeString(file, String.valueOf(before + 1));
        return before;
    }

    @Test
    void passes() {}

    @Disabled("skipped on purpose")
    @Test
    void skipped() {}

    @Test
    void recoversInsideGradle() throws Exception {
        Assertions.assertTrue(startedBefore("inside") >= 1, "fails on its first execution only");
    }

    @Test
    void recoversAcrossRuns() throws Exception {
        Assertions.assertTrue(startedBefore("across") >= 3, "fails every execution of the first Gradle run");
    }

    @Test
    void alwaysFailsWhenAsked() {
        Assertions.assertFalse("1".equals(System.getenv("SHIPIT_SAMPLE_FAIL")), "asked to fail");
    }
}
