$ shipit build --platform ios

[ShipIt] Resolved platform: ios
[ShipIt] Resolved build systems — iOS: kmp, Android: native
[ShipIt] Running :shared:linkReleaseFrameworkIosSimulatorArm64
> Task :shared:linkReleaseFrameworkIosSimulatorArm64 UP-TO-DATE
[ShipIt] Building iOS scheme 'iosApp' (Release)
xcodebuild ... -workspace iosApp/iosApp.xcworkspace -scheme iosApp -configuration Release build
** BUILD SUCCEEDED **
