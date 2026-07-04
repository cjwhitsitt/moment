#!/bin/zsh

fvm flutter build apk --release
adb devices | grep -v List | grep device | cut -f 1 | xargs -I {} -P 8 adb -s {} install -r build/app/outputs/flutter-apk/app-release.apk
