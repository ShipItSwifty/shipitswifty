import Foundation

func makeFakeFlutterEnvironment(in project: URL) throws -> [String: String] {
    let toolsDirectory = try makeToolsDirectory(in: project)
    try writeExecutable(
        named: "flutter",
        contents: fakeFlutterScript,
        in: toolsDirectory
    )
    return pathEnvironment(prepending: toolsDirectory)
}

func makeFakeReactNativeEnvironment(in project: URL) throws -> [String: String] {
    let toolsDirectory = try makeToolsDirectory(in: project)
    try writeExecutable(
        named: "npx",
        contents: fakeNpxScript,
        in: toolsDirectory
    )
    try writeExecutable(
        named: "xcodebuild",
        contents: fakeXcodebuildScript,
        in: toolsDirectory
    )
    try writeExecutable(
        named: "bundletool",
        contents: fakeBundletoolScript,
        in: toolsDirectory
    )
    return pathEnvironment(prepending: toolsDirectory)
}

func makeFakeKMPEnvironment(in project: URL) throws -> [String: String] {
    let toolsDirectory = try makeToolsDirectory(in: project)
    try writeExecutable(
        named: "xcodebuild",
        contents: fakeXcodebuildScript,
        in: toolsDirectory
    )
    try writeExecutable(
        named: "bundletool",
        contents: fakeBundletoolScript,
        in: toolsDirectory
    )
    try writeExecutable(
        named: "gradlew",
        contents: fakeKMPGradlewScript,
        in: project
    )
    return pathEnvironment(prepending: toolsDirectory)
}

private func makeToolsDirectory(in project: URL) throws -> URL {
    let toolsDirectory = project.appendingPathComponent(".shipit-tools")
    try FileManager.default.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
    return toolsDirectory
}

