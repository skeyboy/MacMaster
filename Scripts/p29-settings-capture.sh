#!/bin/zsh
# P29 设置页取证：四张 tab 各拍一张，拍的是**那张 sheet 窗口本身**，不是主窗口。
#
# 为什么要单独写一支，而不复用 `p7-release-check.sh` 的 02-about：那一支只要一张关于页，
# 而且取的是 `--pid` 列表里的**第一个**窗口。设置页是以 sheet 呈现的（`MainWindow.swift:27`），
# 和主窗口同属一个 pid，"第一个"到底是哪一个是渲染顺序决定的——用户报"设置里的功能几乎不可用"，
# 我要看的正是另外三张 tab 在这一格里到底摆得下摆不下，所以这里按**边界宽度**认窗口：
# sheet 的宽度由 `SettingsView.swift` 的 `.frame(width: 500, ...)` 钉死（P29a 之后高度从
# 400 变成 560，宽度没动，所以这一条判据仍然只认 500），
# 主窗口的地板是 1000x600（`MacMasterApp.swift:43`），两个数不会撞。
#
# 只用"抓窗口"这一条路：本项目验证原生 UI 绝不做合成点击（会逃逸到用户的前台应用）。
# tab 由 MM_SETTINGS_TAB 选，sheet 由 MM_SHOW_SETTINGS 开，两者都是只给取证用的钩子。
#
# 顺带带 MM_DUMP_MENUS=1：菜单栏下拉与主菜单里有没有「设置」入口，是只有点开才看得见的东西，
# 而不能点——所以让 app 自己把两支菜单的条目文字打进 stderr（`LaunchMenuDump`），
# 跟着这一族的每份日志落盘，成为"入口在不在"的凭据。
#
#   ./Scripts/p29-settings-capture.sh /tmp/mm-p29a/MacMaster.app docs/verification/p29-settings
set -e

cd "$(dirname "$0")/.."
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${APPEARANCE:-light}
SETTLE=${SETTLE:-6}

source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh 重新构建，再跑这一支。"
  exit 4
fi

mkdir -p "$OUT"
sig=$(codesign -dv "$APP" 2>&1 | grep -oE 'flags=0x[0-9a-f]+\([a-z]+\)' | tr '\n' ' ')
gitc=$(plutil -p "$APP/Contents/Info.plist" 2>/dev/null \
      | sed -nE 's/.*"MMGitCommit" => "(.*)".*/\1/p')

# shot <tab 名>：起一个只开设置页的实例 → 按宽度挑出 sheet → 拍它 → 收掉自己起的 pid。
shot() {
  local tab=$1
  local log="$OUT/00-$tab.log"
  {
    print -r -- "# p29-settings-capture.sh tab=$tab  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP"
    print -r -- "# env: MM_SHOW_SETTINGS=1 MM_SETTINGS_TAB=$tab MM_APPEARANCE=$APPEARANCE MM_DUMP_MENUS=1"
    print -r -- "# repo: $repoTag branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
    mm_provenance_line
    print -r -- "# codesign: $sig"
    print -r -- "# plist: MMGitCommit=${gitc:-（无这一键）}"
  } >"$log"
  env MM_SHOW_SETTINGS=1 MM_SETTINGS_TAB="$tab" MM_APPEARANCE="$APPEARANCE" MM_DUMP_MENUS=1 \
    "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  local pid=$!
  sleep "$SETTLE"
  local all
  all=$(swift Scripts/window-ids.swift --pid "$pid" 2>/dev/null || true)
  print -r -- "# windows(pid=$pid): ${all//$'\n'/ | }" >>"$log"
  # sheet 的判据是宽度 500（±1 抗缩放取整）。挑不到就一张都不出，而不是退回"第一个窗口"——
  # 那正好是这一支要修的毛病的形状。
  local wid
  wid=$(printf '%s\n' "$all" | awk 'match($0, /"Width": [0-9]+/) {
          w = substr($0, RSTART + 9, RLENGTH - 9) + 0
          if (w >= 499 && w <= 501) { match($0, /windowid=[0-9]+/); print substr($0, RSTART + 9, RLENGTH - 9); exit }
        }')
  if [[ -z "$wid" ]]; then
    print -u2 -- "⚠ $tab：pid=$pid 里没有宽度 500 的 sheet 窗口（不产出空照片）"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  screencapture -o -x -l"$wid" "$OUT/$tab.png"
  print -r -- "# captured windowid=$wid" >>"$log"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $tab windowid=$wid"
}

for tab in general monitor cleaner about; do
  shot "$tab"
done

print -r -- "→ $OUT（判据：每张应当只有宽度 500 那一格 sheet，画面顶部是「设置」标题与四个分段控件；"
print -r -- "  某一节的控件在画面里够不着、又没有任何可滚动的迹象，那一节对用户就是找不到的；"
print -r -- "  每份日志末尾的 MM_DUMP_MENUS 行是两支菜单的条目文字，「设置」入口在不在看这一行）"
