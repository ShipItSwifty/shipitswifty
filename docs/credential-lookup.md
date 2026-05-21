# Credential Lookup

Quick reference for the values ShipItSwifty needs from App Store Connect and Google Play.

Use this when `shipit generate` cannot infer a value automatically, or when you are wiring credentials into CI.

## App Store Connect (iOS)

ShipItSwifty only needs App Store Connect credentials for Apple-backed actions such as `testflight`, `upload`, `metadata`, and `provision`.

Local Xcode-only actions like `build`, `test`, `archive`, and `export` do not require these values.

| Value | Where to find it |
|---|---|
| `team_id` | Usually auto-detected from Xcode signing. If you need it manually, use the 10-character Apple Developer Team ID for the team selected in Xcode Signing, or the same team shown in Certificates, IDs & Profiles. |
| `ASC_KEY_ID` | App Store Connect -> `Users and Access` -> `Integrations` -> `App Store Connect API` -> API key `Key ID` |
| `ASC_ISSUER_ID` | Same `App Store Connect API` page. This is not stored inside the downloaded `.p8` file. |
| `ASC_PRIVATE_KEY_PATH` | Local filesystem path to the downloaded `.p8` file |
| `ASC_PRIVATE_KEY` | Raw contents of the `.p8` file, usually stored directly in CI secrets |

### Typical lookup flow

1. Open `App Store Connect`.
2. Go to `Users and Access`.
3. Open `Integrations`.
4. Open `App Store Connect API`.
5. Create or select an API key.
6. Copy `Key ID` into `ASC_KEY_ID`.
7. Copy `Issuer ID` into `ASC_ISSUER_ID`.
8. Download the `.p8` file.

### Team ID notes

- `team_id` and `ASC_ISSUER_ID` are different values.
- If `shipit generate` or Xcode already resolves the correct team, you usually do not need to set `team_id` manually.
- If you do need to set it, prefer the team selected in your app target's Xcode Signing settings.

### Local shell example

```bash
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_PRIVATE_KEY_PATH=./.secrets/AuthKey_XXXXXXXXXX.p8
```

### CI example

```bash
ASC_KEY_ID=...
ASC_ISSUER_ID=...
ASC_PRIVATE_KEY=...      # raw .p8 contents
```

## Google Play (Android)

ShipItSwifty uses a Google Cloud service account with Play Console permissions for `play-store` uploads.

| Value | Where to find it |
|---|---|
| `package_name` | Your Android application ID, usually `applicationId` in `app/build.gradle` or `app/build.gradle.kts` |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Raw contents of the downloaded service account JSON key |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` | Local filesystem path to that JSON key file |

### Typical setup flow

1. Open [Google Cloud Console](https://console.cloud.google.com).
2. Create or select a Google Cloud project.
3. Enable the [Google Play Developer API](https://console.developers.google.com/apis/api/androidpublisher.googleapis.com/).
4. Go to [Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts) and create a service account.
5. Create and download a JSON key for that service account.
6. Open [Google Play Console → Users and permissions](https://play.google.com/console/users-and-permissions).
7. Click **Invite new users** and paste the service account email address.
8. Under the **App permissions** tab, add your app and grant the permissions below.
9. Click **Invite user**.

> **Important:** Only the Play Console **account owner** can invite users. If you cannot see the invite button, ask the account owner.

> **Note:** Linking a Google Cloud project to Play Console is no longer required. Inviting the service account email via Users & permissions is sufficient.

### Typical Play Console permissions

- `View app information and download bulk reports (read-only)`
- `Release apps to testing tracks` for `internal`, `alpha`, or `beta`
- `Release to production, exclude devices, and use Play App Signing` for production rollout
- `Manage store presence` — only if updating store listings via the API

### Troubleshooting 403 PERMISSION_DENIED

If `shipit play-store` returns HTTP 403 with `"The caller does not have permission"`:

1. **Check app-level permissions** — Go to [Users & permissions](https://play.google.com/console/users-and-permissions), click the service account, and verify it has permissions for your specific app under the **App permissions** tab (account-level permissions alone are not enough).
2. **Verify the API is enabled** — The [Google Play Developer API](https://console.developers.google.com/apis/api/androidpublisher.googleapis.com/) must be enabled in the same Cloud project that owns the service account.
3. **Confirm the correct key** — The `client_email` in your JSON key must match the email invited in Play Console.
4. **Wait for propagation** — Permission changes can take a few minutes to take effect.
5. **Account owner required** — Only the account owner can grant permissions. Admin access is not sufficient for managing API users.

### Track notes

- Start with `internal` for the simplest first upload.
- Use `production` only when you intend a real store rollout.
- `shipit generate --platform android` can often infer `package_name`, but the source of truth is your Gradle `applicationId`.

### Local shell example

```bash
export GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH=./service-account.json

# or
export GOOGLE_PLAY_SERVICE_ACCOUNT_JSON="$(cat service-account.json)"
```

## Related docs

- [Walkthrough](walkthrough.md)
- [Android Quickstart](android-quickstart.md)
- [Configuration Reference](configuration-reference.md)
- [CI Setup](ci-setup.md)
