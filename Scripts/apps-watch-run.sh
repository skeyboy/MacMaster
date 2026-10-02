#!/bin/zsh
# 03e 应用装卸监听的实机取证：起实例 → 等基线 → 由脚本改目录 → 按 pid 抓自己的窗口。
#
#   ./Scripts/apps-watch-run.sh notice            # 消失卡 + 新条目提示 + 旧快照列表行
#   ./Scripts/apps-watch-run.sh scan              # 「重新载入并扫描」的终点（后遗症确认面板）
#   ./Scripts/apps-watch-run.sh echo light        # 自我回声：你刚卸载了 X + 由 MacMaster 移入
#   ./Scripts/apps-watch-run.sh skipped           # 真机：~/Applications 不存在那张说明卡
#
# 为什么不复用 p4-sweep.sh：它按固定延时截图，而这一档的时序是
# "启动 → 等监听建好基线 → 改目录 → 再截"。改动必须发生在监听之后，
# 否则它会被当成基线的一部分（首帧只建基线，什么都不报），照片就成了一张干净的列表。
#
# 改目录用的是夹具脚本（`apps-watch-fixture.sh depart`）而不是合成点击：
# 前者是"外部世界真的变了"（探针已证明这类改动会送 kqueue 事件），
# 后者点不进原生控件，而且会逃逸到用户的其它应用。
# 唯一替用户按下按钮的是 `MM_UNINSTALL_SELF_ECHO` / `MM_APPS_WATCH_AUTO_SCAN` 两个钩子，
# 它们都要求 /tmp 夹具成立才生效 —— 没有它们，这两档状态在实机上根本拍不到。
set -e

cd "$(dirname "$0")/.."
CASE=${1:?用法：notice|scan|echo|skipped}
APPEARANCE=${2:-light}
APP=${APP:-build/MacMaster.app}
OUT=${OUT:-docs/verification/p9-apps-watch}
FIX=/tmp/mmapps

mkdir -p "$OUT"
./Scripts/apps-watch-fixture.sh

typeset -a run_env=(MM_APPEARANCE="$APPEARANCE"
                    MM_OPEN_MODULE=uninstaller
                    MM_UNINSTALL_PANE=apps
                    MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$FIX"
                    MM_UNINSTALL_CONFIRM_MODE=none)
case "$CASE" in
    # 「不在这台机器上」那张说明卡要的是**真机**：监听口径 = `AppScanner` 的列举口径，
    # 本机恰好有 /Applications 而没有 ~/Applications，一开机就是那个态。
    # 用了夹具目录反而拍不到——钩子会把监听根整个换成那一个目录，没有"跳过"可言。
    skipped) run_env=($run_env[1,3] MM_PROBE_WINDOW=1) ;;
    notice)  run_env+=(MM_APPS_WATCH_FIXTURE_DIR="$FIX/Applications") ;;
    scan)    run_env+=(MM_APPS_WATCH_FIXTURE_DIR="$FIX/Applications"
                       MM_ORPHAN_FIXTURE_HOME="$FIX" MM_APPS_WATCH_AUTO_SCAN=1) ;;
    echo)    run_env+=(MM_APPS_WATCH_FIXTURE_DIR="$FIX/Applications"
                       MM_TRASH_SCAN_HOME="$FIX" MM_UNINSTALL_SELF_ECHO=1 MM_UNINSTALL_SELECT=Highball) ;;
    *)      print -u2 -- "未知档位：$CASE（notice|scan|echo|skipped）"; exit 2 ;;
esac

# 只有 echo 那一档会让本体真的进 ~/.Trash（那是它要证明的事）。
# 跑完先把它清掉，别在用户的废纸篓里堆 Highball.app / Highball 2.app / …
# 认凭据不认名字：只删包标识确实是 com.example.Highball 的那一个。
trash_cleanup() {
    for candidate in "$HOME/.Trash"/Highball*.app(N); do
        id=$(plutil -extract CFBundleIdentifier raw "$candidate/Contents/Info.plist" 2>/dev/null)
        if [[ "$id" == "com.example.Highball" ]]; then
            rm -rf -- "$candidate"
            print -u2 -- "已清掉本次取证移进废纸篓的夹具应用：$candidate"
        fi
    done
}

# 环境变量必须在二进制之前（`env K=V cmd`）。写成 `cmd K=V` 它们会进 argv，
# 界面照旧启动、钩子一个都不认，拍出来的却是真机的应用列表 —— 照片看着真，来源全错。
env "${run_env[@]}" "$APP/Contents/MacOS/MacMaster" >"$OUT/$CASE.log" 2>&1 &
pid=$!
print -r -- "已启动 pid=$pid（外观=$APPEARANCE 档位=$CASE），等监听建基线…"
print -r -- "钩子：${run_env[*]}"
sleep 12

if [[ "$CASE" != "echo" && "$CASE" != "skipped" ]]; then
    ./Scripts/apps-watch-fixture.sh depart
    sleep 3      # 合并窗口 400ms + 一次目录列举，留够但不靠它决定结果
fi

wid=$(swift Scripts/window-ids.swift --pid "$pid" 2>/dev/null \
      | sed -n 's/^windowid=\([0-9]*\).*/\1/p' | head -1)
if [[ -z "$wid" ]]; then
    kill "$pid" 2>/dev/null || true
    trash_cleanup
    print -u2 -- "pid=$pid 没有可见窗口，不产出空照片；日志在 $OUT/$CASE.log"
    exit 1
fi
screencapture -o -x -l"$wid" "$OUT/$CASE.png"
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
trash_cleanup

print -r -- "✅ $OUT/$CASE.png（windowid=$wid）"
grep -E "夹具|钩子|不在这台|废纸篓|kqueue|错误码" "$OUT/$CASE.log" | head -6
print -r -- "转 jpeg 供对照：sips -s format jpeg -Z 1500 $OUT/$CASE.png --out $OUT/$CASE.jpg"
