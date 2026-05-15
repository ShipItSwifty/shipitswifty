$ shipit version bump --component build

[ShipIt] Current version: 1.0.0, build: 1 (source: kmp)
[ShipIt] Set versionCode to '2' in 'gradle.properties'
[ShipIt] Version bumped: 1.0.0 -> 1.0.0, build: 1 -> 2

$ cat gradle.properties
org.gradle.jvmargs=-Xmx2g
kotlin.code.style=official
versionName=1.0.0
versionCode=2
