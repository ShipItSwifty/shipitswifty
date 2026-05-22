plugins {
    kotlin("multiplatform")
}

kotlin {
    iosSimulatorArm64()
    iosArm64()
    androidTarget()
}
