# Run JVM unit tests (default — no device needed)
shipit test --platform android

# Run instrumented tests on a connected device or running emulator
shipit test --platform android --kind instrumented --device-strategy connected

# Run instrumented tests, booting named emulators automatically
shipit test --platform android --kind instrumented \
    --device-strategy named-emulators --emulators "Pixel_7_API_34,Pixel_Tablet_API_34"

# Run root-scoped unit tests (all modules)
shipit test --platform android --scope root
