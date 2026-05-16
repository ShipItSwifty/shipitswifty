#!/bin/sh
# Runs: npx react-native build-android --mode=release --tasks bundleRelease
shipit archive --platform android
# AAB at: android/app/build/outputs/bundle/release/app-release.aab
