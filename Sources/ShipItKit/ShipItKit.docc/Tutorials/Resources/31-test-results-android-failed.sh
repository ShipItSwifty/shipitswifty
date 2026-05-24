swift run shipit test-results \
  --platform android \
  --report ./app/build/test-results/testDebugUnitTest \
  --failed-only \
  --report-path ./artifacts/test-results-android.json
