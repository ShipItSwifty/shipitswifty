# Real tool output

Artifacts captured from real runs, replayed by `RealFormatTests`. They exist so parsers are checked against
what the tools actually write, not against hand-written approximations.

| Path | Captured from |
|---|---|
| `gradle-test-retry/build/test-results/test/TEST-probe.ProbeTest.xml` | Gradle 9.8.0 + `org.gradle.test-retry` 1.6.6, JUnit Jupiter. Four tests (pass, always-fail, flaky, `@Disabled`) with `maxRetries = 2`. The report holds **one `testcase` per attempt** (seven entries) and its header counts every attempt. Hostname scrubbed. |
| `gradle-test-retry.console.log` | The same run's console. It says `6 tests completed, 3 failed, 1 skipped`: attempts, not tests. |
| `gradle-no-source.console.log` | A Gradle project with no test sources: `> Task :test NO-SOURCE`. |
| `xcresult-clone-failure/` | `xcresulttool get test-results tests/summary --compact` plus the `xcodebuild` log from a run that hit `Failed to clone device named 'iPhone 17'` (exit 65). |
| `xcresult-recovered/` | The same project's serial retry, which passed. Devices include `"platform": "iOS Simulator"`. |

Local paths are scrubbed. To refresh one, re-run the tool and replace the file; the tests state what they expect.
