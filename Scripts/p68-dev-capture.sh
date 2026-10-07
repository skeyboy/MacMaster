#!/bin/zsh
# P6.8「开发产物页 02c 七档」取证：把 docs/verification/p7-dev/ 那批 P5.1d 手工照片变成可重跑脚本。
#
# 背景：p7-dev 那 7 张是真的，但仓库里没有任何脚本会再拍一遍（改这块面板的人拿不到回归对照）。
# 这一轮就是补上重跑能力。照片改写到 docs/verification/p68-dev/，绝不覆盖 p7-dev（那是已提交证据）。
#
# 为什么七档都能零点击：这一屏的四个定格钩子把"要动手才进得去"的状态全部前置了——
# 展开分组 = MM_DEV_EXPAND，批量勾选"7 天未触碰"= MM_DEV_SELECT=untouched，
# 滚到底看四态徽标/最强证据行/读不到的行 = MM_DEV_SCROLL=end，弹确认面板 = MM_DEV_CONFIRM。
# 全程不碰鼠标：合成点击/滚轮会逃逸到用户的其它应用（老规矩）。
#
# 唯一没有钩子替身的是「真按下删除 → 拿回执」那条交互链：本项目禁合成点击，
# 所以 p7-dev 那批本来也没有删后态，这一轮同样不试图绕过。
#
#   ./Scripts/p68-dev-capture.sh <app 路径> <输出目录> [light|dark] [宽x高]
#   ./Scripts/p68-dev-capture.sh /tmp/mm-app-p68dev/MacMaster.app docs/verification/p68-dev
#   ONLY=04 ./Scripts/p68-dev-capture.sh … 只重拍 04 那一档
#
# 夹具：./Scripts/purge-fixture.sh（现成的，本轮不新造）。06 那一档刻意不注入夹具、扫真机。
# 抓完即杀，且只 kill 自己起的 pid。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SIZE=${4:-}
FIXTURE=/tmp/macmaster-purge-fixture
# 01–05、07 是夹具档：默认 8 秒够（夹具扫描是毫秒级，8 秒全花在 SwiftUI 排版与滚动落位上）。
SETTLE=${SETTLE:-8}
# 06 是真机档：不带 MM_PURGE_FIXTURE_HOME，扫的是本机 ~/Repos、~/fvm、~/Desktop…
# 实测这批根要 15 秒级才扫完（p7-dev 的 06 就是 16.2 秒），8 秒只会拍到"正在扫描"，
# 所以这一档单独给 30 秒。改真机目录布局的人要记得这个数。
REAL_SETTLE=${REAL_SETTLE:-30}

[[ -d $FIXTURE ]] || { print -u2 -- "夹具不存在：先跑 ./Scripts/purge-fixture.sh"; exit 2; }
mkdir -p "$OUT"

# shot <文件名> <等待秒> <环境变量...>
# 公共部分（模块/页签/外观/尺寸）在这里统一注入；夹具 home 与四个 dev 钩子由各档自带，
# 好让 06 那一档能干净地"不注入夹具"。后面的 "$@" 会覆盖同名变量（MM_APPEARANCE/MM_WINDOW_SIZE 靠这点做逐档特例）。
shot() {
  local name=$1 settle=$2; shift 2
  # ONLY=04 ./Scripts/p68-dev-capture.sh … 只重拍一档：七档各起一次应用，改一处文案就全跑太慢。
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  # 归因头：这份 .log 要自己说清本档注入了什么——06 真机档不带夹具，
  # 没有这一行就分不出"没注入"和"忘了注入"。
  print -r -- "# p68-dev-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=cleaner MM_OPEN_TAB=dev ${SIZE:+MM_WINDOW_SIZE=$SIZE }$*" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=cleaner MM_OPEN_TAB=dev \
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

# 01 夹具默认态：分组全折叠、一枚没勾（已选 0 处、主按钮禁用）。
shot 01-fixture-default "$SETTLE" MM_PURGE_FIXTURE_HOME="$FIXTURE"
# 02 展开 + 批量勾选：组头/行全展开，MM_DEV_SELECT=untouched 把"证据成立且 7 天没碰"的行勾上。
shot 02-fixture-expanded-selected "$SETTLE" MM_PURGE_FIXTURE_HOME="$FIXTURE" \
     MM_DEV_EXPAND=1 MM_DEV_SELECT=untouched
# 03 滚到底看四态：safe/自述为缓存/warn/受保护 四支徽标 + 最强证据行（.gradle CACHEDIR.TAG）+ 读不到的行（locked/build 体积 —）+ 底部说明，全在后半段。
shot 03-fixture-bottom-states "$SETTLE" MM_PURGE_FIXTURE_HOME="$FIXTURE" \
     MM_DEV_EXPAND=1 MM_DEV_SELECT=untouched MM_DEV_SCROLL=end
# 04 确认面板：在 03 那一态上叠 MM_DEV_CONFIRM 弹 sheet。sheet 要非空清单，所以必须先有 MM_DEV_SELECT。
#     面板内容随 model.report/selectedPaths 落地自己重算，等够 SETTLE 就是带行的那一态（§9.3 记的窗口）。
shot 04-fixture-confirm-sheet "$SETTLE" MM_PURGE_FIXTURE_HOME="$FIXTURE" \
     MM_DEV_EXPAND=1 MM_DEV_SELECT=untouched MM_DEV_SCROLL=end MM_DEV_CONFIRM=1
# 05 深色档：与 03 同一态，只把外观换成 dark（最后的 MM_APPEARANCE 覆盖公共注入）。
shot 05-fixture-dark "$SETTLE" MM_PURGE_FIXTURE_HOME="$FIXTURE" \
     MM_DEV_EXPAND=1 MM_DEV_SELECT=untouched MM_DEV_SCROLL=end MM_APPEARANCE=dark
# 06 真机档：不注入夹具，扫本机真实开发目录。这一档内容随机器与时间变，与 p7-dev 的 06 天然不可比。
shot 06-real-machine "$REAL_SETTLE" MM_DEV_EXPAND=1 MM_DEV_SELECT=untouched
# 07 最小窗口（1000×700）：看窄窗下扫描根 chip 内部省略号截断、"另有 N 个"不丢、主按钮标题不被截尾。
shot 07-fixture-min-window "$SETTLE" MM_PURGE_FIXTURE_HOME="$FIXTURE" \
     MM_DEV_EXPAND=1 MM_DEV_SELECT=untouched MM_WINDOW_SIZE=1000x700
# 08 P26「最长副标题」档：把页头那句能长到的每一段都请出来——根预算压到 0.05 秒逼出截断根
#    （"N 个根没扫完"），再自动续扫 2 批逼出分批（"本清单由 2 批拼成"、"最近一批扫于"、"累计耗时"）。
#    为什么不带 MM_DEV_SELECT：这一档量的是页头放不放得下，勾选只会多一块面板。
#    这一档是 P26 逐屏截断审计（release-readiness.md §7.17）里开发产物页的最坏情况；
#    07 那一档的夹具默认态副标题只有 4 段，量不出最坏。
shot 08-fixture-min-window-all-disclosures "$SETTLE" MM_PURGE_FIXTURE_HOME="$FIXTURE" \
     MM_DEV_ROOT_BUDGET_SECONDS=0.05 MM_DEV_AUTO_CONTINUE=2 MM_WINDOW_SIZE=1000x600

print -r -- "→ $OUT"
print -r -- "转 jpeg（与 p7-dev 同格式，可选）：for f in $OUT/*.png; do sips -s format jpeg -Z 1400 \"\$f\" --out \"\${f%.png}.jpg\" >/dev/null; done"
