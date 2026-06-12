# ShipItSwifty — Security Model

> **DocC mirror:** Security guidance is folded into the `CodeSigningAndVault` article in the `ShipItKit` DocC archive.

## Secrets management

| Secret | Storage |
|---|---|
| **ASC Private Key (`.p8`)** | Env var `ASC_PRIVATE_KEY` in CI; local file path outside version control for dev machines |
| **Vault Passphrase** | Env var `VAULT_PASSWORD` — encrypts/decrypts the cert repo |
| **Slack Webhook URL** | Env var |
| **Keychain Password** | Auto-generated per CI run, stored in memory only |

## Principles

- **Never log secrets** — the logger redacts any value from env vars matching `*KEY*`, `*SECRET*`, `*TOKEN*`, `*PASSWORD*`
- **Temporary keychains** — CI runs create and destroy ephemeral keychains scoped to the process
- **Minimal token scope** — JWT `scope` claim limits API surface per operation
- **Short token lifetime** — default 15-minute JWT lifetime with auto-refresh
- **Encrypted at rest** — cert vault storage uses AES-256-GCM with a key derived from the team passphrase via scrypt (N=2^17, r=8, p=1) and a random per-file salt
- **No telemetry** — ShipItSwifty collects zero usage data

## Threat mitigations

| Threat | Mitigation |
|---|---|
| `.p8` key leakage | CI secrets vault; local `.p8` paths outside version control; never commit key material |
| JWT theft | 15-min expiry; scoped tokens; HTTPS-only |
| Cert repo exposure | AES-256-GCM encryption; scrypt key derivation with per-file salt resists offline brute force of the passphrase |
| `.p8` exposure to other local users | Staged altool key written with `0600` permissions inside a `0700` directory |
| CI log exposure | Automatic secret redaction in all log output |

## Code signing storage (encrypted vault)

Certificates and provisioning profiles are stored encrypted in a shared Git repository. The AES-256 encryption key is derived from the `VAULT_PASSWORD` passphrase with scrypt and a random per-file salt stored in the file header. Only teammates who know the passphrase can decrypt assets.

`shipit sign sync --ci` creates a temporary keychain for the CI process lifetime and removes it on `shipit sign cleanup`.
