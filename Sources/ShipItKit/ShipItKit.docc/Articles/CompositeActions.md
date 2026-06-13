# Composite Actions

Define reusable, parameterised step sequences in `Shipfile.yml` and call them like built-in actions.

## Overview

A **composite action** is a named, parameterised sequence of action steps declared under `custom_actions:`. Once registered, it is callable from any workflow exactly as if it were a built-in:

```yaml
custom_actions:
  build_and_sign:
    description: "Test, archive, and export with a chosen export method."
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
  adhoc:
    - action: build_and_sign
      options: { method: ad-hoc }
```

Composite actions live entirely in YAML — no Swift code required. They are first-class members of the ``ActionRegistry`` and resolve recursively: composites can call other composites (cycles are rejected at validation time).

## Parameter substitution

Composite step `options:` values may reference declared parameters using `{{param.NAME}}`. This delimiter is deliberately chosen to avoid collisions:

| Syntax | Used by | Conflict? |
|---|---|---|
| `{{param.X}}` | ShipItKit composites | — |
| `${ENV_VAR}` | Shipfile env expansion (runs first) | No — different delimiters; you can mix |
| `${{ env.X }}` | GitHub Actions | No |
| `<< parameters.X >>` | CircleCI | No |
| `$VAR` / `${VAR}` | Xcode Cloud, shell | No |

> `{{param.NAME}}` is for **composite call-site parameters**. Top-level workflow steps have a separate set of reserved tokens produced at run time — `{{version}}`, `{{build_number}}`, `{{version_changed}}` — plus a `when:` condition. See <doc:Workflows>.

### Substitution rules

- When a string is **exactly** `{{param.NAME}}`, the typed JSON value of the parameter is substituted (preserving `bool`, `int`, `array`, `object`).
- When a string **contains** `{{param.NAME}}` interpolated with other text, the parameter is stringified into the surrounding string.
- Substitution runs **after** Shipfile's `${ENV_VAR}` expansion, so you can compose them: `"{{param.track}}-${DEPLOY_ENV}"`.

### Example: typed substitution

```yaml
custom_actions:
  notify_release:
    parameters:
      channels:
        type: array
        required: true
      include_changelog:
        type: bool
        default: true
    steps:
      - action: notify
        options:
          slack:
            channels: "{{param.channels}}"        # array passed through as array
            include_changelog: "{{param.include_changelog}}"  # bool stays bool
```

## Validation

`shipit validate yml` enforces:

1. Custom action names must not collide with **built-in** action names.
2. Each step's `action:` must resolve to a built-in or another composite.
3. Every `{{param.NAME}}` reference must match a declared parameter.
4. Required parameters (no `default:`) must be supplied at every call site.
5. Composite-to-composite references must be **acyclic**. The error message names the cycle:
   `Custom action cycle detected: foo -> bar -> foo.`

## Parameter declaration

```yaml
custom_actions:
  example:
    description: "Optional human-readable description."
    parameters:
      name:
        type: string
        required: true
      count:
        type: int
        default: 3
      verbose:
        type: bool
        default: false
      tags:
        type: array
        default: []
    steps:
      - action: build
```

Supported `type:` values: `string`, `int`, `bool`, `array`, `object`.

If `default:` is omitted, `required: true` is implied. Calling the composite without supplying the parameter throws ``CompositeAction/CompositeError/missingRequiredParameter(compositeName:parameter:)``.

## How it works

At Shipfile load time, ``ActionRegistry/registerCustomActions(_:)`` does three static checks (name collisions, name-resolution, cycle detection) and then converts each ``CustomActionConfig`` into an ``ActionDescriptor`` via ``CompositeAction/descriptor(name:config:registry:)``.

When invoked at runtime, the descriptor:

1. Decodes the call-site `options:` into the composite's parameter map.
2. Validates required parameters are present.
3. For each step, recursively substitutes `{{param.NAME}}` into the step's options.
4. Looks up the step's action in the same ``ActionRegistry``.
5. Invokes the action with the substituted options.

A composite returns a single ``ActionResultEnvelope`` whose payload is an array of the sub-step envelopes — making composites observable in JSON output exactly like workflows.

## Composites in `ai-session`

`shipit ai-session` enumerates the user's declared composites in the generated `agentPrompt`. This nudges AI agents to **prefer reusing an existing composite** over duplicating its step sequence in a new workflow.

## When to use a composite vs. a workflow

| Use a composite when… | Use a workflow when… |
|---|---|
| You want to reuse a sub-pipeline across multiple lanes | You want a single user-facing entry point (`shipit run release`) |
| You want call-site parameterisation (`{{param.method}}`) | The pipeline is "complete" and not reused |
| You want recursion (composite calling composite) | You don't need to reuse it |

## See also

- <doc:Workflows>
- ``CompositeAction``
- ``CustomActionConfig``
- ``ActionRegistry/registerCustomActions(_:)``
