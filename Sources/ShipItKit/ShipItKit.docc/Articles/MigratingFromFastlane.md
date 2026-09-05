# Migrating From fastlane

A practical guide to porting a Ruby `Fastfile` to a Swift-native `Shipfile.yml`.

## Overview

ShipItSwifty is a direct, opinionated replacement for fastlane. The mapping is mostly mechanical: each lane becomes a workflow, each tool (`gym`, `pilot`, `match`, `deliver`) maps to a built-in action. The big wins:

- **No Ruby toolchain.** A single Swift binary with no gem-version drift.
- **Type safety.** Action options are `Codable` Swift types validated at load time.
- **Structured output.** Every command can emit JSON for CI and AI agents.
- **First-class Android.** Same Shipfile, same workflows, same JSON envelope.

## Concept mapping

| fastlane | ShipItSwifty |
|---|---|
| `Appfile` | `app:` + `app_store_connect:` in `Shipfile.yml` |
| `Fastfile` lane | `workflows:` entry |
| Lane parameters / env vars | Workflow `options:` + `SHIPIT_*` env vars |
| `match` | `shipit sign sync` (vault-style code signing) |
| `gym` | `shipit archive` + `shipit export` |
| `scan` | `shipit test` |
| `pilot` | `shipit testflight` |
| `deliver` | `shipit metadata` and `shipit upload` |
| `precheck` | `shipit validate metadata` (alias: `shipit precheck`) |
| `screengrab` / `snapshot` | `shipit snapshot` |
| `frameit` | `shipit frame` |
| `increment_build_number` / `increment_version_number` | `shipit version` |
| `supply` | `shipit play-store` |
| `add_git_tag` / `push_to_git_remote` | `git` workflow steps (`operation: tag` / `commit` / `push`), tagging with the `{{version}}` token |

## Step 1: move app identity into the Shipfile

```yaml
app:
  workspace: MyApp.xcworkspace
  scheme: MyApp
  bundle_id: com.example.myapp
  team_id: ABCDE12345

app_store_connect:
  key_id: ${ASC_KEY_ID}
  issuer_id: ${ASC_ISSUER_ID}
  key_path: ./.secrets/AuthKey_XXXXXXXXXX.p8
```

## Step 2: convert each lane

A typical fastlane beta lane:

```ruby
lane :beta do
  increment_build_number
  build_app
  upload_to_testflight(groups: ["Internal QA"])
end
```

Becomes:

```yaml
workflows:
  beta:
    - action: version
      options: { bump: build }
    - action: archive
      options: { configuration: Release, export_method: app-store }
    - action: export
    - action: testflight
      options:
        groups: ["Internal QA"]
```

A release lane that also tags the release:

```ruby
lane :release do
  capture_screenshots
  build_app
  upload_to_app_store(submit_for_review: true)
  increment_version_number(bump_type: "patch")
  commit_version_bump
  add_git_tag(tag: "v#{lane_context[SharedValues::VERSION_NUMBER]}")
  push_to_git_remote
end
```

Becomes:

```yaml
workflows:
  release:
    - action: snapshot
    - action: archive
    - action: export
    - action: upload
      options:
        submit_for_review: true
        phased_release: true
    - action: version
      options: { bump: patch }
    # fastlane's add_git_tag with the bumped version becomes the {{version}} token —
    # no lane_context plumbing. The tag is skipped on build-only bumps.
    - action: git
      options: { operation: commit, commit_message: "chore: release v{{version}}" }
    - action: git
      when: "{{version_changed}}"
      options: { operation: tag, tag_name: "v{{version}}" }
    - action: git
      options: { operation: push, push_tags: true }
```

## Step 3: move secrets to environment variables

```bash
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_PRIVATE_KEY="$(cat ./.secrets/AuthKey_XXXXXXXXXX.p8)"
export VAULT_PASSWORD=…    # only if you use code_signing.type: vault
```

ShipItKit refuses to read secrets like `VAULT_PASSWORD` from a Shipfile field — they must come from the environment.

## Step 4: replace lane invocations

| Before | After |
|---|---|
| `fastlane beta` | `shipit run beta` |
| `fastlane test` | `shipit test` |
| `fastlane match appstore` | `shipit sign sync --profile-type appstore` |
| `fastlane deliver` | `shipit metadata && shipit upload` |
| `fastlane snapshot` | `shipit snapshot` |
| `fastlane supply --track beta` | `shipit play-store --track beta` |

## Step 5: migrate `match`

`match` and `shipit sign` are conceptually identical: an encrypted, version-controlled store of certificates and profiles. The Shipfile equivalent:

```yaml
code_signing:
  type: vault
  storage: git
  git_url: git@github.com:acme/codesign-vault.git
  app_identifier: com.acme.MyApp
  profile_type: appstore
```

Then:

```bash
export VAULT_PASSWORD=…
shipit sign sync
```

See <doc:CodeSigningAndVault> for the full vault model and security guarantees.

## Step 6: validate before going live

```bash
shipit env                          # human: verify resolved config
shipit validate yml                 # static checks
shipit run beta --dry-run --output json   # see the planned step list

# AI/CI-friendly
shipit ai session --goal beta
```

## Migration advice

- **Migrate one lane at a time.** Beta/TestFlight first, release second.
- **Keep workflows small.** ShipItSwifty favours separate `archive`, `export`, `testflight` steps over one fused command.
- **Migrate signing separately.** Verify `shipit sign sync` works before wiring it into a full release workflow.
- **Watch for environment overlap.** Some env vars (`FASTLANE_USER`, `MATCH_PASSWORD`) won't migrate; rename them to ShipItSwifty equivalents (`ASC_*`, `VAULT_PASSWORD`).
- **Use `--dry-run`.** Before deleting your `Fastfile`, run every workflow with `--dry-run --output json` and diff the planned steps against your old lane.

## Things ShipItSwifty does that fastlane doesn't

- **AI session**: `shipit ai session --goal beta` returns a stable JSON contract designed for agents (see <doc:AISession>).
- **Composite actions in YAML**: parameterised reusable step sequences without writing Swift (see <doc:CompositeActions>).
- **Strict typed config**: invalid Shipfile keys fail at load time, not at runtime.
- **One binary for both platforms**: same workflow, just toggle `platform: android`.

## See also

- <doc:Workflows>
- <doc:CodeSigningAndVault>
- <doc:AppStoreConnectIntegration>
- <doc:AndroidAndGooglePlay>
- <doc:CIIntegration>
