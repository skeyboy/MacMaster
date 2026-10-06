#!/bin/zsh
# P22 取证：磁盘页「未纳入 N 个受保护目录」徽章数的到底是整棵树还是只有根目录那一层。
#
# 背景：扫描在**每一层**都按名字跳过 `protectedNames` 里的目录，而这份披露曾经只数
# 根目录的直接子项。真机上 `~/Pictures/Photos Library.photoslibrary` 在第二层，
# 于是徽章上那个 N 是少报的——而少报的那块在画面上就是一片没有解释的空白。
# 修法是 `ProtectedSkipLedger`：跳过一处记一处，路径相对被扫的根。
#
# 为什么这一族要新夹具：`disk-fixture.sh` 那棵哨兵树只在根目录放了 `Library`，
# 旧口径和新口径在它上面都报"未纳入 1 个"，照片完全一样，改动拍不出差别。
# 新夹具 `disk-protected-fixture.sh` 把受保护目录放在第一、第二、第三层各一处。
#
# 为什么两档都零点击：这一屏只要"扫哪棵树"就能进要的状态（`MM_DISK_SCAN=<夹具根>`，
# 钩子只认 /tmp），徽章是扫描结果的一部分，不需要选中、不需要面板。
# 全程不碰鼠标：合成点击会逃逸到用户的其它应用（老规矩）。
#
# 判据（照片上的徽章文字；`MM_DISK_SCAN` 成功时不打印任何东西，所以凭证就是照片）：
#   01 扫夹具根   → 未纳入 3 个受保护目录（改动前是 1 个）
#   02 换根到 Documents → 未纳入 1 个受保护目录（只有 Work/Library 这一处；
#      上一档里的 Library 不在这棵树里，不该跟着换根跑过来）
# 02 那一档同时钉住"数字是相对当前扫描根"的口径：它不是把上一次扫描的账本复读一遍。
#
# hover 浮层里那三条相对路径照片拍不到（原生 tooltip 不进截图），
# 字符串形态的证据在单测里：`DiskScannerHierarchyTests.testNestedProtectedSkipIsDisclosed`。
#
#   ./Scripts/p22-disk-skip-capture.sh <app 路径> <输出目录> [light|dark] [宽x高]
#   ./Scripts/p22-disk-skip-capture.sh /tmp/mm-app-p22/MacMaster.app docs/verification/p22-disk-skip
#   ONLY=02 …只重拍第二档；KEEP_FIXTURE=1 …不重建夹具
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SIZE=${4:-}

# 归因头：日志得说自己跑在哪棵树上、被测产物出自哪棵树。
# 用 -uno：本脚本正往证据目录里写未跟踪的 .log/.png，算进脏活就永远是 -dirty。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)

FIXTURE=/tmp/macmaster-disk-protected-fixture
SETTLE=${SETTLE:-10}

if [[ -z ${KEEP_FIXTURE:-} ]]; then
  ./Scripts/disk-protected-fixture.sh >/dev/null
fi
# 夹具不完整时照片会拍成"少了某一处"的假数——先点名再拍。
for d in "$FIXTURE/Library" "$FIXTURE/Pictures/Photos Library.photoslibrary" \
         "$FIXTURE/Documents/Work/Library"; do
  [[ -d $d ]] || { print -u2 -- "夹具不完整：缺 $d"; exit 2; }
done

mkdir -p "$OUT"

# shot <文件名> <扫描根> [额外环境变量...]
shot() {
  local name=$1 scan=$2; shift 2
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  print -r -- "# p22-disk-skip-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=disk MM_DISK_SCAN=$scan ${SIZE:+MM_WINDOW_SIZE=$SIZE }$*" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=disk MM_DISK_SCAN="$scan" \
      ${SIZE:+MM_WINDOW_SIZE="$SIZE"} "$@" "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  local pid=$!
  sleep "$SETTLE"
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
  # MM_DISK_SCAN 成功时什么都不打印（只有越界才写 stderr），所以照片本身就是凭证。
  # 这里反着查一次：出现"忽略该钩子"说明这一张拍的是真机目录，不是夹具——那这张要作废。
  if grep -q "忽略该钩子" "$log"; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    print -u2 -- "⚠ $name：钩子被忽略（扫描根不在 /tmp 之下），这一张不是夹具照片"
    exit 3
  fi
  print -r -- "# 期望徽章：见脚本头「判据」一节（夹具里三处受保护目录分别在第 1/2/3 层）" >>"$log"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid scan=$scan"
}

shot 01-skip-badge "$FIXTURE"
shot 02-skip-subroot "$FIXTURE/Documents"

print -r -- "→ $OUT"
print -r -- "期望：01 徽章「未纳入 3 个受保护目录」/ 02 徽章「未纳入 1 个受保护目录」"
