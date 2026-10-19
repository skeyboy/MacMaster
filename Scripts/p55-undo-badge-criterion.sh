#!/bin/zsh
# P55 前置量：「最近操作」那一行要说「盘已取下」，判据拿什么——以及它拿不到什么。
#
# 这一族是 `docs/analysis/fidelity-uninstaller.md` §18.5 末尾登记的那个指针的落地：
# 03h 画板 3 与画板 5 第五条把徽章措辞从「废纸篓已清空」改判成「盘已取下」，
# 但改判要成立，界面必须先能**分辨两种成因**（谁倒了垃圾 / 谁拔了盘），
# 而今天 `canUndo` 只有 `fileExists(trashPath)` 一句（`FileTrashService.swift:294-300`，其中 `:298`），
# 它只知道"那个路径读不到了"，不知道**为什么**读不到。
#
# 量法：借 P53 那支夹具（`Scripts/p53-cross-volume-fixture.sh`，卷造在 /tmp、挂载点也在 /tmp 下），
# 挂上→读一次、拔掉→再读一次，同一支探针、同一个路径，两档读数并排进一份日志。
# 本轮**不删任何东西、不碰用户废纸篓**：落点那一格用夹具卷里的种子应用路径冒充，
# 因为 `canUndo` 问的就是"这个路径读不读得到"，与它是不是真的 trashPath 无关（这条口径写进判据旁边，别让下一轮误会）。
#
#   ./Scripts/p55-undo-badge-criterion.sh            跑完整两档，写 docs/verification/p55-undo-badge-criterion/
#   ./Scripts/p55-undo-badge-criterion.sh --keep     跑完不 clean，把卷留在挂载状态（调试用）
#
# 纪律：夹具造在 /tmp，只 detach 自己那一个挂载点，不 -force；退出时按开局的状态收尾——
# 开局没挂就 clean（删盘），开局挂着就只卸不删。全程不改 `Sources/`、`Packages/`。
set -e

cd "$(dirname "$0")/.."
FIXTURE=Scripts/p53-cross-volume-fixture.sh
SRC=Scripts/p55-detach-criterion-probe.swift
OUT=${OUT:-docs/verification/p55-undo-badge-criterion}
LOG=00-criterion-reading.log
MP=${MP:-/tmp/mm-p53-mnt}
# 探针问的那两条路径：落点用夹具卷里的种子应用（挂载中读得到、拔盘读不到，正是 canUndo 那一句的两种答案）。
TARGET=/private/tmp/mm-p53-mnt/Applications/AaaP53CrossVolume.app
MARKER=/private/tmp/mm-p53-mnt

KEEP=0
case "${1:-}" in --keep) KEEP=1 ;; esac

[[ -f $FIXTURE ]] || { print -u2 -- "✗ 夹具脚本不存在：$FIXTURE"; exit 2; }
[[ -f $SRC ]] || { print -u2 -- "✗ 探针源文件不存在：$SRC"; exit 2; }

repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi

SCRATCH=$(mktemp -d /tmp/mm-p55-probe.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

source "$(dirname "$0")/mm-provenance.sh"

swiftc -parse-as-library -o "$SCRATCH/probe" "$SRC" 2>"$SCRATCH/compile.log" || {
  print -u2 -- "⚠ 编译探针失败（volumeUUIDStringKey 那一类成员不存在就走这一支）："
  cat "$SCRATCH/compile.log"
  exit 3
}

# 开局状态：这块卷本来挂没挂、盘本来在不在。收尾照它来，别把用户机器留在半路。
# 两行都必须写成 if 而不是 `[[ … ]] && x=1`：后者在"没挂/没盘"这条最常见的分支上返回非零，
# 而 `set -e` 会把它当成失败直接把脚本收掉。
was_mounted=0
if [[ -d $MP ]] && mount | grep -q " on $(cd "$MP" && pwd -P) ("; then was_mounted=1; fi
was_image=0
if [[ -f /tmp/mm-p53-volume/MMVolumeP53.dmg ]]; then was_image=1; fi

mkdir -p "$OUT"
{
  print -r -- "# p55-undo-badge-criterion.sh  $(date '+%Y-%m-%d %H:%M:%S %z')"
  print -r -- "# repo: $repoTag   # digest: $(mm_source_digest "$PWD")"
  print -r -- "# 编译器: $(swiftc --version 2>/dev/null | head -1)"
  print -r -- "# 探针源文件：$(wc -l <"$SRC" | tr -d ' ') 行  $SRC（单文件编译，不链任何生产源文件）"
  print -r -- "# 落点用 $TARGET 冒充（canUndo 问的是「这个路径读不读得到」，与它是不是真 trashPath 无关）"
  print -r -- "# 开局：挂载=$was_mounted  盘=$was_image"
  print -r -- ""

  print -r -- "==================== 档 A：挂载中 ===================="
  $FIXTURE create
  $FIXTURE mount
  print -r -- ""
  "$SCRATCH/probe" --target "$TARGET" --mountpoint "$MARKER"
  print -r -- ""

  print -r -- "==================== 档 B：已拔盘 ===================="
  $FIXTURE detach
  print -r -- ""
  "$SCRATCH/probe" --target "$TARGET" --mountpoint "$MARKER"
} >"$OUT/$LOG" 2>&1

# 收尾：照开局状态。默认把夹具删干净（开局本来就没有盘），--keep 才留着。
if [[ $KEEP -eq 0 && $was_mounted -eq 0 && $was_image -eq 0 ]]; then
  $FIXTURE clean >>"$OUT/$LOG" 2>&1 || print -u2 -- "⚠ clean 失败，夹具留在 /tmp/mm-p53-volume，手动收尾"
elif [[ $KEEP -eq 0 && $was_mounted -eq 1 ]]; then
  : # 本来就挂着，什么都不动
fi

print -r -- "✅ $OUT/$LOG"
tail -6 "$OUT/$LOG"
