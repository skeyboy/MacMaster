#!/bin/zsh
# P6.1「开发产物截断根续扫」三档取证：一次跑完 ①首批含截断 / ②续扫之后 / ③同一根再截断。
#
# 为什么三档都能零点击：截断由 MM_DEV_ROOT_BUDGET_SECONDS 定，续扫批的预算由
# MM_DEV_CONTINUE_BUDGET_SECONDS 定（两个键是必须的——同一个极小预算下，首批截断的根
# 在第二批必然同样截断，②那一档就永远拍不到），跑完首批后由 MM_DEV_AUTO_CONTINUE
# 自动接一批。全程不碰鼠标：合成点击会逃逸到用户的其它应用（老规矩）。
#
#   ./Scripts/p61-capture.sh <app 路径> <输出目录> [light|dark] [宽x高]
#   ./Scripts/p61-capture.sh /tmp/mm-p61-app/MacMaster.app /tmp/p61 light
#   ONLY=03 ./Scripts/p61-capture.sh … 只重拍 03 那一档
#
# 夹具：./Scripts/purge-fixture.sh（11 号那批 bulky 项目就是为这三档存在的）。
# 抓完即杀，且只 kill 自己起的 pid。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SIZE=${4:-}
FIXTURE=/tmp/macmaster-purge-fixture
# 首批 0.02 秒：真机实测这个值刚好让 ~/Documents 的 12 个候选"量到一半"，
# 于是第二批既有可复用的行、也有新量出来的行——②那一档要的就是这个混合态。
ROOT_BUDGET=0.02
# ③ 的续扫预算必须比首批**更小**，不能同值。实测同值 0.02 拍不出"扫过 2 次仍截断"：
# 第二批要处理的候选比第一批少得多（能复用的整行不再成案），0.02 秒反而够它扫完，
# 于是 ③ 落回"全部扫完"那一档。2 毫秒是刻意让它一定在第一个候选的预算检查上就收尾。
EXHAUST_BUDGET=0.002
SETTLE=${SETTLE:-8}

[[ -d $FIXTURE ]] || { print -u2 -- "夹具不存在：先跑 ./Scripts/purge-fixture.sh"; exit 2; }
mkdir -p "$OUT"

# shot <文件名> <环境变量...>
shot() {
  local name=$1; shift
  # ONLY=03 ./Scripts/p61-capture.sh … 只重拍一档：三档各起一次应用，
  # 改一处文案就全跑一遍太慢。
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=cleaner MM_OPEN_TAB=dev \
      MM_PURGE_FIXTURE_HOME="$FIXTURE" MM_DEV_EXPAND=1 \
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

shot 01-first-batch    MM_DEV_ROOT_BUDGET_SECONDS="$ROOT_BUDGET"
shot 02-after-continue MM_DEV_ROOT_BUDGET_SECONDS="$ROOT_BUDGET" \
                       MM_DEV_CONTINUE_BUDGET_SECONDS=30 MM_DEV_AUTO_CONTINUE=1 \
                       MM_DEV_SELECT=untouched
# ②b：同一档滚到底。「第 N 批补全」的组徽章在列表后半段（新补上的组按项目根排在
# 复用组后面），首屏拍不到；不补这一拍就只能说"徽章有单测、照片里没有"。
shot 02b-continue-bottom MM_DEV_ROOT_BUDGET_SECONDS="$ROOT_BUDGET" \
                       MM_DEV_CONTINUE_BUDGET_SECONDS=30 MM_DEV_AUTO_CONTINUE=1 \
                       MM_DEV_SELECT=untouched MM_DEV_SCROLL=end
shot 03-exhausted      MM_DEV_ROOT_BUDGET_SECONDS="$ROOT_BUDGET" \
                       MM_DEV_CONTINUE_BUDGET_SECONDS="$EXHAUST_BUDGET" MM_DEV_AUTO_CONTINUE=1
print -r -- "→ $OUT"
