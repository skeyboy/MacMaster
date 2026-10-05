#!/bin/zsh
# P6.8「废纸篓监听两档」取证：把 docs/verification/p1.5-trash/ 那两张 P1.5 手工照片变成可重跑脚本。
#
# 背景：p1.5-trash 那两张是真的，但仓库里只有造夹具的 Scripts/trash-fixture.sh，
# 没有任何脚本会再拍一遍。这一轮补上重跑能力。照片改写到 docs/verification/p68-trash/，
# 绝不覆盖 p1.5-trash（那是已提交证据）。
#
# 为什么两档都能零点击：
#   01 提示卡——"拖进废纸篓"这个动作由脚本自己 mv 完成（kqueue 收到的是真实目录改动，
#      探针已证明这类改动会送事件，见 apps-watch.md §3），残留扫描与勾选是
#      syncTrashNotice 自动跑的；钩子 MM_TRASH_FIXTURE_DIR/MM_TRASH_SCAN_HOME 只认 /tmp
#      （TrashWatcher.fixtureEnvironmentValue），越界会被拒绝并**点名改为监听真实废纸篓**
#      ——那一张就拍成真数据了，所以脚本先验夹具存在、且假废纸篓里没有残留条目。
#   02 无权限横幅——根本没有钩子可给：这一档要的就是"真 ~/.Trash 列不动"，
#      它是**真机档**，依赖运行机器没给这个构建授予「完全磁盘访问」。
#      （P6.7 之后这条退路自己会在日志里说清监听对象，见 fidelity-uninstaller.md §11。）
# 全程不碰鼠标：合成点击会逃逸到用户的其它应用（老规矩）。
#
#   ./Scripts/p68-trash-capture.sh <app 路径> <输出目录> [light|dark]
#   ./Scripts/p68-trash-capture.sh /tmp/mm-app-p68uninst/MacMaster.app docs/verification/p68-trash
#   ONLY=02 ./Scripts/p68-trash-capture.sh … 只重拍 02 那一档
#
# 夹具：./Scripts/trash-fixture.sh（现成的，本轮不新造）。01 会把 /tmp/mmstage/Foo.app
# 真的 mv 进 /tmp/mmtrash——重拍 01 前要重跑一次夹具，脚本会替你检查。
# 抓完即杀，且只 kill 自己起的 pid。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
# 旧照片就是深色档，默认沿用；传 light 可看浅色下的卡片排版。
APPEARANCE=${3:-dark}
TRASH=/tmp/mmtrash
HOME_FIX=/tmp/mmhome
STAGE=/tmp/mmstage
# 窗口出现 + TrashWatcher 建好基线（空目录）的时间。基线晚于 mv 就会把 Foo.app 当成
# "启动前就在"的历史条目，只入基线不报事件——这一档拍的是"刚拖进来"，不是"躺在里面"。
# 所以脚本先轮询到窗口 id、再留 2 秒给 onAppear 里的 startTrashWatching，才动手 mv。
BASELINE_BUFFER=${BASELINE_BUFFER:-2}
# mv 之后：400ms 事件合并 + 残留扫描 + 卡片同步——但**合并计时器排在 MainActor 上**，
# 页面还在逐应用测大小时它要排队（trash-watch-fda.md §1.4 记过的代价）。本机 41 个应用
# 实测：8 秒拍不到、约 45 秒（"大小已实测"之后）卡片与 4 项残留齐了。默认给 60 秒兜底，
# 机器空闲时卡片其实早就在了，多的等待只是白等，不会拍到别的态。
AFTER_MOVE=${AFTER_MOVE:-60}
SETTLE=${SETTLE:-8}

[[ -d $TRASH && -d $HOME_FIX ]] || { print -u2 -- "夹具不存在：先跑 ./Scripts/trash-fixture.sh"; exit 2; }
if [[ -z ${ONLY:-} || 01-trash-notice == ${ONLY}* ]]; then
  [[ -e $STAGE/Foo.app ]] || { print -u2 -- "01 需要 $STAGE/Foo.app：上一轮已 mv 进假废纸篓，重跑 ./Scripts/trash-fixture.sh 复位"; exit 2; }
  [[ -e $TRASH/Foo.app ]] && { print -u2 -- "01 的假废纸篓里已有 Foo.app（基线会吞掉这次拖入），重跑 ./Scripts/trash-fixture.sh 复位"; exit 2; }
