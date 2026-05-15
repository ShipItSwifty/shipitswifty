$ shipit inspect

rootPath: /Users/you/projects/MyKMP
detectedPlatform: ios
detectedBuildSystem: kmp
buildSystemFiles:
  - build.gradle.kts
  - settings.gradle.kts
gradleFiles:
  - gradlew
  - build.gradle.kts
  - settings.gradle.kts
xcodeContainers:
  - kind: workspace
    path: iosApp/iosApp.xcworkspace
schemes:
  - name: iosApp
    likelyRunnable: true
