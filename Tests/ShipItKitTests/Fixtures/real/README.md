# Real tool output

Artifacts captured from real runs, replayed by `RealFormatTests`. They exist so parsers are checked against
what the tools actually write, not against hand-written approximations.

| Path | Captured from |
|---|---|
| `gradle-test-retry/build/test-results/test/TEST-probe.ProbeTest.xml` | Gradle 9.8.0 + `org.gradle.test-retry` 1.6.6, JUnit Jupiter. Four tests (pass, always-fail, flaky, `@Disabled`) with `maxRetries = 2`. The report holds **one `testcase` per attempt** (seven entries) and its header counts every attempt. Hostname scrubbed. |
| `gradle-test-retry.console.log` | The same run's console. It says `6 tests completed, 3 failed, 1 skipped`: attempts, not tests. |
| `gradle-no-source.console.log` | A Gradle project with no test sources: `> Task :test NO-SOURCE`. |
| `gradle-compile-failure.console.log` | A Gradle build whose test sources do not compile: `> Task :compileTestJava FAILED`. No test ran, so it must never be reported as a failed *test*. |
| `flutter-machine/*.jsonl` | `flutter test --machine` from a real Flutter app (four scripted tests: pass, skip, flaky, always-fails). `first-attempt` fails two, `rerun-by-name` is `--name` selecting two (event IDs renumber), `flaky-only-first-attempt` fails one, `all-passing` passes. They contain what real output contains: non-JSON text before the events (`Resolving dependencies…`), JSON arrays (VM-service events), a hidden `loading <file>` test, `skipped: true` with `result: success`, and `error` events with stack traces. |
| `jest/*.json` | `jest --json` from a real React Native app (the scripted suite plus the app's own: 40 tests). `first-attempt` fails two, `rerun-by-name` is `--runTestsByPath … --testNamePattern …`, where the unselected tests report `pending`. Jest reports absolute paths, scrubbed to `/project/`. |
| `xcresult-clone-failure/` | `xcresulttool get test-results tests/summary --compact` plus the `xcodebuild` log from a run that hit `Failed to clone device named 'iPhone 17'` (exit 65). |
| `xcresult-recovered/` | The same project's serial retry, which passed. Devices include `"platform": "iOS Simulator"`. |

Local paths are scrubbed. To refresh one, re-run the tool and replace the file; the tests state what they expect.
