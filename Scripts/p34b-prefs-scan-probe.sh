#!/bin/zsh
# P34b 取证：把**生产判据层本身**（`PreferencesAudit.swift`）在真机上跑一趟，量出
# 枚举 / 读取 / 解析三段的耗时拆分、ByHost 那一层的真实形状、"读不到"逐条归因，
# 以及外推到上千条时的形状。它回答的是 P34a 留下的 §11.1、§11.2、§11.3、§11.4 四句。
#
# 与 P34a 那支的分工：P34a 自带判据（那一轮生产代码还不存在），这一支**不重写判据**——
# 编译清单里就是 `Packages/MMOptimizer/Sources/MMOptimizer/PreferencesAudit.swift`，
# 量的是将来界面调的那一条路。判据逻辑一行都不在探针里。
#
# 因为链了生产源文件，归因头的 `# digest:` 是有意义的：改 `PreferencesAudit.swift`
# 不改这一支，digest 就会变，日志与代码不再同源这件事当场看得出来。
#
# 默认档全程只读：不写、不删、不改任何偏好域，也不动 cfprefsd。
# 规模档会往一个 /tmp 假 home 里造样本（探针行为，不进生产路径），跑完由 trap 删掉。
#
#   ./Scripts/p34b-prefs-scan-probe.sh                真 home，写 docs/verification/p34b-prefs/scan-shape.log
#   ./Scripts/p34b-prefs-scan-probe.sh --stdout       只打终端，不写证据目录
#   ./Scripts/p34b-prefs-scan-probe.sh --scale        规模档（2000 条小的 + 200 条大的），写 scale-shape.log
#   OUT=… ./Scripts/p34b-prefs-scan-probe.sh          换输出目录
#
# 退出码恒为 0（量尺）。预算数值由这份日志定，真正的门是 p16 与 P34b 单测。
set -e

cd "$(dirname "$0")/.."
TO_STDOUT=0
MODE=real
case "${1:-}" in
  --stdout) TO_STDOUT=1 ;;
  --scale) MODE=scale ;;
  --scale-stdout) MODE=scale; TO_STDOUT=1 ;;
esac
OUT=${OUT:-docs/verification/p34b-prefs}
[[ $MODE == scale ]] && LOG=scale-shape.log || LOG=scan-shape.log

SRC=Scripts/p34b-prefs-scan-probe.swift
AUDIT=Packages/MMOptimizer/Sources/MMOptimizer/PreferencesAudit.swift
for f in "$SRC" "$AUDIT"; do
  [[ -f $f ]] || { print -u2 -- "✗ 编译清单里的文件不存在：$f（真源改名后要同步这一份清单）"; exit 2; }
done

repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi

SCRATCH=$(mktemp -d /tmp/mm-p34b-probe.XXXXXX)
FAKEHOME=$(mktemp -d /tmp/mm-p34b-scale.XXXXXX)
trap 'rm -rf "$SCRATCH" "$FAKEHOME"' EXIT

source "$(dirname "$0")/mm-provenance.sh"

# 生产源文件只需要 Foundation，不链整个包：这样探针里的 scan 与界面里的 scan 是同一份代码，
# 而编译时间不必换成一次全量构建。
swiftc -parse-as-library -o "$SCRATCH/probe" "$AUDIT" "$SRC" 2>"$SCRATCH/compile.log" || {
  print -u2 -- "⚠ 编译探针失败："
  cat "$SCRATCH/compile.log"
  exit 3
}

emit() {
  print -r -- "# p34b-prefs-scan-probe.sh  $(date '+%Y-%m-%d %H:%M:%S %z')"
  print -r -- "# repo: $repoTag  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
  print -r -- "# digest: $(mm_source_digest "$PWD")"
  print -r -- "# 编译器: $(swiftc --version 2>/dev/null | head -1)"
  print -r -- "# 探针源文件：$(wc -l <"$SRC" | tr -d ' ') 行  $SRC"
  print -r -- "# 参与编译的生产源文件：$(wc -l <"$AUDIT" | tr -d ' ') 行  $AUDIT（判据本体在这一份里，探针不重写）"
  if [[ $MODE == scale ]]; then
    print -r -- "# 本轮是**规模档**：往 /tmp 假 home 造已知条数的 plist，再用同一个生产 scan 过一遍。"
    print -r -- "# 它问的是「上千条时的形状」——本机 625 条永远撞不到时间预算，这一档是唯一能让截断那句话真发生的地方。"
    print -r -- "# 写盘只发生在假 home 里，且跑完由 trap 删除；生产路径不写任何东西。"
  else
    print -r -- "# 扫的是本机真 home（只读）。这一档的进程是裸二进制、不是 .app——"
    print -r -- "# GUI 那个进程对「读不到」那一栏的答复由实拍照片（真机档）给出，两支合起来才是 §11.1 的答案。"
  fi
  print -r -- ""
  if [[ $MODE == scale ]]; then
    # 两种形状各一趟：小的贴近真实分布，大的贴近 MobileSMS 那种体积。
    print -r -- "### 形状 small（每条几行键值）"
    print -r -- ""
    P34B_PROBE_SCALE=2000 P34B_PROBE_SHAPE=small P34B_PROBE_ROOT="$FAKEHOME/small" "$SCRATCH/probe"
    print -r -- ""
    print -r -- "### 形状 big（每条 ~48 KB）"
    print -r -- ""
    P34B_PROBE_SCALE=200 P34B_PROBE_SHAPE=big P34B_PROBE_ROOT="$FAKEHOME/big" "$SCRATCH/probe"
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
tail -12 "$OUT/$LOG"
