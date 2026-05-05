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

## Google Play (Android)

ShipItSwifty uses a Google Cloud service account with Play Console permissions for ``PlayStoreAction`` uploads.

| Value | Where to find it |
|---|---|
| `package_name` | Your Android application ID, usually `applicationId` in `app/build.gradle` or `app/build.gradle.kts` |
| `play_track` | The target Play Console release track: usually `internal`, `alpha`, `beta`, or `production` |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Raw contents of the downloaded service account JSON key |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` | Local filesystem path to that JSON key file |

### Typical setup flow

1. Open `Google Cloud Console`.
2. Create or select a Google Cloud project.
3. Enable the `Google Play Developer API` for that project.
4. Create a service account in the project.
5. Create and download a JSON key for that service account.
6. Open `Google Play Console`.
7. Go to `Users and permissions`.
8. Invite the service account email address as a user.
9. Grant the Play Console permissions needed for your rollout.

### Typical Play Console permissions

- `View app information (read-only)`
- `Release apps to testing tracks` for `internal`, `alpha`, or `beta`
- `Release to production, exclude devices, and use Play App Signing` for production rollout

### Track notes

- Start with `internal` for the simplest first upload.
- Use `production` only when you intend a real store rollout.
- `shipit generate --platform android` can often infer `package_name`, but the source of truth is your Gradle `applicationId`.

## See also

- <doc:GettingStarted>
- <doc:AppStoreConnectIntegration>
- <doc:AndroidAndGooglePlay>
- <doc:ConfigurationReference>
- <doc:CIIntegration>
