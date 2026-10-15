#!/bin/zsh
# P6.4 取证：监控页「温度与风扇」卡（SMC 只读）。
#
# 为什么要夹具 + 卡过滤这一整套：这张卡排在整页最后，760pt 窗口里永远在折叠线以下；
# 而它的四个降级分支（打不开 SMC / 无风扇 / FNum 读不出 / ≥90 °C 转红）在本机
# 一个都构造不出来——本机是 Mac mini M4，有 1 台风扇、174 个可读温度键、空闲 54.5 °C。
# 手法照 MM_GUARDIAN_CARDS：`MM_MONITOR_CARDS=sensors` 只渲染要拍的那张卡，
# 位置由钩子钉死，不靠窗口高度碰运气。
#
#   ./Scripts/p64-capture.sh <app 路径> <输出目录> [light|dark] [宽x高]
#   ONLY=02 ./Scripts/p64-capture.sh … 只重拍 02 那一档
#
# 全部零合成点击；抓完即杀，且只 kill 自己起的 pid。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SIZE=${4:-}

# P45 补的归因头＋内容指纹门禁（配方同 p69）：这一族出片早于 P23b，
# 旧那 26 张（`p64`／`p64-dark`／`p65`／`p65-dark`／`p67-menubar-off`）的 `.log` 里没有
# `# digest:`，"照片与二进制同源"对它们说不成立。产物与当前树不等就一张都不出。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p45 -s /tmp/mm-scratch-p45 重新构建再取证。"
  exit 4
fi

mkdir -p "$OUT"

# shot <文件名> <等待秒> <模块> <环境变量...>
shot() {
  local name=$1 settle=$2 module=$3; shift 3
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  rm -f "$OUT/$name.png"
  print -r -- "# p64-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=$module${SIZE:+ MM_WINDOW_SIZE=$SIZE} $*" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE="$module" \
      ${SIZE:+MM_WINDOW_SIZE="$SIZE"} "$@" "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  local pid=$!
  sleep "$settle"
  local wid
  wid=$(swift Scripts/window-ids.swift --pid "$pid" 2>/dev/null \
        | sed -n 's/^windowid=\([0-9]*\).*/\1/p' | head -1)
  if [[ -z "$wid" ]]; then
    print -u2 -- "⚠ $name：pid=$pid 没有可见窗口（不产出空照片）"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid settle=${settle}s"
}

# 01 实机真读数：不注入任何夹具，走 SMCClient → 键表枚举（1369 键，只有第一帧付）
#    → 174 个温度键 + F0Ac/Mn/Mx。这一张是"进程内也能读 SMC"的唯一证据——
#    独立探针（Scripts/smc-probe.swift）能读不代表 .app 里能读（沙盒/签名是另一回事）。
#    等 12 秒：稳态每帧 ~25 ms，但第一帧要整表枚举，加上窗口起来与首次差分。
shot 01-monitor-sensors-real 12 monitor MM_MONITOR_CARDS=stats,sensors
# 02 正常态夹具（稿子 E1 用的是 01 那组真读数，这一档证明的是同一形态在夹具下也可复现）：
#    10 个 TZZ* 温度点（前 8 上卡）+ 1 台风扇 2100 RPM。
shot 02-monitor-sensors-loaded 6 monitor \
     MM_MONITOR_CARDS=sensors MM_MONITOR_FIXTURE=sensors
# 03 整卡不可用：reason 由钩子给原文，验证"不静默、不塌成空列表"（稿 E2）。
#    整条赋值要加引号——reason 文案里有空格，不加引号 env 会把后半句当命令。
shot 03-monitor-sensors-unavailable 6 monitor \
     MM_MONITOR_CARDS=sensors \
     "MM_MONITOR_FIXTURE=sensors-unavailable:IOServiceOpen(AppleSMC) 失败：kIOReturnDenied"
# 04 E3 无风扇：读到 FNum=0 —— 与 05 的"FNum 读不出"必须是两句话。
shot 04-monitor-sensors-nofan 6 monitor \
     MM_MONITOR_CARDS=sensors MM_MONITOR_FIXTURE=sensorsNoFan
# 05 E4 风扇数未知：fanCount=nil，卡里要同时出现"风扇 —"与那句"未知不等于 0 台"。
shot 05-monitor-sensors-fanunknown 6 monitor \
     MM_MONITOR_CARDS=sensors MM_MONITOR_FIXTURE=sensorsFanUnknown
# 06 E5 红档：本机空闲最高 54.5 °C，≥90 °C 的转红只能靠夹具。
shot 06-monitor-sensors-hot 6 monitor \
     MM_MONITOR_CARDS=sensors MM_MONITOR_FIXTURE=sensorsHot
# 07 相邻与间距：新卡排在进程卡之后，单独渲染时看不出卡间距与页底留白。
#    只留这两卡（合计 ~700pt）就能在 760pt 窗口里同屏，且不用把窗口画高。
shot 07-monitor-sensors-after-process 6 monitor \
     MM_MONITOR_CARDS=process,sensors MM_MONITOR_FIXTURE=processes,sensors
# 08 非法值整批作废（钩子铁律）：画面应回到六卡全在的真实顺序，
#    stderr 里那句「含非法取值…整个钩子已忽略」是本档的判据，照片只是佐证。
shot 08-monitor-cards-illegal-token 8 monitor MM_MONITOR_CARDS=sensors,typo

print -r -- "→ $OUT"
print -r -- "08 的检查：grep 含非法取值 $OUT/08-monitor-cards-illegal-token.log"
