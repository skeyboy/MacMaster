#!/bin/zsh
# P34a 取证：`~/Library/Preferences`（顶层 + ByHost 递归）这一族 plist 在本机真 home 上
# 到底是什么状态——解析成功 / 0 字节 / 解析失败 / 读不到 各多少条，以及同一批文件上
# `plutil -lint`（对照 oracle）给的读数是不是同一个答案。
#
# 这是一支**审计探针**，不是生产代码：判据将来落在 MMOptimizer 里，这里只把真机现状量出来。
# `plutil` 只在这一支里出现，用它是因为它是"另一种判据"，不是因为它更方便——
# 生产实现按 v1.1 §2 第 3 条的约束走 `PropertyListSerialization`，不为此 spawn 进程。
#
# 全程只读：不写、不删、不改任何偏好域，也不动 cfprefsd。
#
#   ./Scripts/p34a-prefs-plist-probe.sh              写 docs/verification/p34a-prefs/prefs-plist.log
#   ./Scripts/p34a-prefs-plist-probe.sh --stdout     只打终端，不写证据目录
#   ./Scripts/p34a-prefs-plist-probe.sh --synthetic  夹具档，写同目录 synth-cases.log
#   OUT=… ./Scripts/p34a-prefs-plist-probe.sh        换输出目录
#   P34A_PROBE_HOME=/tmp/… ./Scripts/p34a-prefs-plist-probe.sh    换 home（夹具档，留给 P34b）
#
# 退出码恒为 0（量尺）。真正的门是 p16 与 P34b 的单测。
set -e

cd "$(dirname "$0")/.."
TO_STDOUT=0
MODE=real
case "${1:-}" in
  --stdout) TO_STDOUT=1 ;;
  --synthetic) MODE=synth ;;
  --synthetic-stdout) MODE=synth; TO_STDOUT=1 ;;
esac
OUT=${OUT:-docs/verification/p34a-prefs}
if [[ $MODE == synth ]]; then
  LOG=synth-cases.log
else
  LOG=prefs-plist.log
fi

SRC=Scripts/p34a-prefs-plist-probe.swift
[[ -f $SRC ]] || { print -u2 -- "✗ 探针源文件不存在：$SRC"; exit 2; }

repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi

SCRATCH=$(mktemp -d /tmp/mm-p34a-probe.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

# 归因头用的内容指纹配方在这里（它是函数库，不能直接当脚本跑）。
source "$(dirname "$0")/mm-provenance.sh"

swiftc -parse-as-library -o "$SCRATCH/probe" "$SRC" 2>"$SCRATCH/compile.log" || {
  print -u2 -- "⚠ 编译探针失败："
  cat "$SCRATCH/compile.log"
  exit 3
}

emit() {
  print -r -- "# p34a-prefs-plist-probe.sh  $(date '+%Y-%m-%d %H:%M:%S %z')"
  print -r -- "# repo: $repoTag  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
  print -r -- "# digest: $(mm_source_digest "$PWD")"
  print -r -- "# 编译器: $(swiftc --version 2>/dev/null | head -1)"
  print -r -- "# 探针源文件：$(wc -l <"$SRC" | tr -d ' ') 行  $SRC（单文件编译，不链任何生产源文件）"
  if [[ $MODE == synth ]]; then
    print -r -- "# 本轮是**夹具档**：探针自己造 12 条已知答案的样本（好/坏/看着坏其实正常）放进一棵 /tmp 假 home，"
    print -r -- "# 再用与真 home **同一条采集路径**过一遍，逐条对 Foundation 判据、plutil 判据与登记的期望。"
    print -r -- "# 它问的是「我们的判据边界在哪」——真 home 上这一族几乎全是好的，这个问题在真机上问不出来。"
  else
    print -r -- "# 扫的是本机真 home（只读）。plutil 只在本探针里当对照 oracle，生产实现不 spawn 它。"
  fi
  print -r -- ""
  if [[ $MODE == synth ]]; then
    P34A_PROBE_SYNTH="$SCRATCH/prefs-home" "$SCRATCH/probe"
  else
    "$SCRATCH/probe"
  fi
}

if [[ $TO_STDOUT -eq 1 ]]; then
  emit
  exit $?
fi

mkdir -p "$OUT"
emit >"$OUT/$LOG"
print -r -- "✅ $OUT/$LOG"
tail -8 "$OUT/$LOG"
