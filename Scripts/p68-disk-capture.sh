#!/bin/zsh
# P6.8「磁盘页删除面板四档」取证：把 docs/verification/p5-disk-permanent/ 那四张手工照片变成可重跑脚本。
#
# 背景：那四张（trash / perm / perm-acked / toast）是真的，但仓库里只留下一段手写命令
# （`fidelity-disk.md` §8 末），没有任何脚本会再拍一遍——改这块面板的人拿不到回归对照。
# 照片改写到 docs/verification/p68-disk/，绝不覆盖 p5-disk-permanent（那是已提交证据）。
#
# 为什么四档都能零点击：这一屏要"动手"的状态全有钩子替身（`MMDisk.swift` 的 `applySelectionHook`）——
#   扫哪棵树 = MM_DISK_SCAN=<夹具根>（只认 /tmp，越界整条忽略并点名）
#   标记哪几项 = MM_DISK_SELECT=<逗号分隔绝对路径>（最多取前三条，且只重放一次）
#   面板弹哪一块 = MM_SHOW_CONFIRM=1（回收/裁决面板）→ MM_SHOW_PERMANENT=1|acked（换到永久删除那块，顺手打勾）
#   回执条 = MM_SHOW_TOAST=permanent（只画"已永久删除"那条，一个字节都不删）
# 全程不碰鼠标：合成点击会逃逸到用户的其它应用（老规矩）。
#
# 这一族的"钩子凭据"是日志里那四行**带数字的成功回执**（P6.7 补的）：
#   MM_DISK_SELECT 已选中 …（50.3 MB）
#   MM_SHOW_CONFIRM 已打开确认面板（3 个标记）
#   MM_SHOW_PERMANENT=acked 已把镜头换到永久删除面板（勾选项 已打），没有改动任何文件
#   MM_SHOW_TOAST=permanent 已画出「已永久删除」回执条（1 项 · 50.3 MB），没有删除任何东西
# 数字与照片对得上才算这档拍成了；只有一句"我开了面板"不算。
#
#   ./Scripts/p68-disk-capture.sh <app 路径> <输出目录> [light|dark] [宽x高]
#   ./Scripts/p68-disk-capture.sh /tmp/mm-app-p68disk/MacMaster.app docs/verification/p68-disk
#   ONLY=03 ./Scripts/p68-disk-capture.sh … 只重拍 03 那一档
#   KEEP_FIXTURE=1 ./Scripts/p68-disk-capture.sh … 不重建夹具（默认每次重建）
#
# 夹具大小是固定的（`Scripts/disk-fixture.sh`：Downloads 48m / Movies 8m / 根 175 MB），
# 所以面板里的数字是**可预期**的——这是这一族照片的哨兵：真机上不会有
# `/tmp/macmaster-disk-fixture/Downloads/dmg-image.dmg` 这条路径，也不会有刚好这些数。
# 抓完即杀，且只 kill 自己起的 pid。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SIZE=${4:-}
# 归因头（P18/P19 立的规矩，这一族之前漏了）：日志得说自己跑在哪棵树上、被测产物出自哪棵树。
# 用 -uno：本脚本正往证据目录里写未跟踪的 .log/.png，算进脏活就永远是 -dirty。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
# 产物那棵树由 `make-app.sh` 打进 Info.plist（P19a）；读不到就写"无"——
# 旧产物没这一格，硬编一个 commit 上去等于伪造出处。
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)
FIXTURE=/tmp/macmaster-disk-fixture
SETTLE=${SETTLE:-10}
# 04 那一档单独用更短的等待：回执条自带 10 秒倒计时（`permanentSeconds = 10`，每秒减一），
# 按通用 10 秒去拍正好卡在条上（实测拍到的是「1s」，机器稍慢一点就什么都没了）。
TOAST_SETTLE=${TOAST_SETTLE:-5}

# 夹具每次重建：`disk-fixture.sh` 开头就 `rm -rf $ROOT`，重跑是幂等的。
# 不重建会拍到上一棵的大小——那没坏，但日志里的"3 个标记 · 58.7 MB"与照片上的数就成了两次运行的和。
if [[ -z ${KEEP_FIXTURE:-} ]]; then
  ./Scripts/disk-fixture.sh >/dev/null
fi
[[ -d $FIXTURE/Downloads && -d $FIXTURE/Movies ]] || {
  print -u2 -- "夹具不完整：$FIXTURE（先跑 ./Scripts/disk-fixture.sh）"; exit 2; }

# 顺序是踩出来的（`hook-ledger.md` §5 末）：`MM_DISK_SELECT` 按逗号逐个往下钻，
# 把扫描根本身写在第一个会一路选到 /tmp，既暴露无关目录又让 selected 变 nil，
# 于是"借选中项数字摆一拍"的吐司支路整条哑掉。所以根放最后。
SEL="$FIXTURE/Downloads,$FIXTURE/Movies,$FIXTURE"

mkdir -p "$OUT"

# shot <文件名> <等待秒> <环境变量...>
shot() {
  local name=$1 settle=$2; shift 2
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  # 归因头：日志得自己说清这张是拿哪些变量拍的。这一族的钩子有先后牵制
  # （TOAST=permanent 会自己 return，永远走不到 CONFIRM），没这一行事后只能靠猜。
  print -r -- "# p68-disk-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP  fixture=$FIXTURE" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=disk ${SIZE:+MM_WINDOW_SIZE=$SIZE }$*" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=disk \
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

base=(MM_DISK_SCAN="$FIXTURE" MM_DISK_SELECT="$SEL")

# 01 回收/裁决面板：三条标记都在里面，顶部给"回收多少 · 清空废纸篓后卷可用怎么变"。
shot 01-trash-confirm "$SETTLE" $base MM_SHOW_CONFIRM=1
# 02 永久删除面板（未勾选）：MM_SHOW_PERMANENT 有值即换面板，值不是 acked 就不打勾——
#    这一档要拍的就是"按钮灰着、点不动"那一态。
shot 02-perm-unacked "$SETTLE" $base MM_SHOW_CONFIRM=1 MM_SHOW_PERMANENT=1
# 03 同一块面板勾上之后：按钮变红亮。consent 是单次会话内的，重开归零。
shot 03-perm-acked "$SETTLE" $base MM_SHOW_CONFIRM=1 MM_SHOW_PERMANENT=acked
# 04 「已永久删除」回执条：橙色三角、没有撤回按钮、倒计时 10 秒。
#    这一档**不带** MM_SHOW_CONFIRM：那条支路自己 return，面板不会盖住吐司。
shot 04-toast-permanent "$TOAST_SETTLE" $base MM_SHOW_TOAST=permanent

print -r -- "→ $OUT"
print -r -- "转 jpeg（与 p5-disk-permanent 同格式，可选）：for f in $OUT/*.png; do sips -s format jpeg -Z 1400 \"\$f\" --out \"\${f%.png}.jpg\" >/dev/null; done"
