# Workflows

Define reusable, named release pipelines as ordered sequences of actions.

## Overview

A **workflow** is a named, ordered list of action steps declared in `Shipfile.yml` under the top-level `workflows:` key. When you run `shipit run <name>`, ShipItKit:

1. Resolves the merged ``ResolvedConfig``.
2. Looks up each step's action in the ``ActionRegistry``.
3. Decodes the step's `options:` block into the action's `Options` type.
4. Executes steps in order, stopping on the first error (fail-fast).
5. Emits an ``ActionResultEnvelope`` per step, plus a final summary.

## A minimal workflow

```yaml
workflows:
  beta:
    - action: version
      options: { bump: build }
    - action: archive
      options: { export_method: app-store }
    - action: testflight
      options:
        groups: ["Internal QA"]
        changelog: "Bug fixes and stability improvements."
```

Run it:

```bash
shipit run beta
```

## Step shape

Each step is a YAML object with:

| Key | Type | Required | Description |
|---|---|---|---|
| `action` | string | yes | A registered action name (built-in, plugin, or composite). |
| `options` | object | no | Free-form key/value map decoded into the action's typed `Options`. |
| `when` | string | no | Condition gating the step (see *Reserved tokens and conditional steps* below). Reserved tokens are substituted, then the result must be truthy (`true`/`1`/`yes`) for the step to run; otherwise the step is skipped. |

Snake-case YAML keys are decoded to camelCase Swift properties automatically.

## Reserved tokens and conditional steps

A step's string `options` values and its `when` condition may reference reserved tokens that the workflow produces as it runs:

| Token | Resolves to |
|---|---|
| `{{version}}` | The marketing version, from a prior `version` step (or the current versioning source). |
| `{{build_number}}` | The build number. |
| `{{version_changed}}` | `true`/`false` — whether the marketing version changed (`false` for a build-only bump). |

These resolve at run time and are **distinct** from composite `{{param.NAME}}` references (<doc:CompositeActions>) and from Shipfile `${ENV_VAR}` expansion. An unknown or not-yet-resolved token is left literal. Resolution is scoped to top-level workflow steps.

A `when:` string runs after token substitution and gates the step on a single truthy token — there are no operators. A falsy or unresolved condition skips the step (recorded with status `skipped`) and the workflow continues. This is the one exception to strict fail-fast: skips are not failures.

```yaml
workflows:
  release:
    - action: version
      options: { bump: patch }
    - action: git
      when: "{{version_changed}}"          # skipped on build-only bumps
      options: { operation: tag, tag_name: "v{{version}}" }
```

## Execution order and failure semantics

Workflows are **strictly sequential** and **fail-fast**. There is no parallelism between steps, and there is no `try/recover/continue` block — if step *N* throws, steps *N+1…* never run. (A step whose `when:` condition is falsy is *skipped*, not failed; the workflow continues.)

This is intentional: release workflows are mostly write operations against external services (TestFlight, Play, ASC) and recovery semantics are domain-specific. For conditional behaviour use a step `when:` (above), composite actions (<doc:CompositeActions>), or split into multiple workflows.

## Dry-run mode

Preview the resolved step list without executing anything:

```bash
shipit run beta --dry-run
shipit run beta --dry-run --output json | jq '.payload.steps'
```

Dry-run output is structured:

```json
{
  "action": "run",
  "status": "dry_run",
  "payload": {
    "workflow": "beta",
    "mode": "dry_run",
    "stepCount": 3,
    "steps": [
      { "index": 1, "action": "version",    "options": { "bump": "build" } },
      { "index": 2, "action": "archive",    "options": { "export_method": "app-store" } },
      { "index": 3, "action": "testflight", "options": { "groups": ["Internal QA"] } }
    ]
  }
}
```

## Auto-generated project step

Any workflow that contains an Xcode-dependent step (`build`, `test`, `archive`, …) and points at a `project_spec` (XcodeGen / Tuist) automatically runs ``GenerateProjectAction`` first. This is invisible — the only requirement is that the spec file exists and the relevant tool is installed.

## Recommended workflow patterns

### Local-only beta (no upload)

```yaml
workflows:
  local:
    - action: test
    - action: archive
    - action: export
```

No App Store Connect credentials needed. Useful for local "is it working?" checks.

### Beta with TestFlight

```yaml
workflows:
  beta:
    - action: version
      options: { bump: build }
    - action: archive
    - action: export
    - action: testflight
      options:
        groups: ["Internal QA"]
        changelog: "${BETA_NOTES}"
```

`${BETA_NOTES}` expands from the environment at config-resolution time.

### Marketing release (tag the released version)

```yaml
workflows:
  release:
    - action: version
      options: { bump: minor }
    - action: archive
    - action: export
    - action: upload
      options:
        submit_for_review: true
        phased_release: true
    # Commit the bump, then tag the released version and push — no shell glue.
    - action: git
      options: { operation: commit, commit_message: "chore: release v{{version}}" }
    - action: git
      when: "{{version_changed}}"          # skipped on build-only bumps
      options: { operation: tag, tag_name: "v{{version}}" }
    - action: git
      options: { operation: push, push_tags: true }
```

