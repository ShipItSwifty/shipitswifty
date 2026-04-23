# Code Signing & Vault

How ShipItKit manages iOS certificates and provisioning profiles — automatic, vault-style, or manual.

## Overview

iOS code signing involves three moving parts: a **certificate** (issued by Apple), a **private key** (stored in your Keychain), and a **provisioning profile** (binds the cert to an App ID, devices, and entitlements). ShipItKit supports three strategies for keeping these in sync across machines:

| `code_signing.type` | Who signs | Best for |
|---|---|---|
| `automatic` | Xcode | Solo dev, simple apps |
| `vault` | ShipItKit pulls from an encrypted, version-controlled store | Teams, CI |
| `manual` | You — ShipItKit just calls `codesign` with what's in Keychain | Custom flows |

## `automatic`

The simplest option. ShipItKit hands signing to Xcode by passing `-allowProvisioningUpdates` to `build`/`archive`/`export`, and exports with `signingStyle: automatic` in the export plist.

```yaml
code_signing:
  type: automatic
```

Requires Xcode to be signed in to your team and the team to have the relevant capabilities.

## `vault`

Vault-style signing keeps your certificates and profiles in an **encrypted, version-controlled store** (Git today; S3/GCS planned). It is the recommended strategy for teams and CI.

```yaml
code_signing:
  type: vault
  storage: git
  git_url: git@github.com:acme/codesign-vault.git
  app_identifier: com.acme.MyApp
  profile_type: appstore   # or adhoc, development, enterprise
```

You also need `VAULT_PASSWORD` in the environment to decrypt the store.

### What `shipit sign` does

```bash
shipit sign sync
```

1. Clones (or pulls) `git_url`.
2. Decrypts the relevant cert and profile with `VAULT_PASSWORD`.
3. Imports the cert into a temporary, isolated Keychain (so CI never touches the user's login Keychain).
4. Installs the profile into `~/Library/MobileDevice/Provisioning Profiles/`.
5. Returns paths and identifiers in the result envelope.

### Provisioning lifecycle

For new devices, missing App IDs, or expired profiles, use ``ProvisionAction``:

```bash
shipit provision --app-identifier com.acme.MyApp --profile-type appstore
```

This drives the App Store Connect REST API directly via ``AppStoreConnectClient`` — no `fastlane match`, no Ruby, no shelling out.

## `manual`

Use this when you're integrating with an existing signing flow and just want ShipItKit to call `codesign` with whatever's already in your Keychain.

```yaml
code_signing:
  type: manual
```

Combine with explicit `xcargs` or environment overrides for fine control:

```yaml
build:
  xcargs:
    CODE_SIGN_IDENTITY: "Apple Distribution: Acme Inc. (TEAMID)"
    PROVISIONING_PROFILE_SPECIFIER: "Acme MyApp Distribution"
```

## Security model

- Cert/profile content is **never logged** at any verbosity level.
- Vault decryption happens in memory — the plaintext is never written to disk except as the imported `.p12` / `.mobileprovision` file in a process-scoped Keychain.
- On CI, the temporary Keychain is destroyed at the end of the run.
- `VAULT_PASSWORD` must be supplied via env var; ShipItKit refuses to read it from a Shipfile field.

## Related types

- ``SignAction`` — top-level CLI/Swift entry point.
- ``ProvisionAction`` — device/App ID/profile lifecycle.
- ``ProfileManager`` — reads and parses provisioning profiles.
- ``CertificateManager`` — Keychain interaction.
- ``ProvisioningProfileInfo`` — typed view of a `.mobileprovision`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `signingResourceNotFound: certificate` | Cert missing from vault | Run `shipit provision --recreate-certificate` |
| `signingResourceNotFound: profile` | Profile missing or expired | `shipit provision --profile-type appstore` |
| `keychainError` on CI | Login Keychain locked | Use `vault` mode (creates a temp Keychain) |
| `archiveFailed`: "no profile matches" | Wrong `profile_type` | Match `profile_type` to your `export_method` |

## See also

- ``SignAction``
- ``ProvisionAction``
- <doc:AppStoreConnectIntegration>
- <doc:CIIntegration>