fi
mkdir -p "$OUT"

# capture <文件名> <pid>：拿窗口 id → 截图 → 杀掉自己起的进程。没有可见窗口就报错不出空照片。
capture() {
  local name=$1 pid=$2
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
  print -r -- "✅ $name windowid=$wid"
}

# 01 提示卡：夹具废纸篓 + 夹具扫描 home。下半屏的应用列表是真机数据（旧照片同样如此），
#    哨兵在卡片与残留行里的 /tmp 路径，见 §12。
if [[ -z ${ONLY:-} || 01-trash-notice == ${ONLY}* ]]; then
  # 归因头同 p68-brew：这份 .log 要自己说清注入了哪两个夹具变量，
  # 而「不得出现『改为监听真实废纸篓』」这条判据只有在知道请求过夹具时才有意义。
  print -r -- "# p68-trash-capture.sh 01-trash-notice  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$OUT/01-trash-notice.log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=uninstaller MM_TRASH_FIXTURE_DIR=$TRASH MM_TRASH_SCAN_HOME=$HOME_FIX" >>"$OUT/01-trash-notice.log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=uninstaller \
      MM_TRASH_FIXTURE_DIR="$TRASH" MM_TRASH_SCAN_HOME="$HOME_FIX" \
      "$APP/Contents/MacOS/MacMaster" >>"$OUT/01-trash-notice.log" 2>&1 &
  pid=$!
  # 先等窗口真的出现（最多 30 秒）再计时基线缓冲：onAppear 里的 startTrashWatching
  # 要等窗口渲染才跑，固定 sleep 在冷启动慢的机器上会让 mv 抢在基线之前。
  wid=""
  for i in {1..30}; do
    sleep 1
    wid=$(swift Scripts/window-ids.swift --pid "$pid" 2>/dev/null \
          | sed -n 's/^windowid=\([0-9]*\).*/\1/p' | head -1)
    [[ -n $wid ]] && break
  done
  if [[ -z "$wid" ]]; then
    print -u2 -- "01：pid=$pid 30 秒内没有可见窗口，杀掉自己起的进程并中止"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    exit 1
  fi
  sleep "$BASELINE_BUFFER"
  if ! mv "$STAGE/Foo.app" "$TRASH/"; then
    print -u2 -- "01：mv $STAGE/Foo.app 失败，杀掉自己起的 pid=$pid 后中止"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    exit 1
  fi
  sleep "$AFTER_MOVE"
  capture 01-trash-notice "$pid"
fi

# 02 无权限横幅：刻意**不带任何夹具钩子**，监听的就是真实 ~/.Trash。
#    这一档没有夹具哨兵——它证明的是"权限被拒时页面说读不到，而不是谎报空的"。
#    如果这台机器已给本构建授了「完全磁盘访问」，横幅不会出现，照片会是一张正常页：
#    那要如实记为"此机器不可重跑"，不要为了凑照片注入假废纸篓（假目录永远读得动）。
if [[ -z ${ONLY:-} || 02-no-fda-banner == ${ONLY}* ]]; then
  print -r -- "# p68-trash-capture.sh 02-no-fda-banner  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$OUT/02-no-fda-banner.log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=uninstaller（真机档：刻意不注入任何夹具钩子）" >>"$OUT/02-no-fda-banner.log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=uninstaller \
      "$APP/Contents/MacOS/MacMaster" >>"$OUT/02-no-fda-banner.log" 2>&1 &
  pid=$!
  sleep "$SETTLE"
  capture 02-no-fda-banner "$pid"
fi

print -r -- "→ $OUT"
print -r -- "转 jpeg（与 p1.5-trash 同格式，可选）：for f in $OUT/*.png; do sips -s format jpeg -Z 1400 \"\$f\" --out \"\${f%.png}.jpg\" >/dev/null; done"
