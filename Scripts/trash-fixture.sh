#!/bin/zsh
# P1.5 废纸篓提示的验证夹具：只在 /tmp 之下造文件，绝不碰真实用户目录。
#
#   ./Scripts/trash-fixture.sh          # 造出 /tmp/mmtrash、/tmp/mmhome、/tmp/mmstage
#   MM_TRASH_FIXTURE_DIR=/tmp/mmtrash MM_TRASH_SCAN_HOME=/tmp/mmhome \
#     MM_OPEN_MODULE=uninstaller ./build/MacMaster.app/Contents/MacOS/MacMaster &
#   mv /tmp/mmstage/Foo.app /tmp/mmtrash/     # 模拟"拖进废纸篓"
#
# 这两个钩子只认 /tmp（见 TrashWatcher.fixtureEnvironmentValue），所以带删除动作的
# 入口不会因为一个拼错的环境变量指向真实 ~/Library。
set -e
TRASH=/tmp/mmtrash
HOME_FIX=/tmp/mmhome
STAGE=/tmp/mmstage

# 上一轮的残留先清掉，否则"已存在的条目"会被当成基线，测不出新拖入。
rm -rf "$TRASH" "$HOME_FIX" "$STAGE"
mkdir -p "$TRASH" "$HOME_FIX/Library" "$STAGE"

LIB="$HOME_FIX/Library"
# 用 dd 而不是 mkfile：mkfile 预分配大文件时要特权，夹具只需要"文件真的有 N MB"。
seed() { mkdir -p "$(dirname "$1")"; dd if=/dev/zero of="$1" bs=1m count="${2%m}" >/dev/null 2>&1; }

# 5 MB 缓存 → safe（包名完全对应）
seed "$LIB/Caches/com.example.Foo/payload.bin" 5
# 1 MB 容器内可重建缓存 → safe
seed "$LIB/Containers/com.example.Foo/Data/Library/Caches/webkit.bin" 1
# 2 MB Application Support → caution（可能含账号与状态）
seed "$LIB/Application Support/Foo/state.db" 2
# 偏好设置 → caution
mkdir -p "$LIB/Preferences"
printf '%s' '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>didFinishOnboarding</key><true/></dict></plist>' > "$LIB/Preferences/com.example.Foo.plist"

# 一个最小可用的假 app bundle，包标识与上面的残留同名。
APP="$STAGE/Foo.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.example.Foo</string>
  <key>CFBundleName</key><string>Foo</string>
  <key>CFBundleDisplayName</key><string>示例应用</string>
  <key>CFBundleExecutable</key><string>Foo</string>
  <key>CFBundleShortVersionString</key><string>3.2.1</string>
  <key>CFBundleVersion</key><string>77</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
printf '%s' 'binary' > "$APP/Contents/MacOS/Foo"

print -r -- "夹具就绪：假废纸篓=$TRASH · 假 home=$HOME_FIX · 待拖入=$APP"
