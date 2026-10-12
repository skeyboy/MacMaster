#!/bin/zsh
# P35a 取证：本机现在挂着哪些卷、Foundation 的卷枚举（`mountedVolumeURLs`）会把它们说成
# 什么，以及「最满的那卷优先」这句话在三种可用容量口径下是不是同一个排序。
#
# 这是一支**审计探针**，不是生产代码：判据将来落在 MMDisk 里，这里只把真机现状量出来。
# 对照的那一把尺子是进程内 `getmntinfo`（挂载表）+ `statvfs`——disktree 拿 `mount` 的
# **文本输出**做同一件事，v1.1 §2 第 4 条明确不学它，所以这里也只调系统调用，不 spawn 子进程。
#
# 全程只读：不扫目录树、不写、不弹 NSOpenPanel、不 mount/diskutil、不请求任何权限。
#
#   ./Scripts/p35a-volumes-probe.sh              写 docs/verification/p35a-volumes/volumes.log
#   ./Scripts/p35a-volumes-probe.sh --stdout     只打终端，不写证据目录
#   OUT=… ./Scripts/p35a-volumes-probe.sh        换输出目录（同族多跑必须换目录，规矩出自 f7bca94）
#
# 退出码恒为 0（量尺）。真正的门是 p16 与将来的 MMDisk 单测。
set -e

cd "$(dirname "$0")/.."
TO_STDOUT=0
case "${1:-}" in
  --stdout) TO_STDOUT=1 ;;
esac
OUT=${OUT:-docs/verification/p35a-volumes}
LOG=volumes.log

SRC=Scripts/p35a-volumes-probe.swift
[[ -f $SRC ]] || { print -u2 -- "✗ 探针源文件不存在：$SRC"; exit 2; }

repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi

SCRATCH=$(mktemp -d /tmp/mm-p35a-probe.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

# 归因头用的内容指纹配方在这里（它是函数库，不能直接当脚本跑）。
source "$(dirname "$0")/mm-provenance.sh"

swiftc -parse-as-library -o "$SCRATCH/probe" "$SRC" 2>"$SCRATCH/compile.log" || {
  print -u2 -- "⚠ 编译探针失败："
  cat "$SCRATCH/compile.log"
  exit 3
}

emit() {
  print -r -- "# p35a-volumes-probe.sh  $(date '+%Y-%m-%d %H:%M:%S %z')"
  print -r -- "# repo: $repoTag  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
  print -r -- "# digest: $(mm_source_digest "$PWD")"
  print -r -- "# 编译器: $(swiftc --version 2>/dev/null | head -1)"
  print -r -- "# 探针源文件：$(wc -l <"$SRC" | tr -d ' ') 行  $SRC（单文件编译，不链任何生产源文件）"
  print -r -- "# 量的三件事：① 挂载表全量 vs Foundation 默认档 vs 传 .skipHiddenVolumes 档，条数差在谁身上；"
  print -r -- "# ② 「最满优先」在 avail普通 / avail重要 / avail机会（以及 statvfs f_bavail 那一族）下是不是同一顺序；"
  print -r -- "# ③ 枚举回来的一堆路径里哪些真能当扫描根（browsable / isDirectory / readOnly / removable，交叉挂载表标志位）。"
  print -r -- "# 注意：这个 SDK 里没有 .includeHiddenVolumes 这个成员（现读编译核实），默认档已经含隐藏卷。"
  print -r -- "# 对照的挂载表走进程内 getmntinfo + statvfs，不 spawn mount。"
  print -r -- ""
  "$SCRATCH/probe"
}

if [[ $TO_STDOUT -eq 1 ]]; then
  emit
  exit $?
fi

mkdir -p "$OUT"
emit >"$OUT/$LOG"
print -r -- "✅ $OUT/$LOG"
tail -8 "$OUT/$LOG"
