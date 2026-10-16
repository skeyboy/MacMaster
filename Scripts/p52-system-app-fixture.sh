#!/bin/zsh
# P52b 夹具：一个只放在 /tmp 的假 home，专门喂 `MM_UNINSTALL_CONFIRM_FIXTURE_HOME`。
#
# 两行应用，一行的差别只有一个包标识前缀：
#   · `ApplePages.app` → `com.apple.FixturePages`（`AppScanner.isSystemOwned` 成立那一档，本体转只读）
#   · `PlainTool.app` → `com.example.PlainTool`（对照，本体照常给删除入口）
# 两边各放一份 `Library/Caches/<包标识>` 的占位文件：系统应用那一档"连扫都不扫"这件事，
# 只有夹具里真放着它名下的文件才拍得出来（否则画面上"没有残留"可能只是没有残留）。
#
# 这一族不启动任何 bundle，也不删任何东西：照片拍的是删除入口给不给，不是删完之后。
# 夹具目录留在 /tmp 由调用方决定何时删。
set -e

fixture_root=$(mktemp -d /tmp/macmaster-p52-fixture.XXXXXX)

make_app() {
  local name=$1 bundleID=$2
  local app="$fixture_root/Applications/$name.app"
  mkdir -p "$app/Contents/MacOS"
  local plist="$app/Contents/Info.plist"
  plutil -create xml1 "$plist"
  plutil -insert CFBundleIdentifier -string "$bundleID" "$plist"
  plutil -insert CFBundleName -string "$name" "$plist"
  plutil -insert CFBundleExecutable -string "$name" "$plist"
  plutil -insert CFBundleShortVersionString -string 1.0 "$plist"
  plutil -insert CFBundleVersion -string 42 "$plist"
  printf 'fixture only\n' > "$app/Contents/MacOS/$name"
}

make_app ApplePages com.apple.FixturePages
make_app PlainTool com.example.PlainTool

for id in com.apple.FixturePages com.example.PlainTool; do
  mkdir -p "$fixture_root/Library/Caches/$id"
  printf 'payload\n' > "$fixture_root/Library/Caches/$id/payload.bin"
done

print -r -- "$fixture_root"
