#!/bin/zsh
# P6.5 取证：内存卡 Swap 一行的三种口径（I9）。
#
# 立项原因：I9 那条说的是「Swap 读到 0 输出 0 字节 / 0 字节」——中文里读起来像采样坏了，
# 而它其实想说"确实一点没用"。这一档**本机拍不到**：`sysctl vm.swapusage` 现在给的是
# used=800.69M / total=2048M（非零），零值只能靠 `MM_MONITOR_FIXTURE=swapZero` 摆。
# 于是三张都要：零值（新文案）、非零（旧对仗没被改坏）、读不到（"—"）——
# 前两档是**改动前后的对照**，第三档证明"读到 0"和"读不到"仍是两句话。
#
# 只用 MM_MONITOR_CARDS=memory 把这一张卡单独渲染（照 P6.4 的手法），
# 不靠窗口高度碰运气；全程零合成点击，抓完即杀，且只 kill 自己起的 pid。
#
#   ./Scripts/p65-swap-capture.sh <app 路径> <输出目录> [light|dark]
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}

# P45 补的归因头＋内容指纹门禁（配方同 p69），理由见 p64-capture.sh 同段注释。
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

# shot <文件名> <等待秒> <环境变量...>
shot() {
  local name=$1 settle=$2; shift 2
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  rm -f "$OUT/$name.png"
  print -r -- "# p65-swap-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=monitor MM_MONITOR_CARDS=memory $*" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=monitor \
      MM_MONITOR_CARDS=memory "$@" "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
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

# 01 实机真读数（不注任何夹具）：Swap 行应是「已用 / 总量」的非零对仗。
#    这一张是"改文案没把非零路径改坏"的回归证据，数字每一帧都能回到 sysctl。
shot 01-monitor-memory-real 8
# 02 I9 新档位：读到 0 且总量也是 0 → 「0 字节（未使用）」。
shot 02-monitor-memory-swapzero 6 MM_MONITOR_FIXTURE=swapZero
# 03 读不到 sysctl（swapAvailable=false）→ 仍是「—」，与 02 必须是两句话。
shot 03-monitor-memory-swapoff 6 MM_MONITOR_FIXTURE=swapOff
# 04 夹具底座（populated）：swap 现在是真实形状 838.9 MB / 2.1 GB，
#    这一档与 02 分开才有意义——底座原本也是 0/0，两档会拍成同一张。
shot 04-monitor-memory-populated 6 MM_MONITOR_FIXTURE=populated

print -r -- "→ $OUT（$APPEARANCE）"
