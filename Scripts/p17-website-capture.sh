#!/bin/zsh
# P17c 落地页四张截图：夹具档实拍。
#
# 为什么这一支脚本单独存在（而不是复用 p68/p62b 那些取证脚本）：
# 那些照片拍的是**这台机器**——真实卷名与占用、真实登录项、真实密钥目录的 mtime，
# 它们作为验收证据留在 docs/verification/ 里是有意为之，但同一批图放进一个给陌生人看的
# 落地页，就是拿用户数据当宣传图（判据与逐屏的钩子清单见 docs/analysis/website-audit.md §3）。
# 所以这四个表面只有一个来源：**夹具钩子 + 合成条目**。任何一个 surface 拿不到夹具档，
# 这一档就不拍，而不是退回真机数据拍一张"看着没问题"的图。
#
# 三档里有两档连 /tmp 都不读：`MM_MONITOR_FIXTURE`（纯数值注入，进程名一律 com.example.*、
# 温度键一律 TZZ*）与 `MM_GUARDIAN_*FIXTURE`（合成条目）；另两档读 /tmp 夹具目录
# （purge 与 disk 那两棵树，由本脚本按需重建）。
#
# 全程零合成点击：合成点击/滚轮会逃逸到用户的其它应用（全站取证口径）。
# 抓窗口一律带 --pid，只 kill 自己起的那个进程。
#
#   ./Scripts/p17-website-capture.sh <app 路径> <输出目录> [dark|light] [宽x高]
#   ./Scripts/p17-website-capture.sh /tmp/mm-app-p17/MacMaster.app docs/website/assets
#   ONLY=03 ./Scripts/p17-website-capture.sh …   只重拍监控那一屏
#   KEEP_FIXTURE=1 …                              不重建 /tmp 夹具（默认每次重建）
#   EVIDENCE=docs/verification/p17-website …      归因日志落点（默认就是这个）
#
# 判据不是"四张图各自长得不一样"，而是**画面上必须出现真实机器生产不出的值**：
#   01 清理 = `/tmp/macmaster-purge-fixture` 下的假项目；
#   02 磁盘 = `/tmp/macmaster-disk-fixture` 与 `com.example.app`；
#   03 监控 = `com.example.*` 进程名 + `TZZ*` 温度键 + 固定时刻「2023-11-15」；
#   04 守护 = `com.example.*` 登录项与授权行。
# 这四条由脚本自己 grep 一遍照片对应的 stderr/日志做不到（画面是位图），所以脚本把
# 注入的钩子逐个写进归因头，人眼对着照片核那四个哨兵；照片与日志同批产出、同一时刻。
set -e

cd "$(dirname "$0")/.."
# 归因头要能说出自己是哪棵树（-uno：证据目录里自己写出的未跟踪文件不算脏活）。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-dark}
SIZE=${4:-1280x800}
EVIDENCE=${EVIDENCE:-docs/verification/p17-website}
PURGE_FIXTURE=/tmp/macmaster-purge-fixture
# 同源检查（P22 之后立的规矩，配方见 mm-provenance.sh）：落地页那四张是要发出去的，
# 拍在一份"界面上还没有那一屏"的产物上，比修没修好那一屏更难查。
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，四张都不出："
  mm_provenance_line >&2
  exit 4
fi
DISK_FIXTURE=/tmp/macmaster-disk-fixture
LOG="$EVIDENCE/capture.log"
# 8 秒是 p68-dev 对夹具档实测过的落位时间（夹具扫描是毫秒级，全花在 SwiftUI 排版上）；
# 磁盘那棵 175 MB 的树要走到 Treemap 布局落定，给到 12 秒。
SETTLE=${SETTLE:-8}
DISK_SETTLE=${DISK_SETTLE:-12}

[[ -x "$APP/Contents/MacOS/MacMaster" ]] || {
  print -u2 -- "找不到可执行文件：$APP/Contents/MacOS/MacMaster"; exit 2; }

if [[ -z ${KEEP_FIXTURE:-} ]]; then
  ./Scripts/purge-fixture.sh >/dev/null
  ./Scripts/disk-fixture.sh >/dev/null
fi
for d in "$PURGE_FIXTURE" "$DISK_FIXTURE"; do
  [[ -d $d ]] || { print -u2 -- "夹具不存在：$d（去掉 KEEP_FIXTURE 让脚本自己重建）"; exit 2; }
done
mkdir -p "$OUT" "$EVIDENCE"

