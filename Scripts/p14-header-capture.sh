#!/bin/zsh
# P14 守护页页头副标题取证：四段副标题在三种窗口宽度下有没有被**中间省略**。
#
# 为什么要为一句副标题单开一支脚本：`MMPageHeader` 的副标题写的是
# `.lineLimit(1)` + `.truncationMode(.middle)`（见 `MMDesign.swift` 的 `MMPageHeader.body`，
# 按符号名找）。这两条是给"副标题常带完整路径"设计的，而 P14 把副标题从 3 段改成 4 段
# （D1：页头少说了界面上已经存在的第四张卡）。加长的结果不是换行、不是报错，
# 而是**画面上多一个省略号**——改完代码看单测全绿，看界面也认不出被切了哪一段。
# 所以这一支脚本的唯一判据是：**照片上那一行副标题里有没有「…」**。
#
# 哪一段被切掉最要紧，脚本里不猜：默认档（1100×700）与最窄档（1000×600，
# 也就是 `.frame(minWidth:minHeight:)` 的地板值）各拍一张，两档之间的差就是
# "这一句在用户能拖到的最小窗口里还剩不剩得下"。宽带档（1400×900）是控制组：
# 它要是也切，说明问题不在宽度。
#
#   ./Scripts/p14-header-capture.sh /tmp/mm-app-p14/MacMaster.app docs/verification/p14-header
#   ONLY=02 ./Scripts/p14-header-capture.sh …    只重拍窄窗那一档
#
# 三条硬规定沿用全站取证口径：① **一个顶数据的夹具钩子都不带**（副标题是静态文案，
# 一旦注入夹具，照片上的页头就不再是用户看到的那个页头）；② 零合成点击；
# ③ 只 kill 自己起的 pid，且抓窗口一律带 `--pid`。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
# 12 秒：这一屏四张卡全渲染，要等 launchd 快照 + TCC 读库 + 目录 stat 都落位。
# 页头本身不等这些（它是静态文案），但拍整页就不能只等首帧——否则照片会被"卡片还在骨架"
# 那一态挤乱，读宽度时误判。
SETTLE=${SETTLE:-12}

mkdir -p "$OUT"

# shot <档名> <等待秒> <环境变量...>
shot() {
  local name=$1; shift
  local settle=$1; shift
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  {
    print -r -- "# p14-header-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP"
    print -r -- "# env: MM_APPEARANCE=light MM_OPEN_MODULE=guardian ${(j: :)@}"
    print -r -- "# fixtures: 无（本轮拍的是静态页头文案，注入夹具就不是用户看到的那个页头）"
    print -r -- "# codesign: $(codesign -dvv "$APP" 2>&1 | grep -oE 'flags=0x[0-9a-f]+[a-z()]*' | head -1)"
    print -r -- "# 判据：照片上副标题那一行不许出现「…」。MM_WINDOW_SIZE 请求值会被"
    print -r -- "#       .frame(minWidth:minHeight:) 夹，生效值看应用自己回读的那一行（本 .log 末尾）"
  } >"$log"
  env MM_APPEARANCE=light MM_OPEN_MODULE=guardian "$@" \
      "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  local pid=$!
  print -r -- "# pid: $pid（由本脚本启动，也由本脚本 kill；不是用户的实例）" >>"$log"
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

# 01 默认尺寸（`.defaultSize` 1100×700，不给 MM_WINDOW_SIZE）
shot 01-default "$SETTLE"

# 02 地板尺寸：1000×600 是 `MacMasterApp` 里 minWidth/minHeight 的下限，
#    也是用户能拖到的最小窗口。这一档切了，就是"最小窗口里用户读不到全句"。
shot 02-min-window "$SETTLE" MM_WINDOW_SIZE=1000x600

# 03 宽带控制组：给足宽度还切，说明问题不在宽度（例如某段本身超长）。
#    屏高会把 900 往上夹，宽度这一维是真实的——只看副标题那一行，不看纵向。
shot 03-wide "$SETTLE" MM_WINDOW_SIZE=1400x900

print -r -- "→ $OUT"
