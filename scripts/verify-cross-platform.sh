#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

cd "$repo_root"

echo "== swift build =="
swift build

echo "== fixture integration: Flutter =="
swift test --filter FlutterFixtureIntegrationTests

echo "== fixture integration: React Native =="
swift test --filter ReactNativeFixtureIntegrationTests

echo "== fixture integration: KMP =="
swift test --filter KMPFixtureIntegrationTests

echo "== native integration artifacts =="
swift test --filter BuildIntegrationTests
swift test --filter AndroidIntegrationTests

echo "== full integration sweep =="
swift test --filter IntegrationTests

echo "Cross-platform verification complete."
