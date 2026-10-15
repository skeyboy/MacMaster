#!/bin/zsh
# P42a 量尺：偏好文件页若加一列「主人名」，本机到底有多少行填得满。
#
# 判据只有一个：NSWorkspace.urlForApplication(withBundleIdentifier:) 命中与否（LaunchServices 只认
# 本机注册过的 bundle id）。探针不猜、不做名称模糊匹配、不读 plist 内容。
# 三道闸（剥扩展名 / 削 UUID 尾段 / 反向域名形态）的语义抄自
# Packages/MMUninstaller/Sources/MMUninstaller/OrphanScanner.swift——那三处真源原文随日志头一起打出来，
# 谁改真源时这份日志会当场露出两串不一致。
#
#   ./Scripts/p42-owner-resolve-probe.sh              写 docs/verification/p42-owner-resolve/probe.log
#   ./Scripts/p42-owner-resolve-probe.sh --stdout     只打终端，不写证据目录
#   OUT=… ./Scripts/p42-owner-resolve-probe.sh        换输出目录
#
# 退出码恒为 0：这一支是量尺，不是门。真正的门是 p16。
set -e

cd "$(dirname "$0")/.."
TO_STDOUT=0
[[ "${1:-}" == "--stdout" ]] && TO_STDOUT=1
OUT=${OUT:-docs/verification/p42-owner-resolve}

repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi

PROBE=Scripts/p42-owner-resolve-probe.swift
RULES=Packages/MMUninstaller/Sources/MMUninstaller/OrphanScanner.swift
[[ -f $PROBE ]] || { print -u2 -- "⚠ 探针文件不存在：$PROBE"; exit 2; }
[[ -f $RULES ]] || { print -u2 -- "⚠ 真源规则文件不存在：$RULES（真源改名后要同步这一份清单）"; exit 2; }

SCRATCH=$(mktemp -d /tmp/mm-p42-owner.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

source "$(dirname "$0")/mm-provenance.sh"

swiftc -o "$SCRATCH/probe" "$PROBE" 2>"$SCRATCH/compile.log" || {
  print -u2 -- "⚠ 编译探针失败："
  cat "$SCRATCH/compile.log"
  exit 3
}

emit() {
  print -r -- "# p42-owner-resolve-probe.sh  $(date '+%Y-%m-%d %H:%M:%S %z')"
  print -r -- "# repo: $repoTag  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
  print -r -- "# digest: $(mm_source_digest "$PWD")"
  print -r -- "# 编译器: $(swiftc --version 2>/dev/null | head -1)"
  print -r -- "# 全程只读：只列 ~/Library/Preferences 与 ByHost 的文件名，不读内容、不写盘。"
  print -r -- "# 三道闸的真源原文（$RULES，现读行号随本段一起打）："
  print -r -- "#   --- 剥扩展名（正则那一条）"
  sed -n '109,113p' "$RULES" | while IFS= read -r l; do print -r -- "#   $l"; done
  print -r -- "#   --- 削 UUID 尾段"
  sed -n '132,139p' "$RULES" | while IFS= read -r l; do print -r -- "#   $l"; done
  print -r -- "#   --- 反向域名形态"
  sed -n '141,147p' "$RULES" | while IFS= read -r l; do print -r -- "#   $l"; done
  print -r -- "#   --- isUUIDLike"
  sed -n '54,62p' "$RULES" | while IFS= read -r l; do print -r -- "#   $l"; done
  print -r -- "# 口径声明：上面这四段是**抄的语义**，探针自己实现了一遍。落地时判定必须由真源那一处出；"
  print -r -- "#   两串若漂移，本读数只能算近似，不能当判据。"
  print -r -- ""
  "$SCRATCH/probe"
}

if [[ $TO_STDOUT -eq 1 ]]; then
  emit
  exit $?
fi

mkdir -p "$OUT"
emit >"$OUT/probe.log"
print -r -- "✅ $OUT/probe.log"
tail -16 "$OUT/probe.log"
