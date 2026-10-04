#!/bin/zsh
# P6.6 取证：把挂了四天的三条 `⚠️待真机测量` 量掉（磁盘页 I9/I11 + 清理页 I9）。
#
# 为什么单独立一个脚本：这三条都不是"没有钩子"，是**没人拍过一张窗**。
#   · disk I11 面包屑栏高：实现 `.frame(height: 34)`(`MMDisk.swift:379`) vs 稿 `.crumbs` 26px(`screen.css:126`)
#   · disk I9  treemap 块内标签带高：`TreemapLayoutOptions.headerHeight = 14`
#                (`Packages/MMUI/Sources/MMUI/TreemapView.swift:116`，**共享包**)
#                vs 稿 `--cap: 20px`（而稿自己另把五个块内联覆写成 16px，三个数各说一遍）
#   · cleaner I9 分组右注 `.frame(maxWidth: 280)` + `.lineLimit(1)`(`MMCleaner.swift:543-546`)
#                会不会把最长那句截尾
# 前两条要**量**（沿一条竖线打色带，见脚本末尾的 pixel-probe 命令），第三条只要**读**（截尾会显 "…"）。
#
# 全程零合成点击；夹具只在 /tmp（`MM_DISK_SCAN` 拒绝别处，写错就拍成空态）。
#
#   ./Scripts/disk-fixture.sh                      # 先造夹具（175 MB，大小可核对）
#   ./Scripts/p66-layout-measure.sh <app> <outdir> [light|dark]
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
FIXTURE=/tmp/macmaster-disk-fixture

[[ -d $FIXTURE ]] || { print -u2 -- "缺夹具：先跑 ./Scripts/disk-fixture.sh"; exit 1; }
mkdir -p "$OUT"

shot() {
  local name=$1 settle=$2; shift 2
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  env MM_APPEARANCE="$APPEARANCE" "$@" "$APP/Contents/MacOS/MacMaster" >"$log" 2>&1 &
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
  # 顺手把窗口尺寸记进日志：@2x 截图量出来的像素要除以缩放才是 pt，
  # 不记这一行，下一轮就得拿像素当点数用。
  print -r -- "windowid=$wid" >>"$log"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid"
}

# 01 磁盘页首屏（扫描根 = 夹具）：顶层列表 + treemap + 面包屑，三样都在同一张里，量一次就够。
#    MM_DISK_DEPTH=3 让 treemap 长出子块——I9 问的正是**子块**的标签带高。
shot 01-disk-root 14 MM_OPEN_MODULE=disk MM_DISK_SCAN="$FIXTURE" MM_DISK_DEPTH=3
# 02 钻进两层（Library → Caches）：面包屑变成两级，看 34pt 那一栏装得下几级、会不会挤。
#    路径必须写成**夹具下的绝对路径**：MM_DISK_SELECT 只认 /tmp 开头的完整路径，
#    给相对段名（"Library,Caches"）会被那道越界 guard 整条忽略，照片就退回一级面包屑，
#    而日志里只有一行 stderr——不盯日志会当成"两级面包屑就是这样"。
#    顺序按 hook-ledger §5 那条教训：扫描根本身不写在第一个，否则钩子会一路选到 /tmp。
shot 02-disk-drill 14 MM_OPEN_MODULE=disk MM_DISK_SCAN="$FIXTURE" MM_DISK_DEPTH=3 \
  MM_DISK_SELECT="$FIXTURE/Library/Caches"
# 03 清理页分组行：`MM_EXPAND_CATEGORIES=1` 展开分类，分组头右侧那句 `risk.groupNote`
#    最长的是「可能包含登录态或未同步数据，默认不勾选」（19 个 CJK 字）。
shot 03-cleaner-group-notes 12 MM_OPEN_MODULE=cleaner MM_EXPAND_CATEGORIES=1
# 04 谨慎档分组头：I9 问的是**最长那句**会不会截尾，而它属于「需谨慎」分组
#    （`Risk.swift:33`「可能包含登录态或未同步数据，默认不勾选」，19 个 CJK 字）。
#    03 那张首屏只有「可安全清理」的 12 字短注，量不到，所以再拍一张：
#    `MM_CLEANER_FILTER` 直接把列表收到只剩谨慎档那一组，分组头就顶到首屏，不用滚动（也不许合成点击）。
shot 04-cleaner-caution-note 12 MM_OPEN_MODULE=cleaner MM_CLEANER_FILTER=浏览器

print -r -- "→ $OUT（$APPEARANCE）"
print -r -- "量法（@2x：像素 ÷ 2 = pt）："
print -r -- "  swift Scripts/pixel-probe.swift $OUT/01-disk-root.png scan x <某条竖线的 x> <y 起点> <y 终点>"
print -r -- "  swift Scripts/pixel-probe.swift $OUT/02-disk-drill.png scan x <面包屑栏内一条无字竖线> 150 300"
# ⚠️ `pixel-probe.swift` 的 scan 参数名是**反的**：`scan x` 固定 x、沿 y 走（竖着量），
#    `scan y` 固定 y、沿 x 走。第一次用会按字面写成 `scan y <x>`，参数超出图片高度时
#    一个像素都取不到，输出**空**且不报错——看着像"这一带没边界"，其实是没扫到东西。
#    量高一律用 `scan x`。
