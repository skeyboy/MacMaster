#!/bin/zsh
# 逐屏实机取证扫描：按模块依次起实例、按 pid 抓自己的窗口、抓完即杀。
# 为什么按 pid 而不是按应用名：并发改动期间同机器可能跑着多个 MacMaster，
# 名字匹配会抓到别人的窗口，产出的照片"看着真、来源错"，比没照片更糟。
#
# 用法：./Scripts/p4-sweep.sh <app 路径> <输出目录> [light|dark] [宽x高]
#   ./Scripts/p4-sweep.sh /tmp/mmapp-p4/MacMaster.app /tmp/p4-light light
#   ./Scripts/p4-sweep.sh /tmp/mmapp-p4/MacMaster.app /tmp/p4-min  light 900x600
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SIZE=${4:-}

mkdir -p "$OUT"
typeset -a extra
[[ -n "$SIZE" ]] && extra=(MM_WINDOW_SIZE="$SIZE")
[[ -n "$APPEARANCE" ]] && extra=(MM_APPEARANCE="$APPEARANCE")

# 设置页不是模块目的地，它靠 MM_SHOW_SETTINGS 弹出，所以单独列一行
targets=(dashboard cleaner uninstaller disk monitor guardian optimizer settings)
for m in $targets; do
  log="$OUT/$m.log"
  if [[ "$m" == "settings" ]]; then
    env MM_SHOW_SETTINGS=1 "${extra[@]}" "$APP/Contents/MacOS/MacMaster" >"$log" 2>&1 &
  else
    env MM_OPEN_MODULE="$m" "${extra[@]}" "$APP/Contents/MacOS/MacMaster" >"$log" 2>&1 &
  fi
  pid=$!
  sleep 3.5
  wid=$(swift Scripts/window-ids.swift --pid "$pid" 2>/dev/null \
        | sed -n 's/^windowid=\([0-9]*\).*/\1/p' | head -1)
  if [[ -z "$wid" ]]; then
    print -r -- "⚠ $m：pid=$pid 没有可见窗口（跳过，不产出空照片）"
    kill "$pid" 2>/dev/null || true
    continue
  fi
  screencapture -o -x -l"$wid" "$OUT/$m.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  # 取证标记落在文件名之外还要能追溯：这一行是钩子是否真生效的凭据
  marks=$(grep -E "MM_APPEARANCE|MM_WINDOW_SIZE" "$log" | head -2 | tr '\n' '；')
  print -r -- "✅ $m windowid=$wid ${marks}"
done

print -r -- "→ $OUT"
print -r -- "转 jpeg：for f in $OUT/*.png; do sips -s format jpeg -Z 1400 \"\$f\" --out \"\${f%.png}.jpg\" >/dev/null; done"
