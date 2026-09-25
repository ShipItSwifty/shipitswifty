---
name: add-action
description: Add a new ShipItKit Action or change an existing action's Options/Result in ShipItSwifty, keeping the schema catalog, docs, AI-session guidance, CLI, and tests in sync. Use for any change under Sources/ShipItKit/Actions/ that adds, removes, or renames an option, result field, or action.
---

# Add or change a ShipItKit action

`shipit schema` and `shipit ai session` are generated from code that is **not** derived from the
action's `Options` type, so an action change is incomplete until every surface below agrees.

## 1. Implement

- One action per file: `Sources/ShipItKit/Actions/<Name>.swift`, conforming to `Action`.
- `Options: Codable & Sendable` with snake_case `CodingKeys` matching Shipfile keys; every field
  optional unless truly required, with defaults resolved from `context.config` inside `run`.
- `Result: Codable & Sendable`.
- Behaviour comes only from `Options` and `ActionContext` — no globals, no `ProcessInfo` reads in
  the action (resolve environment in `ConfigResolver`).
- Shell work goes through SwiftyShell via the tool wrappers (`context.gradle()`,
  `XcodeBuild(context:)`, `Adb(context:)`, …). If a flag or subcommand is missing, add it to the
  wrapper first (see the `tool-wrapper` skill) instead of hand-building strings.
- ASC calls go through `AppStoreConnectClient`; wrap with `mappingASCErrors { }`. Google Play
  calls wrap with `mappingGoogleErrors { }`.
- DocC comment on the action with a `## Usage` section.

## 2. Register and expose

- Register it in `builtInActionDescriptors()` (`Sources/CLI/Commands/RunCommand.swift`) with
  `optionSchema: BuiltInSchemaCatalog.optionSchema(for: <Name>.name)` and, if it has cross-field
  rules, `validationRules:` (see `Sources/ShipItKit/Actions/ActionValidationRules.swift`).
  Unregistered actions are invisible to `shipit run` workflows and `shipit validate yml`.
- Add the Shipfile schema entry in `Sources/ShipItKit/Config/Shipfile.swift`.
- CLI: `Sources/CLI/Commands/<Name>Command.swift` (one command per file) if it is user-invocable.

## 3. Sync every contract surface (same change)

| Surface | What to update |
|---|---|
| `Sources/ShipItKit/Introspection/BuiltInSchemaCatalog.swift` | The action's `actionSchemas()` entry and its `*Options()` helper — every option, with description, default, and example |
| `Sources/ShipItKit/Introspection/AISessionBuilder.swift` | `buildAgentPrompt` / `buildNextAction` / `buildNextQuestion` if agents should use or configure it |
| Generated workflows | `ShipfileSuggester` and `GenerateCommand` if `shipit generate` should emit it |
| `docs/features.md` | Feature table row(s) |
| `docs/configuration-reference.md` | Option table if it is Shipfile-configurable |
| `AGENTS.md` | Commands section for new/renamed CLI surface; agent workflow guidance |
| `docs/architecture.md` | Exit-code table if you add or change a `ShipItError` case (also `CLIHelpers.errorSuggestions`) |

## 4. Test

- `Tests/ShipItKitTests/<Name>ActionTests.swift` with Swift Testing (`@Test`, `#expect`, `#require`).
- Use `makeCaptureExecutor` + `makeTestActionContext` from `Tests/ShipItKitTests/TestSupport.swift`
  and assert the exact commands issued.
- Mock realistic exit codes (a failing `gradlew` exits 1, `xcodebuild` 65), not exit 0 plus failure text.
- Keep Android / config / parsing tests outside `#if os(macOS)` so the Linux CI job runs them.
- Add a schema test if the catalog entry has non-trivial structure (see `IntrospectionTests`).

## 5. Verify

```bash
swift build
swift test --filter ShipItKitTests
swift test --filter CLITests
```

On Linux without a toolchain, use the `verify-linux` skill. Report explicitly which parts
(macOS-only code paths) were not compiled or run.
