// A plain JVM project (no Android SDK needed) whose tests have scripted outcomes, run with the real
// `org.gradle.test-retry` plugin so integration tests see the XML a retry plugin actually writes.
plugins {
    java
    id("org.gradle.test-retry") version "1.6.6"
}

repositories { mavenCentral() }

dependencies {
    testImplementation(platform("org.junit:junit-bom:6.1.3"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

// Compile for Java 17 on whichever JDK (17 or newer) is installed; a pinned toolchain would need auto-provisioning.
tasks.withType<JavaCompile> { options.release.set(17) }

tasks.test {
    useJUnitPlatform()
    // Three executions per failing test (the first plus two retries) inside one Gradle run.
    retry { maxRetries.set(2) }
}
