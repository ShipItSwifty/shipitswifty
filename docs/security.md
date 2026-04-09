# ShipItSwifty — Security Model

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
- **Encrypted at rest** — cert vault storage uses AES-256-GCM
- **No telemetry** — ShipItSwifty collects zero usage data

## Threat mitigations

| Threat | Mitigation |
|---|---|
| `.p8` key leakage | CI secrets vault; local `.p8` paths outside version control; never commit key material |
| JWT theft | 15-min expiry; scoped tokens; HTTPS-only |
| Cert repo exposure | AES-256-GCM encryption with team passphrase |
| CI log exposure | Automatic secret redaction in all log output |

## Code signing storage (encrypted vault)

Certificates and provisioning profiles are stored encrypted in a shared Git repository. The encryption key is the `VAULT_PASSWORD` passphrase. Only teammates who know the passphrase can decrypt assets.

`shipit sign sync --ci` creates a temporary keychain for the CI process lifetime and removes it on `shipit sign cleanup`.
