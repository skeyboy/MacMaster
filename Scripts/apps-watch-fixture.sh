#!/bin/zsh
# P5.3 应用目录装卸监听的验证夹具：只在 /tmp 之下造文件，绝不碰真实 /Applications。
#
# ① 消失卡 + 新条目提示 + 旧快照的列表行（03e-live-1）
#   ./Scripts/apps-watch-fixture.sh
#   MM_OPEN_MODULE=uninstaller MM_UNINSTALL_PANE=apps \
#   MM_APPS_WATCH_FIXTURE_DIR=/tmp/mmapps/Applications \
#   MM_UNINSTALL_CONFIRM_FIXTURE_HOME=/tmp/mmapps MM_UNINSTALL_CONFIRM_MODE=none \
#     ./build/MacMaster.app/Contents/MacOS/MacMaster &
#   sleep 12                                 # 等基线建好：首帧只建基线，不报任何东西
#   ./Scripts/apps-watch-fixture.sh depart   # 删一个、装一个：两个方向同时发生
#
# ② 再跑一次同样的，加上 MM_APPS_WATCH_AUTO_SCAN=1 与 MM_ORPHAN_FIXTURE_HOME=/tmp/mmapps，
#   截「重新载入并扫描」的终点：清单刷新后它散在假 ~/Library 的残留才第一次成为孤儿。
#   （没有 MM_ORPHAN_FIXTURE_HOME 这一步会去扫真实 ~/Library —— 那才是真的拿用户文件做截图。）
#
# ③ 自我回声那两种文案（03e-3 ⑤）：加 MM_UNINSTALL_SELF_ECHO=1 与 MM_TRASH_SCAN_HOME=/tmp/mmapps，
#   它会替我们按下「仅卸载应用」。这一步需要完全磁盘访问 —— 废纸篓监听读的是真 ~/.Trash。
#
# 为什么用脚本改目录、用钩子按按钮，而不是点界面：探针（Scripts/apps-watch-probe.swift）
# 证明目录改动确实产生 kqueue 事件，所以改目录是"观察外部变化"；而合成点击进不了原生控件，
# 用它就是在验证一条并不存在的交互路径。
#
# 钩子只认 /tmp（TrashWatcher.fixtureEnvironmentValue），而且这条链路的终点是删除入口，
# 指向真实主目录就等于拿用户文件做截图。
set -e
ROOT=/tmp/mmapps
APPS=$ROOT/Applications
LIB=$ROOT/Library

make_app() {
    local dir="$APPS/$1.app" id="$2" display="$3"
    mkdir -p "$dir/Contents/MacOS"
    cat > "$dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$id</string>
  <key>CFBundleName</key><string>$1</string>
  <key>CFBundleDisplayName</key><string>$display</string>
  <key>CFBundleExecutable</key><string>$1</string>
  <key>CFBundleShortVersionString</key><string>1.4.2</string>
  <key>CFBundleVersion</key><string>88</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
    printf '%s' 'binary' > "$dir/Contents/MacOS/$1"
}

# 给某个应用配一小堆散在假 ~/Library 的残留，尺寸固定方便看图核对。
seed_residuals() {
    local name="$1" id="$2"
    mkdir -p "$LIB/Caches/$id" "$LIB/Application Support/$name" "$LIB/Preferences"
    dd if=/dev/zero of="$LIB/Caches/$id/payload.bin" bs=1m count=5 >/dev/null 2>&1
    dd if=/dev/zero of="$LIB/Application Support/$name/state.db" bs=1m count=2 >/dev/null 2>&1
    printf '%s' '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>lastRun</key><string>2026-10-01</string></dict></plist>' \
        > "$LIB/Preferences/$id.plist"
}

case "${1:-build}" in
build)
    # 上一轮的残留先清掉：否则"已经躺在目录里的应用"会被当成基线，什么都测不出来。
    rm -rf "$ROOT"
    mkdir -p "$APPS" "$LIB"
    make_app Highball com.example.Highball "Highball"
    make_app Keeper com.example.Keeper "Keeper"
    make_app Lumen com.example.Lumen "Lumen"
    seed_residuals Highball com.example.Highball
    seed_residuals Keeper com.example.Keeper
    print -r -- "夹具就绪：应用目录=$APPS · 假 home=$ROOT（残留散在 $LIB）"
    print -r -- "改目录（删 Highball、装 Notion）：./Scripts/apps-watch-fixture.sh depart"
    ;;
depart)
    mkdir -p "$APPS"
    # 「消失」：直接从目录里拿走，不进废纸篓 —— 这正是 P1.5 的盲区（rm -rf / 自带卸载器）。
    rm -rf "$APPS/Highball.app"
    # 「新出现」：装一个之前不在基线里的应用。
    make_app Notion com.example.Notion "Notion"
    print -r -- "已改动 $APPS：删掉 Highball.app，新增 Notion.app"
    ;;
restore)
    make_app Highball com.example.Highball "Highball"
    rm -rf "$APPS/Notion.app"
    print -r -- "已还原：Highball.app 回来了，Notion.app 拿掉了"
    ;;
*)
    print -u2 -- "用法：$0 [build|depart|restore]"
    exit 2
    ;;
esac
