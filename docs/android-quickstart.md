# Android Quickstart

> **DocC mirror:** Also available as the `AndroidAndGooglePlay` article and tutorial chapter 2 ("Android Quick Start") in the `ShipItKit` DocC archive.

Get your first Android build shipped with ShipItSwifty.

## Prerequisites

- Xcode CLI tools or Homebrew (`swift`, `swift build`)
- An Android project with a `gradlew` wrapper at the project root
- A Google Play service account JSON key (for Play Store uploads)
- `bundletool` on PATH (for `validate bundle`: `brew install bundletool`)

## 1. Install ShipItSwifty

```bash
# From source
git clone https://github.com/shipitswifty/shipitswifty
cd ShipItSwifty
swift build -c release
cp .build/release/shipit /usr/local/bin/shipit
```

## 2. Auto-detect your project

Run `ai-session` from your Android project root. ShipItSwifty detects `gradlew` and produces an Android-specific bootstrap payload:

```bash
cd /path/to/MyAndroidApp
shipit ai-session --goal beta --platform android --output json
```

The response includes:
- Detected platform (`.android`)
- Required secrets (`GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`)
- A ready-to-use `Shipfile.yml` draft
- The next recommended command

## 3. Create a Shipfile

```bash
shipit generate --goal beta --platform android --non-interactive --output json
```

Or write one manually:

```yaml
# Shipfile.yml
platform: android

android:
  module: app
  build_variant: release
  package_name: com.example.myapp
  play_track: internal
  keystore_path: ./certs/release.keystore
  keystore_password: ${ANDROID_KEYSTORE_PASSWORD}
  key_alias: release
  key_password: ${ANDROID_KEY_PASSWORD}

workflows:
  beta:
    steps:
      - action: test
      - action: archive
      - action: validate_bundle
      - action: play_store
```

## 4. Set credentials

```bash
export ANDROID_KEYSTORE_PASSWORD=...
export ANDROID_KEY_PASSWORD=...
export GOOGLE_PLAY_SERVICE_ACCOUNT_JSON="$(cat service-account.json)"
```

## 5. Run a dry-run

```bash
shipit run beta --dry-run --output json
```

## 6. Ship it

```bash
shipit run beta --ci --output json
```

## Individual commands

```bash
# Build APK
shipit build --platform android

# Run unit tests
shipit test --platform android

# Build AAB
shipit archive --platform android

# Run lint
shipit lint --platform android

# Validate the AAB before uploading
shipit validate bundle --bundle ./app/build/outputs/bundle/release/app-release.aab

# Upload to Google Play
shipit play-store --platform android
```

## Platform auto-detection

When `--platform` is omitted, ShipItSwifty checks the current directory:

| File found | Detected platform |
|---|---|
| `gradlew` or `build.gradle.kts` | Android |
| `*.xcworkspace` or `*.xcodeproj` | iOS |
| (nothing) | iOS (default) |

## Google Play service account setup

1. Open [Google Cloud Console](https://console.cloud.google.com)
2. Create a service account under your project
3. Grant it the **Release Manager** role in Google Play Console
4. Download the JSON key file
5. Set `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` or `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH`

## Troubleshooting

**`gradlew: Permission denied`**

```bash
chmod +x ./gradlew
```

**`bundletool: command not found`**

```bash
brew install bundletool
```

**`Google Play upload failed: 401`**

Check that your service account has the Release Manager role in Google Play Console (not just Google Cloud Console).

**Build uses `gradle` instead of `./gradlew`**

ShipItSwifty uses `./gradlew` when it exists in the working directory or the configured `gradlew_path`. If neither is present, it falls back to `gradle` on PATH. Set `android.gradlew_path` in `Shipfile.yml` to override.
