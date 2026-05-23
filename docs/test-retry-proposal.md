# Infrastructure Retry — Cross-Platform Design

## Context

`shipit test` already supports platform-native retry mechanisms:
- **iOS**: Xcode's `-retry-tests-on-failure` via `retry_on_failure: true`
- **Android**: Gradle's `--rerun-tasks` (manual)
- **Flutter/RN**: No built-in retry

These help when an individual test case flakes, but they do **not** cover infrastructure
failures that happen before tests begin executing:

- **iOS**: Simulator boot instability, `xctrunner` launch failures, `FBSOpenApplicationServiceErrorDomain`, CoreSimulator database locks
- **Android**: Emulator disconnects, ADB server crashes, device-offline during instrumented tests, Gradle daemon disappearances
- **Flutter**: Flutter tool crashes, pub cache corruption, VM service connection drops
- **React Native**: Jest worker OOM kills, Metro bundler crashes, ENOSPC/EMFILE system limits
- **KMP**: Konan compiler daemon timeouts, simulator failures via Gradle

## Industry Alignment

| Standard | Implementation |
|----------|---------------|
| Bazel `flaky_test_attempts` | Retry in tooling layer, not ad hoc per workflow |
| Fastlane `number_of_retries` | Configurable per-action retry count |
| CircleCI "Rerun failed tests" | Separate infra failures from test failures |
| gRPC/AWS SDK retry | Exponential backoff with jitter, max delay cap |
| GitHub Actions | Step-level retry via `continue-on-error` + matrix |

## Architecture

```
┌─────────────────────────────────────────────────────┐
│              InfrastructureRetryScheduler            │
│  ┌─────────┐  ┌─────────────────────────────────┐   │
│  │ Options │  │ InfrastructureFailureClassifier  │   │
│  │ (config)│  │        (protocol)                │   │
│  └─────────┘  └─────────────────────────────────┘   │
└───────────────────────────┬─────────────────────────┘
                            │
        ┌───────────┬───────┼───────┬───────────┐
        │           │       │       │           │
   ┌────┴────┐ ┌────┴────┐ ┌┴──────┐ ┌────┴────┐ ┌────┴────┐
   │  iOS    │ │ Android │ │Flutter│ │   RN    │ │   KMP   │
   │Classify.│ │Classify.│ │Class. │ │Classify.│ │Classify.│
   └─────────┘ └─────────┘ └───────┘ └─────────┘ └─────────┘
```

### Key Types

- **`InfrastructureFailureClassifier`** (protocol): `platformName` + `isRetryable(log:)`
- **`InfrastructureRetryScheduler`**: Generic retry wrapper with exponential backoff + jitter
- **`InfrastructureRetryScheduler.Options`**: Shared config struct (replaces old iOS-only options)

### Classifiers

Each classifier defines:
1. **Retryable patterns** — known transient infrastructure failure strings
2. **Non-retryable patterns** — real build/test failures that must never be retried (takes priority)

| Classifier | Retryable examples | Non-retryable examples |
|------------|-------------------|------------------------|
| `IOSInfrastructureClassifier` | `simulator device failed to launch`, `database is locked`, `failed to launch xctrunner` | `compile error`, `no signing certificate`, `unable to find a destination` |
| `AndroidInfrastructureClassifier` | `device offline`, `gradle daemon disappeared`, `adb connection reset` | `compilation failed`, `could not resolve`, `execution failed for task` |
| `FlutterInfrastructureClassifier` | `flutter tool crashed`, `pub get failed`, `vm service connection closed` | `compiler error`, `analysis issue` |
| `ReactNativeInfrastructureClassifier` | `javascript heap out of memory`, `jest worker encountered`, `metro bundler process exited` | `syntaxerror`, `referenceerror`, `cannot find module` |
| `KMPInfrastructureClassifier` | `konan compiler daemon not responding` + delegates to iOS + Android classifiers | `unresolved reference`, `type mismatch` |

## Configuration

Single unified config block in Shipfile, works for all platforms:

```yaml
test:
  retry_on_failure: true          # Platform-native flaky test retry (iOS only today)
  infrastructure_retry:           # Presence of this block enables retries; omit to disable
    max_attempts: 3                # Total attempts including first try
    initial_delay_seconds: 2       # Delay before first retry
    max_delay_seconds: 60          # Backoff cap
```

### Options Struct

```swift
public typealias InfrastructureRetryOptions = InfrastructureRetryScheduler.Options

// In InfrastructureRetryScheduler:
public struct Options: Codable, Sendable, Equatable {
    public var maxAttempts: Int?            // default: 3
    public var initialDelaySeconds: Double? // default: 2.0
    public var maxDelaySeconds: Double?     // default: 60.0
}
```

## Execution Semantics

For each platform test runner:

1. Build the test command as normal.
2. Wrap execution in `InfrastructureRetryScheduler.execute(label:operation:extractContext:)`.
3. If the operation succeeds, return results.
4. If it fails:
   - `extractContext` pulls the combined log from the error.
   - The scheduler passes the log to the platform's classifier.
   - If classified as infrastructure failure and attempts remain:
     - Wait with exponential backoff + ±25% jitter.
     - Re-execute the operation.
   - Otherwise, throw the original error.

### Backoff Strategy

- **Exponential**: Each retry doubles the previous delay.
- **Jitter**: ±25% randomization to decorrelate parallel retries.
- **Cap**: `max_delay_seconds` prevents unbounded waits (default 60s).
- Formula: `delay_n = min(initial * 2^(n-1) * random(0.75, 1.25), max_delay)`

### Scope

- iOS: per-destination (each simulator destination retries independently)
- Android: per-task (entire Gradle task retries)
- Flutter/RN/KMP: per-invocation

## Non-Goals

- Do not retry all action types (only `test`).
- Do not add simulator reset/erase side effects.
- Do not attempt perfect classification of every error.
- Retries are opt-in: the user must add the `infrastructure_retry:` block to enable them.

## Testing

Unit tests cover:
- iOS classifier matches xctrunner launch errors, rejects assertion failures
- Android classifier matches emulator disconnects, rejects compilation failures
- Flutter classifier matches tool crashes, rejects analysis errors
- ReactNative classifier matches worker failures, rejects syntax errors
- Scheduler backoff doubles correctly and respects cap
- Scheduler jitter stays within 75%-125% bounds
- End-to-end: iOS retry recovers after infrastructure failure on second attempt
- End-to-end: Normal test failure is not retried

## Rollout Strategy

1. Ship as opt-in (block must be present to enable).
2. Recommend for CI/beta workflows with UITests or instrumented Android tests.
3. Collect field data on retry rates and false-positive/negative classification.
4. Consider default-on for CI environments once field experience is positive.
5. Future: Add structured telemetry for retry counts per-platform.
