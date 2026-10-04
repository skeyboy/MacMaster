#!/bin/zsh
# I11 取证：真实负载下让温度跨过 90 °C 再回落，逐帧抓屏。
#
# 为什么这一档值得专门跑一次脚本：迟滞（进 90 / 出 85）是**随时间**的行为，
# 而 MM_MONITOR_FIXTURE 每次进程只给一个定格快照——夹具拍不出"跨阈值之后又落回来还红着"。
# 唯一的真办法是让本机自己真的热上去再冷下来：零合成点击，温度也是真读数。
#
#   ./Scripts/i11-hysteresis-capture.sh <app 路径> <输出目录>
#
# 判据：出现一帧"最高温在 85–89.9 °C 之间、那一行仍是 destructive 红"。
# 单点阈值拍不出这一帧（它会是白的），所以这张就是改动的正面证据。
# 抓完杀自己记的 pid（应用 + 负载循环都记），不 pkill。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
LOAD=${LOAD:-8}          # 几个 yes 循环；Mac mini M4 十核，8 个够跨过 90
FRAMES=${FRAMES:-26}

mkdir -p "$OUT"

env MM_OPEN_MODULE=monitor MM_MONITOR_CARDS=sensors "$APP/Contents/MacOS/MacMaster" >"$OUT/app.log" 2>&1 &
APP_PID=$!
print -r -- "应用 pid=$APP_PID"

WID=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 2
  WID=$(swift Scripts/window-ids.swift --pid "$APP_PID" 2>/dev/null \
        | sed -n 's/^windowid=\([0-9]*\).*/\1/p' | head -1)
  [[ -n "$WID" ]] && break
done
[[ -n "$WID" ]] || { print -u2 -- "pid=$APP_PID 没有可见窗口"; kill "$APP_PID"; exit 1; }
print -r -- "windowid=$WID"

LOAD_PIDS=()
for i in $(seq 1 "$LOAD"); do
  yes > /dev/null &
  LOAD_PIDS+=($!)
done
print -r -- "负载 pid=${LOAD_PIDS[1]}…（$LOAD 个）"

# 每帧只抓屏：数字本来就在照片里。
# （不再顺手跑一次 Scripts/smc-probe.swift——它自己就要连开 1369 次 SMC 往返，
# 既是额外负载，又和页面不是同一时刻，对不上反而误导。）
for f in $(seq 1 "$FRAMES"); do
  screencapture -o -x -l"$WID" "$OUT/frame-$(printf '%02d' "$f").png"
  print -r -- "frame $f 已抓"
  # 前 10 帧带负载，后面让它自己冷下来
  if [[ $f -eq 10 ]]; then
    for p in $LOAD_PIDS; do kill "$p" 2>/dev/null || true; done
    print -r -- "负载已停，继续拍冷却段"
  fi
  sleep 3
done

for p in $LOAD_PIDS; do kill "$p" 2>/dev/null || true; done
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true

print -r -- "→ $OUT（$FRAMES 帧）。下一步：Scripts/i11-strip.swift 把温度行拼成对比条再读。"
