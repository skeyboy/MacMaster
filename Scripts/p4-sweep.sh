#!/bin/zsh
# 逐屏实机取证扫描：按模块依次起实例、按 pid 抓自己的窗口、抓完即杀。
# 为什么按 pid 而不是按应用名：并发改动期间同机器可能跑着多个 MacMaster，
# 名字匹配会抓到别人的窗口，产出的照片"看着真、来源错"，比没照片更糟。
#
# 用法：./Scripts/p4-sweep.sh <app 路径> <输出目录> [light|dark] [宽x高] [屏名...] [附加环境变量]
#   ./Scripts/p4-sweep.sh /tmp/mmapp-p4/MacMaster.app /tmp/p4-light light
#   ./Scripts/p4-sweep.sh /tmp/mmapp-p4/MacMaster.app /tmp/p4-min  light 900x600
#   ./Scripts/p4-sweep.sh /tmp/mmapp-p4/MacMaster.app /tmp/p4-disk  dark "" disk
#   ./Scripts/p4-sweep.sh /tmp/mm-p5-app/MacMaster.app /tmp/p5-sheet light "" disk \
#       "MM_DISK_SCAN=/tmp/macmaster-disk-fixture MM_SHOW_CONFIRM=1"
# 第 5 个参数用来只跑关心的几屏（一次全扫 8 屏要 40 秒，逐屏返工时太慢）。
# 第 6 个参数是逐屏共用的附加环境变量：确认面板这类"要先把数据摆上桌才拍得到"的屏，
# 靠模块钩子把状态推到位，而不是靠合成点击（点击会逃逸到用户其它应用）。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SIZE=${4:-}
SELECTED=${5:-}
EXTRA=${6:-}

mkdir -p "$OUT"
# 两个钩子要同时生效过：之前写成两次赋值，第二个把第一个覆盖掉了，
# 于是带尺寸的那轮其实只换了外观，照片上的"最小窗口"是假的。
typeset -a extra=()
[[ -n "$APPEARANCE" ]] && extra+=(MM_APPEARANCE="$APPEARANCE")
[[ -n "$SIZE" ]] && extra+=(MM_WINDOW_SIZE="$SIZE")
[[ -n "$EXTRA" ]] && extra+=(${=EXTRA})

# 设置页不是模块目的地，它靠 MM_SHOW_SETTINGS 弹出，所以单独列一行
targets=(dashboard cleaner uninstaller disk monitor guardian optimizer settings)
if [[ -n "$SELECTED" ]]; then
  targets=(${=SELECTED})
fi
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
  # 取证标记落在文件名之外还要能追溯：这一行是钩子是否真生效的凭据。
  # 别枚举钩子名——上一版只列了 MM_APPEARANCE/MM_WINDOW_SIZE/MM_DISK/MM_SHOW 四类，
  # 于是 monitor/guardian/optimizer/dev/watch 那十几个钩子即便真生效了，这行也是空的，
  # 读起来跟"钩子没落"一模一样。凡是 MM_ 开头的名字加上夹具哨兵词，一并收进来。
  marks=$(grep -E "MM_[A-Z]|夹具|示例|TZZ|com\.example" "$log" | head -6 | tr '\n' '；')
  print -r -- "✅ $m windowid=$wid ${marks}"
done

print -r -- "→ $OUT"
print -r -- "转 jpeg：for f in $OUT/*.png; do sips -s format jpeg -Z 1400 \"\$f\" --out \"\${f%.png}.jpg\" >/dev/null; done"
