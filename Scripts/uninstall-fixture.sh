#!/bin/zsh
set -e

fixture_root=$(mktemp -d /tmp/macmaster-uninstall-fixture.XXXXXX)
app="$fixture_root/Applications/Fixture Notes.app"
cache="$fixture_root/Library/Caches/com.example.FixtureNotes"
mkdir -p "$app/Contents/MacOS" "$cache"

plist="$app/Contents/Info.plist"
plutil -create xml1 "$plist"
plutil -insert CFBundleIdentifier -string com.example.FixtureNotes "$plist"
plutil -insert CFBundleName -string 'Fixture Notes' "$plist"
plutil -insert CFBundleExecutable -string FixtureNotes "$plist"
plutil -insert CFBundleShortVersionString -string 1.0 "$plist"
printf 'fixture only\n' > "$app/Contents/MacOS/FixtureNotes"
printf 'cache fixture\n' > "$cache/payload.bin"

print -r -- "$fixture_root"
