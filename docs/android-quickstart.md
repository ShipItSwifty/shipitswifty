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

Run `generate` from your Android project root. ShipItSwifty detects `gradlew`, walks through the missing values, and writes an Android-ready `Shipfile.yml`:

```bash
cd /path/to/MyAndroidApp
shipit generate --goal beta --platform android
```

The generated setup includes:
- Detected platform (`.android`)
- Required secrets (`GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`)
- A ready-to-use `Shipfile.yml` draft
- The next recommended command

## 3. Create a Shipfile

```bash
shipit generate --goal beta --platform android --non-interactive
```

Or write one manually:

```yaml
# Shipfile.yml
platform: android

android:
  module: app
  build_variant: release
  package_name: com.example.myapp
  keystore_path: ./certs/release.keystore
  keystore_password: ${ANDROID_KEYSTORE_PASSWORD}
  keystore_alias: release
  key_password: ${ANDROID_KEY_PASSWORD}

workflows:
  beta:
    - action: test
    - action: archive
    - action: validate-bundle
    - action: play-store
      options:
        track: internal
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
shipit validate bundle --aab ./app/build/outputs/bundle/release/app-release.aab

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

Need help locating these values? See [Credential Lookup](credential-lookup.md).

Use these values for Android setup:

| Value | Where to find it |
|---|---|
| `package_name` | Your Android application ID, usually `applicationId` in `app/build.gradle` or `app/build.gradle.kts` (for example `com.example.myapp`) |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Raw contents of the service account key JSON file |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` | Local filesystem path to that JSON key file |

Set up Play API access:

1. Open [Google Cloud Console](https://console.cloud.google.com) and create or choose a project.
2. Go to [APIs & Services](https://console.developers.google.com/apis/api/androidpublisher.googleapis.com/) and enable the **Google Play Developer API**.
3. Go to [Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts) and create a service account.
4. Create and download a JSON key for that service account.
5. Open [Google Play Console → Users and permissions](https://play.google.com/console/users-and-permissions).
6. Click **Invite new users** and paste the service account email (e.g. `my-sa@my-project.iam.gserviceaccount.com`).
7. Under the **App permissions** tab, add your specific app and grant the permissions below.
8. Click **Invite user**.

> **Important:** Only the Play Console **account owner** can invite new users. If you don't see the invite option, ask the account owner to perform steps 5–8.

> **Note:** You do **not** need to link your Google Cloud project to Play Console. Google removed that requirement — inviting the service account email directly via Users & permissions is sufficient.

Required permissions (under **App permissions** for your app):

- `View app information and download bulk reports (read-only)`
- `Release apps to testing tracks` — for `internal`, `alpha`, or `beta` uploads
- `Release to production, exclude devices, and use Play App Signing` — if you want production rollout
- `Manage store presence` — only if you also update store listings via the API

Then set one of these:

```bash
export GOOGLE_PLAY_SERVICE_ACCOUNT_JSON="$(cat service-account.json)"

# or
export GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH=./service-account.json
```

Notes:

- `shipit generate --platform android` can usually infer `package_name`, but the source of truth is your Gradle `applicationId`.
- The `track` option on the `play-store` step must match the kind of release you intend to publish. For early testing, start with `internal`.

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

Check that your service account has the required permissions in Google Play Console (not just Google Cloud Console). See the setup steps above.

**`Google Play upload failed: 403 — PERMISSION_DENIED`**

This means the service account lacks the required Play Console permissions for your app. Fix:

1. Go to [Users & permissions](https://play.google.com/console/users-and-permissions) in Play Console.
2. Find your service account email and click it.
3. Under **App permissions**, ensure your app is listed and the account has at least `Release apps to testing tracks` (or `Release to production…` for production uploads).
4. Verify the **Google Play Developer API** is enabled in your [Google Cloud project](https://console.developers.google.com/apis/api/androidpublisher.googleapis.com/).
5. If you recently changed permissions, wait a few minutes for propagation.
6. Confirm you're using the correct service account JSON key — the email in the key must match the invited user in Play Console.

> **Common cause:** The service account was granted only account-level permissions but not app-level permissions for the specific package. Always check the **App permissions** tab.

**Build uses `gradle` instead of `./gradlew`**

ShipItSwifty uses `./gradlew` when it exists in the working directory or the configured `gradlew_path`. If neither is present, it falls back to `gradle` on PATH. Set `android.gradlew_path` in `Shipfile.yml` to override.
