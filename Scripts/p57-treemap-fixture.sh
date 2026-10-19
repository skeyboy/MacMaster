#!/bin/zsh
# P57 双语取证的 treemap 夹具：两棵"子项比 cap 多"的浅树，专门把两块合并块逼出来。
#
# 为什么需要单独一棵树而不是复用 disk-fixture.sh：那一棵只有 8 个分支，
# 而这两块块的**出现条件**是数量，不是大小——
#   MMUI 布局层的 cap：`TreemapLayoutOptions.childCap(at: 0)` = maxChildren = 96，
#     第 97 个子块起并进一块，名字由 MMUI 自己生成（P57 起走 `ui.treemap.others`，跟语言）。
#   MMDisk 的渲染窗：`renderWindow` = 200，第 201 个子项起并进 `__remaining__`，
#     名字由模块页自己拼（现在仍是中文，P57 把它登记成中英混排的已知面）。
# 两块的判据都改成显式标志之后，同一张图里能同时拍到两种口径——所以 250 那一棵是必需的。
#
# 只准放 /tmp：MMDisk 的 MM_DISK_SCAN 拒绝 /tmp 之外的路径（钩子自己会忽略并点名）。
# 每个子项一个 4 KB 小文件：APFS 上实际占用就是 4 KB，400 个文件不到 2 MB，
# 而等大小正是这里要的——合并块 = 54/150（36%）与 50/250（20%）的整块面积，
# 块名才画得出来；大小拉开一个数量级反而会把合并块挤成一条窄片。
#
# 用法：./Scripts/p57-treemap-fixture.sh          # 建两棵，打印两个根
#       ./Scripts/p57-treemap-fixture.sh --clean
set -e
ROOT=/tmp/macmaster-p57-treemap-fixture
OVER_CAP=$ROOT/wide-150        # 97..150 → 只有 MMUI 那块
OVER_WINDOW=$ROOT/wide-250     # 201..250 → MMUI 与 MMDisk 两块同框

if [[ "${1:-}" == "--clean" ]]; then
  rm -rf "$ROOT"
  print -r -- "已删除 $ROOT"
  exit 0
fi

rm -rf "$ROOT"
build() {
  local dir=$1 count=$2 i name
  mkdir -p "$dir"
  # 用 seq 而不是 `{1..$count}`：zsh 的 Brace 展开早于参数展开，后者会原样留成字符串。
  for i in $(seq 1 $count); do
    name="$dir/branch-$(printf '%03d' $i)"
    mkdir -p "$name"
    mkfile 4k "$name/blob.bin"
  done
}
build "$OVER_CAP" 150
build "$OVER_WINDOW" 250

print -r -- "$OVER_CAP   子项=$(ls "$OVER_CAP" | wc -l | tr -d ' ')"
print -r -- "$OVER_WINDOW   子项=$(ls "$OVER_WINDOW" | wc -l | tr -d ' ')"
du -sh "$ROOT"
