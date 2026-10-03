#!/bin/zsh
# P6.2a「磁盘标记跨重扫存续」三档取证：① 首次扫描后打上标记 ② 同一个根重扫 ③ 换一个根重扫。
#
# 为什么三档都能零点击：标记由 MM_DISK_SELECT + MM_SHOW_CONFIRM 在扫描落地时打上
# （它代表"用户动手标记过一次"，钩子现在只重放一次，见 applySelectionHook），
# 第二次扫描由新增的 MM_DISK_RESCAN 自己发起。全程不碰鼠标：
# 合成点击会逃逸到用户的其它应用（老规矩）。
#
# 三档各拍什么：
#   ① 基线：面板上 2 个标记、各自的大小
#   ② 同根重扫：标记还在（改这一条之前，重扫会把它们全清空）
#   ③ 换根重扫：新扫描里还找得到的那个换成新体积，找不到的直接丢弃并在面包屑上点名
#
#   ./Scripts/p62-capture.sh <app 路径> <输出目录> [light|dark] [宽x高]
#   ONLY=03 ./Scripts/p62-capture.sh … 只重拍 03 那一档
#
# 夹具：./Scripts/disk-fixture.sh（磁盘页一直在用的那棵小树，本次不新增夹具）。
# 抓完即杀，且只 kill 自己起的 pid。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SIZE=${4:-}
FIXTURE=/tmp/macmaster-disk-fixture
# 两条标记故意分在两个不同的顶层目录：③ 换根重扫时一条挂得回去、一条挂不回去。
MARKS="$FIXTURE/Documents/report-2026.pdf,$FIXTURE/Downloads"
# 第二次扫描要等第一次扫完 + 钩子打完标记，留足时间；夹具只有 78 MB，扫描本身是毫秒级。
SETTLE=${SETTLE:-8}

[[ -d $FIXTURE ]] || { print -u2 -- "夹具不存在：先跑 ./Scripts/disk-fixture.sh"; exit 2; }
mkdir -p "$OUT"

# shot <文件名> <环境变量...>
shot() {
  local name=$1; shift
  # ONLY=03 ./Scripts/p62-capture.sh … 只重拍一档：三档各起一次应用。
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=disk MM_OPEN_TAB=tree \
      MM_DISK_SCAN="$FIXTURE" MM_DISK_SELECT="$MARKS" MM_SHOW_CONFIRM=1 \
      ${SIZE:+MM_WINDOW_SIZE="$SIZE"} "$@" "$APP/Contents/MacOS/MacMaster" >"$log" 2>&1 &
  local pid=$!
  sleep "$SETTLE"
  local wid
  wid=$(swift Scripts/window-ids.swift --pid "$pid" 2>/dev/null \
        | sed -n 's/^windowid=\([0-9]*\).*/\1/p' | head -1)
  if [[ -z "$wid" ]]; then
    print -u2 -- "⚠ $name：pid=$pid 没有可见窗口（不产出空照片）"
    kill "$pid" 2>/dev/null || true
    return 1
  fi
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid"
}

shot 01-marks-before
shot 02-marks-after-rescan MM_DISK_RESCAN="$FIXTURE"
shot 03-marks-after-root-switch MM_DISK_RESCAN="$FIXTURE/Documents"
print -r -- "→ $OUT"
