#!/bin/zsh
# P21 取证：把「磁盘页风险标签 vs 删除闸门」的逐路径判定表落成一份可读的证据。
#
# 为什么这一档没有照片：磁盘页的扫描与选择钩子按红线只认 /tmp 下的夹具路径，
# 越界直接忽略整条钩子 —— 于是 `/etc/hosts`、`~/.ssh/config` 这些"标签从此不再给按钮"的行
# **没有任何钩子能拍到**。缺照片时证据只能来自代码本身：这条脚本把三个真源文件
# （Risk.swift / DeletionGuard.swift / DiskRisk.swift）连同探针一起编译，
# 让表格里的每一格都是那两个真函数的返回值，不抄逻辑、不手填。
#
# 唯一的机械改动：编译前用 sed 去掉 DiskRisk.swift 里那一行 `import MMCore`。
# 四个文件合成一个模块，同模块内才有内部可见性（`DiskRisk` 不是 public），
# 而那行 import 在合成模块里必然报"no such module"。**判定代码一个字都没动**，
# 日志头部把这件事写清楚了，重跑的人一眼能验（行数核对就写在下面）。
#
#   ./Scripts/p21-disk-risk-probe.sh              写 docs/verification/p21-disk-risk/risk-labels.log
#   ./Scripts/p21-disk-risk-probe.sh --stdout     只打终端，不写证据目录
#   OUT=… ./Scripts/p21-disk-risk-probe.sh        换输出目录
#
# 退出码：合同 1 违例（标签给按钮、字面闸门却拒）非零 —— 这条脚本可以当门禁跑。
set -e

cd "$(dirname "$0")/.."
TO_STDOUT=0
[[ "${1:-}" == "--stdout" ]] && TO_STDOUT=1
OUT=${OUT:-docs/verification/p21-disk-risk}

# 归因头（老规矩）：跑脚本的这棵树。工作区脏就加 -dirty，只看 commit 会把未提交的树读成已入库的树。
# 用 -uno：这条脚本自己正在往证据目录里写未跟踪的日志。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi

SCRATCH=$(mktemp -d /tmp/mm-p21-probe.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

SOURCE=Packages/MMDisk/Sources/MMDisk/DiskRisk.swift
ORIG_LINES=$(wc -l <"$SOURCE" | tr -d ' ')
# 合成一个模块：只剥掉那一行 import，其余逐字节原样。
sed '/^import MMCore$/d' "$SOURCE" >"$SCRATCH/DiskRisk.swift"
COPY_LINES=$(wc -l <"$SCRATCH/DiskRisk.swift" | tr -d ' ')
if [[ $COPY_LINES -ne $(( ORIG_LINES - 1 )) ]]; then
  print -u2 -- "⚠ 剥 import 之后行数不对：原 $ORIG_LINES 行 / 现 $COPY_LINES 行（应当只差 1 行）"
  exit 2
fi

swiftc -parse-as-library -o "$SCRATCH/probe" \
  Packages/MMCore/Sources/MMCore/Risk.swift \
  Packages/MMCore/Sources/MMCore/DeletionGuard.swift \
  "$SCRATCH/DiskRisk.swift" \
  Scripts/p21-disk-risk-probe.swift 2>"$SCRATCH/compile.log" || {
    print -u2 -- "⚠ 编译探针失败："
    cat "$SCRATCH/compile.log"
    exit 3
  }

emit() {
  print -r -- "# p21-disk-risk-probe.sh  $(date '+%Y-%m-%d %H:%M:%S %z')"
  print -r -- "# repo: $repoTag  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
  print -r -- "# 编译器: $(swiftc --version 2>/dev/null | head -1)"
  print -r -- "# 参与编译的真源文件: Packages/MMCore/Sources/MMCore/{Risk,DeletionGuard}.swift"
  print -r -- "#   + Packages/MMDisk/Sources/MMDisk/DiskRisk.swift（$ORIG_LINES 行，唯一机械改动是去掉它那行"
  print -r -- "#   import MMCore → $COPY_LINES 行）+ Scripts/p21-disk-risk-probe.swift"
  print -r -- "# 表格里每一格都是 DiskRisk.risk(of:) / DeletionGuard.literalRejection(...) / DeletionGuard.rejection(...)"
  print -r -- "# 的原样返回值；闸门理由也是原文，没有手填文案。"
  print -r -- ""
  "$SCRATCH/probe"
}

if [[ $TO_STDOUT -eq 1 ]]; then
  emit
  exit $?
fi

mkdir -p "$OUT"
emit >"$OUT/risk-labels.log"
print -r -- "✅ $OUT/risk-labels.log"
tail -5 "$OUT/risk-labels.log"
