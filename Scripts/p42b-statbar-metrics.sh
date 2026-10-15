#!/bin/zsh
# P42b 量尺：监控页顶部读数条 4 格 → 6 格（I8 加网络进出）到底要不要拆行、会不会缩字。
#
# 判据只有两条：`MMStatItem` 自己的约束（数值 lineLimit(1)+minimumScaleFactor(0.7)、
# 标题 .caption 且没有 lineLimit）与这条链上的四个硬宽度（窗口最小 1000 / 侧栏 220 /
# 滚动区边距 16 / 卡内边距 12）。字体用 AppKit 的 preferredFont 现量，不查表、不估。
#
# 不建窗口、不采样、不写盘：探针离屏算文字固有宽。落地那一步仍要拍一张 6 格的最小窗照片，
# 这条量尺只负责把"要不要为它拆行"这个疑问变成数，不替代实拍。
#
#   ./Scripts/p42b-statbar-metrics.sh              写 docs/verification/p42b-statbar/metrics.log
#   ./Scripts/p42b-statbar-metrics.sh --stdout     只打终端，不写证据目录
#   OUT=… ./Scripts/p42b-statbar-metrics.sh        换输出目录
#
# 退出码恒为 0：这一支是量尺，不是门。真正的门是 p16。
set -e

cd "$(dirname "$0")/.."
TO_STDOUT=0
[[ "${1:-}" == "--stdout" ]] && TO_STDOUT=1
OUT=${OUT:-docs/verification/p42b-statbar}

repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi

PROBE=Scripts/p42b-statbar-metrics.swift
[[ -f $PROBE ]] || { print -u2 -- "⚠ 探针文件不存在：$PROBE"; exit 2; }

SCRATCH=$(mktemp -d /tmp/mm-p42b-statbar.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

source "$(dirname "$0")/mm-provenance.sh"

swiftc -o "$SCRATCH/probe" "$PROBE" 2>"$SCRATCH/compile.log" || {
  print -u2 -- "⚠ 编译探针失败："
  cat "$SCRATCH/compile.log"
  exit 3
}

emit() {
  print -r -- "# p42b-statbar-metrics.sh  $(date '+%Y-%m-%d %H:%M:%S %z')"
  print -r -- "# repo: $repoTag  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
  print -r -- "# digest: $(mm_source_digest "$PWD")"
  print -r -- "# 编译器: $(swiftc --version 2>/dev/null | head -1)"
  print -r -- "# 宽度链真源原文（探针里的常量抄的就是这五段，现读行号随本段一起打）："
  print -r -- "#   Sources/MacMaster/MacMasterApp.swift:36"
  sed -n '36p' Sources/MacMaster/MacMasterApp.swift | while IFS= read -r l; do print -r -- "#     $l"; done
  print -r -- "#   Sources/MacMaster/MainWindow.swift:22"
  sed -n '22p' Sources/MacMaster/MainWindow.swift | while IFS= read -r l; do print -r -- "#     $l"; done
  print -r -- "#   Packages/MMUI/Sources/MMUI/MMDesign.swift:93-101（MMGap）"
  sed -n '93,101p' Packages/MMUI/Sources/MMUI/MMDesign.swift | while IFS= read -r l; do print -r -- "#     $l"; done
  print -r -- "#   Packages/MMUI/Sources/MMUI/MMDesign.swift:399-408（MMStatItem 的 body：谁缩字、谁换行）"
  sed -n '399,408p' Packages/MMUI/Sources/MMUI/MMDesign.swift | while IFS= read -r l; do print -r -- "#     $l"; done
  print -r -- "#   Packages/MMMonitor/Sources/MMMonitor/MMMonitor.swift:118-124（现状 4 格）"
  sed -n '118,124p' Packages/MMMonitor/Sources/MMMonitor/MMMonitor.swift | while IFS= read -r l; do print -r -- "#     $l"; done
  print -r -- "# 口径声明：上面五段是**当轮现读**，探针里的 220/1000/16/12 若与真源漂移，本读数作废。"
  print -r -- "#   「取证窗 1100pt」取自 fidelity-monitor.md §0（p64 那批照片的窗宽），不是硬约束。"
  print -r -- ""
  "$SCRATCH/probe"
}

if [[ $TO_STDOUT -eq 1 ]]; then
  emit
  exit $?
fi

mkdir -p "$OUT"
emit >"$OUT/metrics.log"
print -r -- "✅ $OUT/metrics.log"
tail -8 "$OUT/metrics.log"
