#!/bin/zsh
# 逐屏量窗口几何：每一页都问同一个问题——SwiftUI 的宿主视图有没有比窗口高。
#
#   ./Scripts/window-probe-sweep.sh [light|dark]
#
# 为什么需要它：某一页里一个 `.fixedSize(vertical:)` 就能让整页按理想高度布局，
# 宿主视图长到 1100 多 pt，而窗口只有 760 pt——上下各裁掉一截。
# 照片上看像"整个窗口错位"，只有把 host 的高度和窗口高度并排量出来才能定案，
# 而且必须逐页量：错位的成因在页面里，不在壳里。
#
# 只启动自己拉的实例、只 kill 自己的 pid；探针（MM_PROBE_WINDOW）只读帧不改帧。
set -e

cd "$(dirname "$0")/.."
APPEARANCE=${1:-light}
APP=${APP:-build/MacMaster.app}
OUT=${OUT:-docs/verification/window-probe}
WAIT=${WAIT:-7}

mkdir -p "$OUT"
typeset -a pages=(dashboard cleaner uninstaller disk monitor guardian optimizer)
typeset -a summary=()

for m in "${pages[@]}"; do
    log="$OUT/$m.log"
    env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE="$m" MM_PROBE_WINDOW=1 \
        "$APP/Contents/MacOS/MacMaster" >"$log" 2>&1 &
    pid=$!
    sleep "$WAIT"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    last=$(grep "PROBE win" "$log" 2>/dev/null | grep -v NSStatusBarWindow | tail -1)
    if [[ -z "$last" ]]; then
        summary+=("$m: 没量到（日志里没有 PROBE 行，多半是没窗口或钩子没生效）")
        continue
    fi
    win=$(print -r -- "$last" | grep -o 'frame=W[0-9]*xH[0-9]*' | head -1 | sed 's/frame=//')
    host=$(print -r -- "$last" | grep -o 'AppKitPlatformViewHost.*' \
           | grep -o 'W[0-9]*xH[0-9]*' | tail -1)
    winH=${win#*H}; hostH=${host#*H}
    if [[ "$hostH" == "${winH%%@*}" ]]; then
        summary+=("$m: 齐平  窗口 $win / 宿主 $host")
    else
        summary+=("$m: ⚠️ 溢出  窗口 $win / 宿主 $host（差 $(( ${hostH%%@*} - ${winH%%@*} ))pt）")
    fi
done

print -r -- "—— 逐屏窗口几何（外观=$APPEARANCE，每页等 ${WAIT}s）——"
for line in "${summary[@]}"; do print -r -- "  $line"; done
print -r -- "原始日志在 $OUT/*.log"

# 结论也落一份进仓库：文档要引用的是"哪一页在哪个尺寸下齐平/溢出"，
# 而 .log 里是逐时间点的原始帧，两者不是一回事。
{
    print -r -- "外观=$APPEARANCE · 每页等 ${WAIT}s · 请求尺寸=${MM_WINDOW_SIZE:-默认 1100x760}"
    for line in "${summary[@]}"; do print -r -- "$line"; done
} > "$OUT/sweep.txt"