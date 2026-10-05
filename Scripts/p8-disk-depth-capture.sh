#!/bin/zsh
# P8「磁盘详情四宫格那一格不许把没量到写成 0」取证。
#
# 修的是什么：那一格原来挂的标签是「文件数」，值却是 `children.count`（直接子项数），
# 而设计稿写的是递归文件数（`fidelity-disk.md` I4）；更糟的是深度上限处
# `MMDisk.swift` 造的是 `children: []` + `descendantsMeasured: false` 的封顶节点，
# 照原样显示就成了对着一个大目录说「文件数 0」。现在标签是「子项」，
# 判定抽在 `DiskInspectorText.childCount(of:enumerated:)` 里，封顶那一档明说「未枚举」。
#
# 三档都能零点击拍到：
#   扫哪棵树 = MM_DISK_SCAN=<深夹具根>（钩子只认 /tmp，越界整条忽略并点名）
#   选哪一个 = MM_DISK_SELECT=<逗号分隔绝对路径>（取第一条，展开它所在那一层并选中）
# 全程不碰鼠标：合成点击会逃逸到用户的其它应用（老规矩）。
#
#   ./Scripts/p8-disk-depth-capture.sh <app 路径> <输出目录> [light|dark]
#   ONLY=01 ./Scripts/p8-disk-depth-capture.sh …   # 只重拍封顶那一档
#   SIZE=1100x800 …  KEEP_FIXTURE=1 …              # 换窗口尺寸 / 不重建夹具
#   KEEP_FIXTURE=1 …                                # 不重建夹具（默认每次重建）
#
# 哨兵判据（画面上必须出现的）：
#   01 选中 L21（depth=20 那一支造出来的封顶节点）→「占用」有数（deepSize 兜到了字节），
#      「子项」是**未枚举**，绝不能是 0；
#   02 选中 L01（正常量到的目录）→「子项」是一个真实的小数字（夹具里是 2：marker + L02），
#      证明 01 那句"未枚举"是"没枚举"而不是"这一格坏了"；
#   03 选中一个文件 →「子项」是 —（文件没有子项，也不该写成 0）。
# 日志里那一行 `MM_DISK_SELECT 已选中 …（体积）` 是这一族的钩子凭据：
# 数字与照片上的「占用」对上才算这档拍成了。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
ROOT=/tmp/macmaster-disk-depth-fixture
CAPPED=$ROOT/L01/L02/L03/L04/L05/L06/L07/L08/L09/L10/L11/L12/L13/L14/L15/L16/L17/L18/L19/L20/L21
SETTLE=${SETTLE:-12}
# 窗口尺寸必须自己写死：这一屏要读的是右侧详情面板，而 App 会恢复上次退出的 frame
# （第一次实跑恢复到 1000x652pt，四宫格被挤到窗口边缘，照片看着像"那一格没了"）。
SIZE=${SIZE:-1400x900}

if [[ -z ${KEEP_FIXTURE:-} ]]; then
  ./Scripts/disk-depth-fixture.sh >/dev/null
fi
[[ -d $CAPPED ]] || {
  print -u2 -- "夹具不完整：$CAPPED（先跑 ./Scripts/disk-depth-fixture.sh）"; exit 2; }

mkdir -p "$OUT"

# shot <文件名> <MM_DISK_SELECT 路径>
shot() {
  local name=$1 select=$2
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  print -r -- "# p8-disk-depth-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP  fixture=$ROOT" >"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=disk MM_WINDOW_SIZE=$SIZE MM_DISK_SCAN=$ROOT MM_DISK_SELECT=$select" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=disk MM_WINDOW_SIZE="$SIZE" \
      MM_DISK_SCAN="$ROOT" MM_DISK_SELECT="$select" \
      "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
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
  # 钩子有没有真选中，读日志里那一行凭据；没有它，照片上的空面板与"钩子没跑"长得一样。
  if grep -q "MM_DISK_SELECT 已选中" "$log"; then
    print -r -- "# hook: $(grep -m1 'MM_DISK_SELECT 已选中' "$log")" >>"$log"
  else
    print -r -- "# hook: 没有『已选中』回执——详情面板可能是空的，这张照片不能用" >>"$log"
  fi
  print -r -- "# windowid=$wid pid=$pid settle=${SETTLE}s" >>"$log"
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid"
}

# 01 封顶节点：占用有数、子项「未枚举」。
shot 01-capped-node "$CAPPED"
# 02 正常量到的目录（根的直接子女，不会触发额外下钻）：子项是个真实数字。
shot 02-measured-dir "$ROOT/L01"
# 03 文件：子项 —。
shot 03-file-node "$ROOT/L01/marker.bin"

print -r -- "→ $OUT"
print -r -- "清理夹具：./Scripts/disk-depth-fixture.sh --clean"
