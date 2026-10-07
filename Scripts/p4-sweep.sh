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

# 归因头 + 同源门禁（P26 补：这一支是九屏逐屏取证的主工具，此前是 27 支持照脚本里
# 没有门禁的那 22 支之一——它产出的照片能说"画面长这样"，不能说"这画面是这棵树构建的产物"）。
# 用 -uno：本脚本正往证据目录里写未跟踪的 .log/.png，算进脏活就永远是 -dirty。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一屏一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先按顺序来：提交 → ./Scripts/make-app.sh → 再跑本脚本。"
  exit 4
fi

# 设置页不是模块目的地，它靠 MM_SHOW_SETTINGS 弹出，所以单独列一行
targets=(dashboard cleaner uninstaller disk monitor guardian optimizer settings)
if [[ -n "$SELECTED" ]]; then
  targets=(${=SELECTED})
fi
for m in $targets; do
  log="$OUT/$m.log"
  # 四行归因头先落盘，应用自己的输出往后追加（原来是直接截断，头一写就没了）。
  print -r -- "# p4-sweep.sh $m  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# env: ${extra[*]} ${EXTRA:+$EXTRA }" >>"$log"
  if [[ "$m" == "settings" ]]; then
    env MM_SHOW_SETTINGS=1 "${extra[@]}" "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  else
    env MM_OPEN_MODULE="$m" "${extra[@]}" "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
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
  # `tail -n +5`：上面那四行归因头里就写着 MM_APPEARANCE/MM_WINDOW_SIZE，
  # 连头一起 grep 等于**脚本自己给钩子作证**——这一行要的凭据是应用自己打出来的那句。
  marks=$(tail -n +5 "$log" | grep -E "MM_[A-Z]|夹具|示例|TZZ|com\.example" | head -6 | tr '\n' '；')
  print -r -- "✅ $m windowid=$wid ${marks}"
done

print -r -- "→ $OUT"
print -r -- "转 jpeg：for f in $OUT/*.png; do sips -s format jpeg -Z 1400 \"\$f\" --out \"\${f%.png}.jpg\" >/dev/null; done"
