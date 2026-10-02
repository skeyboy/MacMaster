#!/bin/zsh
# P5.2「安装来源」取证夹具：一棵假 home，里面每一行应用对应一档来源凭据。
#
#   eval "$(print -r -- "export FIX=$(./Scripts/provenance-fixture.sh)")"
#   MM_UNINSTALL_CONFIRM_FIXTURE_HOME=$FIX MM_UNINSTALL_SELECT=Highball ...
#
# 三条硬规矩（沿用 uninstall-fixture.sh / purge-fixture.sh）：
#   1. 只建在 /tmp 之下——这一页的终点是删除按钮；
#   2. 账本放在 `$root/.homebrew`，由 MM_UNINSTALL_CONFIRM_FIXTURE_HOME 顺带指过去，
#      不新增钩子，也绝不会去读真机的 /opt/homebrew；
#   3. staged 符号链接用真链接，不用假文本——"设备号同一"这条判据拿假数据测不出来。
set -e

root=$(mktemp -d /tmp/macmaster-provenance-fixture.XXXXXX)
apps="$root/Applications"
brew="$root/.homebrew/Caskroom"

make_app() {         # $1=目录名 $2=包名 $3=版本 [$4=mas]
  local dir="$apps/$1.app"
  mkdir -p "$dir/Contents/MacOS"
  plutil -create xml1 "$dir/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string "$2" "$dir/Contents/Info.plist"
  plutil -insert CFBundleName -string "$1" "$dir/Contents/Info.plist"
  plutil -insert CFBundleExecutable -string "$1" "$dir/Contents/Info.plist"
  plutil -insert CFBundleShortVersionString -string "$3" "$dir/Contents/Info.plist"
  plutil -insert CFBundleVersion -string "${3##*.}" "$dir/Contents/Info.plist"
  printf 'fixture only\n' > "$dir/Contents/MacOS/$1"
  if [[ "$4" == "mas" ]]; then
    mkdir -p "$dir/Contents/_MASReceipt"
    printf 'receipt placeholder\n' > "$dir/Contents/_MASReceipt/receipt"
  fi
}

make_receipt() {     # $1=token $2=版本 $3=声明的 .app 名（空串=不声明）
  local dir="$brew/$1"
  mkdir -p "$dir/.metadata" "$dir/$2"
  local apps_json=""
  if [[ -n "$3" ]]; then apps_json="\"$3\""; fi
  cat > "$dir/.metadata/INSTALL_RECEIPT.json" <<JSON
{
  "homebrew_version": "6.0.10",
  "installed_on_request": true,
  "time": 1784024063,
  "source": { "tap": "homebrew/cask", "version": "$2", "path": "/tmp/api.jws.json" },
  "uninstall_artifacts": [
    { "app": [$apps_json] },
    { "zap": [{ "trash": ["~/Library/Caches/$1", "~/Library/Preferences/$1.plist"] }] }
  ]
}
JSON
}

# ① 强证据：staged 链接解析后就是磁盘上这份 bundle
make_app Highball app.highball.Highball 0.9.39
make_receipt highball 0.9.39 Highball.app
ln -s "$apps/Highball.app" "$brew/highball/0.9.39/Highball.app"
mkdir -p "$root/Library/Caches/app.highball.Highball"
printf 'cache fixture\n' > "$root/Library/Caches/app.highball.Highball/payload.bin"

# ② 名字对上、设备号没对上：账本还在，那份 staged 链接指向一个已被挪走的目标
make_app CodeEdit com.codeedit.CodeEdit 0.3.6
make_receipt codeedit 0.3.6 CodeEdit.app
ln -s "$apps/CodeEdit.app.relocated-to-somewhere-else" "$brew/codeedit/0.3.6/CodeEdit.app"

# ③ App Store：bundle 里有 _MASReceipt
make_app WeChat com.tencent.xinWeChat 4.1.6 mas

# ④ 两份账本抢同一个名字：不替用户挑第一个
make_app Firefox org.mozilla.firefox 132.0
make_receipt firefox 132.0 Firefox.app
ln -s "$apps/Firefox.app" "$brew/firefox/132.0/Firefox.app"
make_receipt firefox-beta 132.0.0b9 Firefox.app
ln -s "$apps/Firefox.app" "$brew/firefox-beta/132.0.0b9/Firefox.app"

# ⑤ 什么凭据都没有：既不是"手动安装"，也不该有任何徽章
#    （名字不含空格：p4-sweep.sh 会按空格切附加环境变量，带空格的夹具名拍不到）
make_app "Fixture Notes" com.example.FixtureNotes 1.0
mkdir -p "$root/Library/Caches/com.example.FixtureNotes"
printf 'cache fixture\n' > "$root/Library/Caches/com.example.FixtureNotes/payload.bin"
make_app MysteryApp com.example.MysteryApp 1.0

print -r -- "$root"
