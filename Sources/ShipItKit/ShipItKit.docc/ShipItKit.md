# ``ShipItKit``

A Swift-native library for automating iOS app release workflows.

## Overview

`ShipItKit` is the reusable core of ShipItSwifty — a Swift-native release toolkit. It provides a composable action model, YAML-based workflow configuration, App Store Connect API integration, and code-signing utilities.

All domain logic lives in `ShipItKit`. The `shipit` CLI is a thin argument-parsing layer on top of it, and any app or CI script can embed `ShipItKit` directly.

### Core Execution Model

```
Shipfile.yml / CLI flags / env vars
        ↓
  ConfigResolver  →  ResolvedConfig
        ↓
  ActionContext (shell, logger, config, AppStoreConnectClient)
        ↓
  ActionRegistry (actor) — maps action names → ActionDescriptors
        ↓
  Workflow.run(context:registry:)  →  executes WorkflowStep[] sequentially
        ↓
  Action.run(with:context:)  →  ActionResultEnvelope
```

### Key Abstractions

| Type | Role |
|---|---|
| ``Action`` | Protocol — one unit of work (`build`, `archive`, `testflight`, …) |
| ``ActionDescriptor`` | Type-erased wrapper produced by `Action.descriptor(for:)` |
| ``ActionRegistry`` | `actor` — serializes registration and lookup by name |
| ``Workflow`` / ``WorkflowStep`` | A named sequence of steps defined in Shipfile YAML |
| ``ActionContext`` | Passed to every `Action.run(...)` — carries shell, logger, config |
| ``ConfigResolver`` | Merges CLI flags → env vars → Shipfile → defaults |

## Topics

### Getting Started

- <doc:GettingStarted>

### Core Concepts

- <doc:CoreConcepts>

### Configuration Reference

- <doc:ConfigurationReference>

### Writing Plugins

- <doc:WritingPlugins>

### Actions

- ``Action``
- ``ActionDescriptor``
- ``ActionContext``
- ``ActionResultEnvelope``

### Registry and Workflows

- ``ActionRegistry``
- ``Workflow``
- ``WorkflowStep``

### Plugin System

- ``ShipItPlugin``
- ``PluginRegistry``

### Configuration

- ``Shipfile``
- ``ResolvedConfig``
- ``ConfigResolver``

### Errors and Utilities

- ``ShipItError``
- ``RetryPolicy``
- ``JSONValue``
- ``JSONReporter``