`shipit generate --goal release` scaffolds this tail (commit/tag/push) for you, for both iOS and Android.

### Android beta

```yaml
platform: android

workflows:
  beta:
    - action: lint
    - action: test
    - action: archive            # produces .aab
    - action: play-store
      options:
        track: internal
        rollout_fraction: 1.0
```

### Staging alongside production (workflow-level overrides)

A workflow can be written as an object with a `steps` array plus override groups, instead of a
plain array. Overrides apply only while that workflow runs, so a staging lane can live in the
same Shipfile as production without weakening the top-level production defaults or mutating
them through environment variables.

| Group | Keys | Platform |
|---|---|---|
| `build_variant`, `flavor` | (scalar) | Android |
| `app` | `scheme`, `bundle_id`, `team_id`, `workspace`, `project` | iOS |
| `build` | `configuration`, `derived_data_path`, `xcargs` | iOS |
| `archive` | `export_method`, `output_path`, `include_symbols` | iOS |
| `export` | `archive_path`, `output_directory` | iOS |
| `code_signing` | `type`, `provisioning_profile_path`, storage keys | iOS |

Only the keys you set are overridden; everything else falls through to the top-level
configuration.

```yaml
platform: ios

app:
  scheme: MyApp
  bundle_id: com.example.app
build:
  configuration: Release
archive:
  export_method: app-store

workflows:
  # Production — unchanged, still uses the top-level Release / app-store defaults.
  beta:
    - action: archive
    - action: export
    - action: testflight

  # Staging — same Shipfile, different scheme, configuration, and export method.
  staging:
    app:
      scheme: MyApp-QA
      bundle_id: com.example.app.qa
    build:
      configuration: QA
    archive:
      export_method: ad-hoc
      output_path: ./build/MyApp-QA.xcarchive
    export:
      archive_path: ./build/MyApp-QA.xcarchive
      output_directory: ./build/staging-export
    steps:
      - action: archive
      - action: export
      - action: firebase-app-distribution
        options:
          app_id: ${FIREBASE_IOS_QA_APP_ID}
          artifact_path: ./build/staging-export/MyApp.ipa
          groups:
            - qa-testers
```

The Android equivalent uses `build_variant` in place of the iOS groups:

```yaml
workflows:
  staging:
    build_variant: qaRelease
    steps:
      - action: build
        options: { build_variant: qaRelease, build_type: apk }
      - action: firebase-app-distribution
        options:
          app_id: ${FIREBASE_ANDROID_QA_APP_ID}
          artifact_path: ./app/build/outputs/apk/qa/release/app-qa-release.apk
          groups:
            - qa-testers
```

Keep the distribution channels separated by construction: give the staging workflow no
`testflight` or `play-store` step, and give the production workflows no
`firebase-app-distribution` step.

The action supports either service-account JSON credentials or keyless Workload Identity
Federation. For GitHub Actions, prefer WIF by setting `workload_identity_provider` and
`service_account_email` on the step (or `GOOGLE_WORKLOAD_IDENTITY_PROVIDER` and
`GOOGLE_SERVICE_ACCOUNT_EMAIL` in the environment), granting the repository identity
`roles/iam.workloadIdentityUser`, and enabling OIDC for the job:

```yaml
permissions:
  contents: read
  id-token: write
```

For JSON-key authentication, use `service_account_path`, `FIREBASE_SERVICE_ACCOUNT_JSON`, or
`GOOGLE_APPLICATION_CREDENTIALS`. Never place inline credential JSON in Shipfile.yml. Always
provide `app_id` explicitly; ShipIt does not infer it from local Firebase configuration files.

### Composite step

```yaml
custom_actions:
  build_and_sign:
    description: "Test, archive, export with a chosen method."
    parameters:
      method:
        type: string
        required: true
    steps:
      - action: test
      - action: archive
      - action: export
        options:
          method: "{{param.method}}"

workflows:
  beta:
    - action: build_and_sign
      options: { method: app-store }
    - action: testflight
```

See <doc:CompositeActions> for the full composite contract.

## Programmatic execution

You can run a workflow directly from Swift code, useful for embedding ShipItKit in a server or test harness:

```swift
import ShipItKit

let registry = ActionRegistry()
try await registerBuiltInActions(into: registry)

let workflow = Workflow("beta", steps: [
    WorkflowStep(action: "archive", options: nil),
    WorkflowStep(
        action: "testflight",
        options: .object(["groups": .array([.string("Internal QA")])])
    ),
])

let envelopes = try await workflow.run(context: context, registry: registry)
for env in envelopes { print(env.action, env.status) }
```

## See also

- <doc:CompositeActions>
- <doc:ActionsCatalog>
- <doc:OutputFormats>
- ``Workflow``
- ``WorkflowStep``
- ``ActionRegistry``