{
  print -r -- "# p17-website-capture.sh 落地页四屏夹具档实拍"
  print -r -- "# date: $(date '+%Y-%m-%d %H:%M:%S %z')"
  print -r -- "# command: ./Scripts/p17-website-capture.sh $APP $OUT $APPEARANCE $SIZE"
  print -r -- "# repo: $repoTag branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
  local ver bld gcommit
  ver=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 未知)
  bld=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null || echo 未知)
  gcommit=$(/usr/libexec/PlistBuddy -c 'Print :MMGitCommit' "$APP/Contents/Info.plist" 2>/dev/null || echo 未知)
  print -r -- "# app: $ver ($bld)"
  # `# repo:` 是跑这条脚本的那棵树，`# app-repo:` 是被拍的那份二进制打包时的那棵树，改脚本重跑旧产物时两者不同。
  print -r -- "# app-repo: $gcommit"
  mm_provenance_line
  print -r -- "# shape under test: 落地页 §界面预览 那四个截图位（改前是四个 .screenshot-placeholder 的 div、全页 <img> 为 0）"
  print -r -- "# expected: 四张图的清单与读数来自夹具钩子；画面上出现 /tmp 夹具路径或 com.example.*/TZZ* 合成条目，"
  print -r -- "            不出现真实登录项、真实密钥目录 mtime。**但有三个值夹具顶替不了，必然带真机状态**："
  print -r -- "            侧栏卷名+剩余百分比（MainWindow.swift:143-168）、侧栏「系统清理」那格可回收体积"
  print -r -- "            （MainWindow.swift:107-111，读概览那次真实扫描）、磁盘页「卷可用」badge（MMDisk.swift:376）。"
  print -r -- "            这三处不做隐藏、也不裁图，改成在落地页 §界面预览 那句话里明说——见 website-audit.md §3。"
  print -r -- "# observed: 见下面每档的 env 行与哨兵核对结果（人工对着照片打勾，脚本只负责把注入项如实写下来）"
  print -r -- "# restore: 本脚本不写用户任何状态；夹具目录在 /tmp，需要时用 --clean 删"
} >"$LOG"

# shot <档名> <等待秒> <环境变量...>
# 公共部分（外观/尺寸）在这里统一注入；各档自带的 MM_* 决定画面上是哪一屏、是哪批夹具。
shot() {
  local name=$1 settle=$2; shift 2
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  print -r -- "# ---- $name ----" >>"$LOG"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_WINDOW_SIZE=$SIZE $*" >>"$LOG"
  env MM_APPEARANCE="$APPEARANCE" MM_WINDOW_SIZE="$SIZE" "$@" \
      "$APP/Contents/MacOS/MacMaster" >>"$LOG" 2>&1 &
  local pid=$!
  sleep "$settle"
  local wid
  wid=$(swift Scripts/window-ids.swift --pid "$pid" 2>/dev/null \
        | sed -n 's/^windowid=\([0-9]*\).*/\1/p' | head -1)
  if [[ -z "$wid" ]]; then
    print -u2 -- "⚠ $name：pid=$pid 没有可见窗口（不产出空照片）"
    print -r -- "# result: $name 失败——pid=$pid 没有窗口，这一档没有照片" >>"$LOG"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "# result: $name windowid=$wid pid=$pid settle=${settle}s file=$OUT/$name.png" >>"$LOG"
  print -r -- "✅ $name windowid=$wid $(du -h "$OUT/$name.png" | cut -f1)"
}

# 01 清理（开发产物页）：MM_PURGE_FIXTURE_HOME 只认 /tmp，越界整块忽略；
#    MM_DEV_EXPAND + MM_DEV_SELECT=untouched 让画面落在"有行、有勾选、有合计"那一态——
#    落地页那句"删除前要确认一次"要有对应的画面，全折叠的空清单证明不了任何事。
shot 01-cleaner "$SETTLE" \
     MM_OPEN_MODULE=cleaner MM_OPEN_TAB=dev \
     MM_PURGE_FIXTURE_HOME="$PURGE_FIXTURE" MM_DEV_EXPAND=1 MM_DEV_SELECT=untouched
# 02 磁盘：Treemap 是默认视图，扫的是 disk-fixture 那棵 175 MB 的假树（大小拉开一个数量级，
#    块面积差才看得出来）。不带 MM_DISK_SELECT——选中某一层会把右侧详情面板挤进来，
#    落地页这一格要的是"整张 Treemap"。
shot 02-disk "$DISK_SETTLE" \
     MM_OPEN_MODULE=disk MM_DISK_SCAN="$DISK_FIXTURE"
# 03 监控：populated 是确定数值底座，processes 给 com.example.* 进程名，sensors 给 TZZ* 键。
#    三个档逗号叠加；夹具态下 `menuBar.enable()` 不会被调用，后台采样不会把夹具覆盖掉。
shot 03-monitor "$SETTLE" \
     MM_OPEN_MODULE=monitor MM_MONITOR_FIXTURE=populated,processes,sensors
# 04 守护：四张卡全用夹具（占用图标环 camera=inuse,mic=idle；TCC 与登录项 com.example.*；
#    改动时间卡 rows）。这一屏真机态里有真实登录项，是最不能外流的一屏。
shot 04-guardian "$SETTLE" \
     MM_OPEN_MODULE=guardian \
     MM_GUARDIAN_FIXTURE=camera=inuse,mic=idle \
     MM_TCC_FIXTURE=rows MM_GUARDIAN_LOGIN_FIXTURE=rows MM_GUARDIAN_ACTIVITY_FIXTURE=rows

print -r -- "# ---- 产出清点 ----" >>"$LOG"
for f in "$OUT"/0*.png; do
  [[ -f $f ]] && print -r -- "# file: $(basename "$f") $(du -h "$f" | cut -f1) $(sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null | awk '/pixel/{printf "%s ", $2}')" >>"$LOG"
done
print -r -- "→ 照片 $OUT，归因日志 $LOG"
