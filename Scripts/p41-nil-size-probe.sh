#!/bin/zsh
# P41 量尺：§4.2(b)「子树读不进 → 体积判 nil」这条口径变更，在本机到底会翻多少行。
#
# 判定一个不在这个脚本里：`Scripts/p41-nil-size-probe.swift` 与真源文件编成同一个模块，
# 行集合来自真 `ProjectArtifactScanner.scan()`，每条行的读不进目录来自真
# `FileTreeWalker.walkForArtifact`——两个文件都不改一行，唯一 required 的机械处理是
# 「合成一个模块」（`SubtreeWalk` 与 `walkForArtifact` 不是 public，分两个模块就只能抄逻辑，
# 而抄一遍的探针恰好是本仓库反复防的那种假账）。
#
# 这台机器是**真 home**：全程只读，不调用任何删除接口；但它会真的把开发产物页那套根走一遍，
# 所以耗时与页面点一次「重新扫描」同量级（预算由 `ProjectArtifactRules.default` 自己定）。
#
# 量出来的是 **(b) 的上界**（探针给的 deadline 比真扫描的逐候选预算宽裕）。日志头里写明了这一句。
#
#   ./Scripts/p41-nil-size-probe.sh              写 docs/verification/p41-nil-size/nil-size.log
#   ./Scripts/p41-nil-size-probe.sh --stdout     只打终端，不写证据目录
#   OUT=… ./Scripts/p41-nil-size-probe.sh        换输出目录
#
# 退出码恒为 0：这一支是量尺，不是门。真正的门是 p16。
set -e

cd "$(dirname "$0")/.."
TO_STDOUT=0
[[ "${1:-}" == "--stdout" ]] && TO_STDOUT=1
OUT=${OUT:-docs/verification/p41-nil-size}

repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi

MMS=Packages/MMFileScanner/Sources/MMFileScanner
typeset -a SOURCES=(
  "$MMS/FileTreeWalker.swift"
  "$MMS/ProjectArtifactScanner.swift"
  Scripts/p41-nil-size-probe.swift
)
for f in "${SOURCES[@]}"; do
  [[ -f $f ]] || { print -u2 -- "⚠ 编译清单里的文件不存在：$f（真源改名后要同步这一份清单）"; exit 2; }
done

SCRATCH=$(mktemp -d /tmp/mm-p41-nil-size.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

source "$(dirname "$0")/mm-provenance.sh"

swiftc -parse-as-library -o "$SCRATCH/probe" "${SOURCES[@]}" 2>"$SCRATCH/compile.log" || {
  print -u2 -- "⚠ 编译探针失败："
  cat "$SCRATCH/compile.log"
  exit 3
}

emit() {
  print -r -- "# p41-nil-size-probe.sh  $(date '+%Y-%m-%d %H:%M:%S %z')"
  print -r -- "# repo: $repoTag  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
  print -r -- "# digest: $(mm_source_digest "$PWD")"
  print -r -- "# 编译器: $(swiftc --version 2>/dev/null | head -1)"
  print -r -- "# 参与编译的真源文件（$((${#SOURCES[@]} - 1)) 个 + 探针）："
  for f in "${SOURCES[@]}"; do
    print -r -- "#   $(wc -l <"$f" | tr -d ' ') 行  $f"
  done
  print -r -- "# 两个真源文件一行没改、也不需要剥 import（它们只 import Foundation/Darwin）。"
  print -r -- "# 口径：这是 (b) 影响面的**上界**——探针给的 deadline（600 s）比真扫描按 rootBudget/"
  print -r -- "#   totalBudget 分给每个候选的那条线宽裕；真扫描里被截断的行今天已经是 nil，"
  print -r -- "#   不会「因为 (b) 才变 nil」，所以上界不减掉那部分。"
  print -r -- "# 全程只读：不调用删除接口；走的根与页面点一次「重新扫描」同一套。"
  print -r -- ""
  "$SCRATCH/probe"
}

if [[ $TO_STDOUT -eq 1 ]]; then
  emit
  exit $?
fi

mkdir -p "$OUT"
emit >"$OUT/nil-size.log"
print -r -- "✅ $OUT/nil-size.log"
tail -12 "$OUT/nil-size.log"