private func writeExecutable(
    named name: String,
    contents: String,
    in directory: URL
) throws {
    let url = directory.appendingPathComponent(name)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private func pathEnvironment(prepending directory: URL) -> [String: String] {
    let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
    return ["PATH": "\(directory.path):\(existingPath)"]
}

private let fakeFlutterScript = """
#!/bin/sh
set -eu

write_zip() {
  path="$1"
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  dd if=/dev/urandom of="$tmpdir/payload.txt" bs=2048 count=1 2>/dev/null
  (
    cd "$tmpdir"
    /usr/bin/zip -q "$path" payload.txt
  )
  rm -rf "$tmpdir"
  trap - EXIT
}

if [ "${1:-}" = "test" ]; then
  printf '00:01 +3: All tests passed!\n'
  exit 0
fi

if [ "${1:-}" = "analyze" ]; then
  printf 'No issues found!\n'
  exit 0
fi

if [ "${1:-}" = "build" ] && [ "${2:-}" = "ios" ]; then
  saw_no_codesign=0
  for arg in "$@"; do
    if [ "$arg" = "--no-codesign" ]; then
      saw_no_codesign=1
    fi
  done
  if [ "$saw_no_codesign" -ne 1 ]; then
    printf 'flutter build ios missing --no-codesign\n' >&2
    exit 1
  fi
  mkdir -p build/ios/iphoneos
  printf 'Built build/ios/iphoneos/Runner.app\n'
  exit 0
fi

if [ "${1:-}" = "build" ] && [ "${2:-}" = "ipa" ]; then
  mkdir -p build/ios/ipa
  write_zip "$PWD/build/ios/ipa/Runner.ipa"
  printf 'Built build/ios/ipa/Runner.ipa\n'
  exit 0
fi

if [ "${1:-}" = "build" ] && [ "${2:-}" = "apk" ]; then
  mkdir -p build/app/outputs/flutter-apk
  write_zip "$PWD/build/app/outputs/flutter-apk/app-release.apk"
  printf 'Built build/app/outputs/flutter-apk/app-release.apk\n'
  exit 0
fi

if [ "${1:-}" = "build" ] && [ "${2:-}" = "appbundle" ]; then
  mkdir -p build/app/outputs/bundle/release
  write_zip "$PWD/build/app/outputs/bundle/release/app-release.aab"
  printf 'Built build/app/outputs/bundle/release/app-release.aab\n'
  exit 0
fi

printf 'Unexpected flutter command: %s\n' "$*" >&2
exit 1
"""

private let fakeNpxScript = """
#!/bin/sh
set -eu

write_zip() {
  path="$1"
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  dd if=/dev/urandom of="$tmpdir/payload.txt" bs=2048 count=1 2>/dev/null
  (
    cd "$tmpdir"
    /usr/bin/zip -q "$path" payload.txt
  )
  rm -rf "$tmpdir"
  trap - EXIT
}

if [ "${1:-}" != "react-native" ]; then
  printf 'Unexpected npx invocation: %s\n' "$*" >&2
  exit 1
fi

shift

if [ "${1:-}" = "build-ios" ]; then
  shift
  saw_release=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --mode)
        if [ "${2:-}" = "Release" ]; then
          saw_release=1
        fi
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  if [ "$saw_release" -ne 1 ]; then
    printf 'react-native build-ios missing Release mode\n' >&2
    exit 1
  fi
  printf 'Build Succeeded\n'
  exit 0
fi

if [ "${1:-}" = "build-android" ]; then
  shift
  saw_release=0
  saw_bundle=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --mode=release)
        saw_release=1
        shift
        ;;
      --tasks)
        if [ "${2:-}" = "bundleRelease" ]; then
          saw_bundle=1
          shift 2
        else
          printf 'Unexpected React Native bundle task: %s\n' "${2:-}" >&2
          exit 1
        fi
        ;;
      *)
        shift
        ;;
    esac
  done

  if [ "$saw_release" -ne 1 ]; then
    printf 'react-native build-android missing release mode\n' >&2
    exit 1
  fi

  if [ "$saw_bundle" -eq 1 ]; then
    mkdir -p android/app/build/outputs/bundle/release
    write_zip "$PWD/android/app/build/outputs/bundle/release/app-release.aab"
    printf 'BUILD SUCCESSFUL\n'
    exit 0
  fi

  mkdir -p android/app/build/outputs/apk/release
  write_zip "$PWD/android/app/build/outputs/apk/release/app-release.apk"
  printf 'BUILD SUCCESSFUL\n'
  exit 0
fi

printf 'Unexpected react-native command: %s\n' "$*" >&2
exit 1
"""

private let fakeXcodebuildScript = """
#!/bin/sh
set -eu

archive_path=""
saw_build=0
saw_test=0
saw_export=0
saw_archive=0
export_path=""

while [ $# -gt 0 ]; do
  case "$1" in
    -archivePath)
      archive_path="${2:-}"
      shift 2
      ;;
    -exportPath)
      export_path="${2:-}"
      shift 2
      ;;
    -exportArchive)
      saw_export=1
      shift
      ;;
    build)
      saw_build=1
      shift
      ;;
    test)
      saw_test=1
      shift
      ;;
    archive)
      saw_archive=1
      shift
      ;;
    *)
      shift
      ;;
  esac
done

write_info_plist() {
  cat > "$1" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.shipitswifty.integration</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleIcons</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconFiles</key>
      <array>
        <string>AppIcon</string>
      </array>
    </dict>
  </dict>
  <key>UIRequiresFullScreen</key>
  <true/>
  <key>UIApplicationSceneManifest</key>
  <dict/>
</dict>
</plist>
EOF
}

write_zip() {
  path="$1"
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  dd if=/dev/urandom of="$tmpdir/payload.txt" bs=2048 count=1 2>/dev/null
  (
    cd "$tmpdir"
    /usr/bin/zip -q "$path" payload.txt
  )
  rm -rf "$tmpdir"
  trap - EXIT
}

if [ "$saw_export" -eq 1 ]; then
  if [ -z "$export_path" ]; then
    printf 'Missing -exportPath\n' >&2
    exit 1
  fi
  mkdir -p "$export_path"
  write_zip "$export_path/HelloWorld.ipa"
  printf 'EXPORT SUCCEEDED\n'
  exit 0
fi

if [ "$saw_build" -eq 1 ]; then
  printf '** BUILD SUCCEEDED **\n'
  exit 0
fi

if [ "$saw_test" -eq 1 ]; then
  printf 'Test Suite KMPWrapperTests started\n'
  printf 'Test Case -[KMPWrapperTests testSmoke] passed\n'
  printf '** TEST SUCCEEDED **\n'
  exit 0
fi

if [ "$saw_archive" -ne 1 ]; then
  printf 'Unexpected xcodebuild invocation\n' >&2
  exit 1
fi

if [ -z "$archive_path" ]; then
  printf 'Missing -archivePath\n' >&2
  exit 1
fi

app_bundle="$archive_path/Products/Applications/HelloWorld.app"
mkdir -p "$app_bundle"
write_info_plist "$archive_path/Info.plist"
write_info_plist "$app_bundle/Info.plist"
printf '** ARCHIVE SUCCEEDED **\n'
"""

private let fakeBundletoolScript = """
#!/bin/sh
set -eu

if [ "${1:-}" = "validate" ]; then
  exit 0
fi

if [ "${1:-}" = "version" ]; then
  printf '1.0.0\n'
  exit 0
fi

printf 'Unexpected bundletool invocation: %s\n' "$*" >&2
exit 1
"""

private let fakeKMPGradlewScript = """
#!/bin/sh
set -eu

write_zip() {
  path="$1"
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  dd if=/dev/urandom of="$tmpdir/payload.txt" bs=2048 count=1 2>/dev/null
  (
    cd "$tmpdir"
    /usr/bin/zip -q "$path" payload.txt
  )
  rm -rf "$tmpdir"
  trap - EXIT
}

for arg in "$@"; do
  case "$arg" in
    *linkDebugFrameworkIosSimulatorArm64|*linkReleaseFrameworkIosSimulatorArm64)
      mkdir -p shared/build/bin/iosSimulatorArm64/debugFramework
      printf 'Linked shared/build/bin/iosSimulatorArm64/debugFramework/Shared.framework\n'
      printf 'BUILD SUCCESSFUL\n'
      exit 0
      ;;
    *linkReleaseFrameworkIosArm64)
      mkdir -p shared/build/bin/iosArm64/releaseFramework
      printf 'Linked shared/build/bin/iosArm64/releaseFramework/Shared.framework\n'
      printf 'BUILD SUCCESSFUL\n'
      exit 0
      ;;
    *assembleRelease)
      mkdir -p androidApp/build/outputs/apk/release
      write_zip "$PWD/androidApp/build/outputs/apk/release/androidApp-release.apk"
      printf 'androidApp/build/outputs/apk/release/androidApp-release.apk\n'
      printf 'BUILD SUCCESSFUL\n'
      exit 0
      ;;
    *bundleRelease)
      mkdir -p androidApp/build/outputs/bundle/release
      write_zip "$PWD/androidApp/build/outputs/bundle/release/androidApp-release.aab"
      printf 'androidApp/build/outputs/bundle/release/androidApp-release.aab\n'
      printf 'BUILD SUCCESSFUL\n'
      exit 0
      ;;
    *iosSimulatorArm64Test)
      printf '4 tests completed, 0 failed, 0 skipped\n'
      exit 0
      ;;
    *testDebugUnitTest|*testReleaseUnitTest)
      printf '6 tests completed, 0 failed, 0 skipped\n'
      exit 0
      ;;
  esac
done

printf 'Unexpected KMP gradlew command: %s\n' "$*" >&2
exit 1
"""
