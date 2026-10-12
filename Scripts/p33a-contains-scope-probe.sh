#!/bin/zsh
# P33a 审计取证：`名称包含应用名` 这条证据在增强/深度档会不会把**别的应用**的残留
# 收进本机应用清单，并且被默认勾选。
#
# 判定一行都不在这个脚本里：`Scripts/p33a-contains-scope-probe.swift` 与真源文件编成同一个模块，
# 表里每一格都是 ResidualScanner.scan / ResidualNameMatcher.reason(allowContains:false) /
# ResidualCategory.defaultRisk / MMRisk.isDefaultSelected 的原样返回值。
# 为什么必须合成一个模块：`ResidualScanContext`、`ResidualCollector.add` 与
# `ContainerScanner.metadataIdentifierKey` 都不是 public，分成两个模块就只能把逻辑抄一遍。
#
# 参与编译的是**卸载页扫描那一条链**（AppScanner→ResidualScanner→ContainerScanner→
# LaunchServiceScanner→ResidualCollector→ResidualNameMatcher→SteamLauncherProbe）加 MMCore 的
# Risk 与 HookValues 两个文件；UI 文件（MMUninstaller.swift 引 SwiftUI/MMUI）与
# UninstallerModel.swift（引 MMFileScanner）**不参与**，页面调用 scan 时传的参数形态由
# 本探针按 UninstallerModel.swift:379 那一行逐字照抄（appName 用 bundleName，不用显示名）。
# OrphanScanner.swift 只定义 `InstalledAppIdentity`（P33b 之后 `ResidualScanOptions.foreignApps`
# 引用它），只 import Foundation，所以拉进来不会牵进 UI 依赖。
#
# 这台机器是**真 home**：探针只读（contentsOfDirectory / lstat / PropertyListSerialization），
# 不调用任何删除接口；大小只对被点名的跨应用项量，不是全盘遍历。
#
#   ./Scripts/p33a-contains-scope-probe.sh              写 docs/verification/p33a-contains-scope/contains-scope.log
#   ./Scripts/p33a-contains-scope-probe.sh --stdout     只打终端，不写证据目录
#   OUT=… ./Scripts/p33a-contains-scope-probe.sh        换输出目录
#
# 退出码恒为 0：这一支是量尺，本轮的结论恰恰是"它量出来的是违例"，把违例做成红门
# 会在修复落地前一直红。真正的门是 p16。
set -e

cd "$(dirname "$0")/.."
TO_STDOUT=0
[[ "${1:-}" == "--stdout" ]] && TO_STDOUT=1
OUT=${OUT:-docs/verification/p33a-contains-scope}

repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi

MMC=Packages/MMCore/Sources/MMCore
MMU=Packages/MMUninstaller/Sources/MMUninstaller
typeset -a SOURCES=(
  "$MMC/Risk.swift"
  "$MMC/HookValues.swift"
  "$MMU/AppScanner.swift"
  "$MMU/ResidualNameMatcher.swift"
  "$MMU/OrphanScanner.swift"
  "$MMU/ResidualCollector.swift"
  "$MMU/ResidualScanner.swift"
  "$MMU/ContainerScanner.swift"
  "$MMU/LaunchServiceScanner.swift"
  "$MMU/SteamLauncherProbe.swift"
  Scripts/p33a-contains-scope-probe.swift
)
for f in "${SOURCES[@]}"; do
  [[ -f $f ]] || { print -u2 -- "⚠ 编译清单里的文件不存在：$f（真源改名后要同步这一份清单）"; exit 2; }
done

SCRATCH=$(mktemp -d /tmp/mm-p33a-probe.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

# 归因头用的内容指纹配方在这里（它是函数库，不能直接当脚本跑）。
source "$(dirname "$0")/mm-provenance.sh"

# ---- 合成一个模块：唯一的机械改动是去掉 `import MMCore` 那一行 ----
# 同模块内才有内部可见性（ResidualScanContext / ResidualCollector.add / metadataIdentifierKey
# 都不是 public），而 `import MMCore` 在合成模块里必然报 no such module。
# 每个被剥的文件都把「原行数 → 现行数」写进日志头，差一条不等于 1 行就当场退出——
# 判定代码一个字没动，这一句可以被机械复核。
typeset -a COMPILED=()
typeset -a STRIPPED=()
for f in "${SOURCES[@]}"; do
  if grep -q '^import MMCore$' "$f"; then
    base=$(basename "$f")
    orig=$(wc -l <"$f" | tr -d ' ')
    sed '/^import MMCore$/d' "$f" >"$SCRATCH/$base"
    now=$(wc -l <"$SCRATCH/$base" | tr -d ' ')
    if [[ $now -ne $(( orig - 1 )) ]]; then
      print -u2 -- "⚠ 剥 import 之后行数不对：$base 原 $orig 行 / 现 $now 行（应当只差 1 行）"
      exit 2
    fi
    STRIPPED+=("$base $orig→$now")
    COMPILED+=("$SCRATCH/$base")
  else
    COMPILED+=("$f")
  fi
done

swiftc -parse-as-library -o "$SCRATCH/probe" "${COMPILED[@]}" 2>"$SCRATCH/compile.log" || {
  print -u2 -- "⚠ 编译探针失败："
  cat "$SCRATCH/compile.log"
  exit 3
}

emit() {
  print -r -- "# p33a-contains-scope-probe.sh  $(date '+%Y-%m-%d %H:%M:%S %z')"
  print -r -- "# repo: $repoTag  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
  print -r -- "# digest: $(mm_source_digest "$PWD")"
  print -r -- "# 编译器: $(swiftc --version 2>/dev/null | head -1)"
  print -r -- "# 参与编译的真源文件（$((${#SOURCES[@]} - 1)) 个 + 探针）："
  for f in "${SOURCES[@]}"; do
    print -r -- "#   $(wc -l <"$f" | tr -d ' ') 行  $f"
  done
  print -r -- "# 唯一机械改动 = 去掉这些文件里的「import MMCore」一行（合成模块里 import 必报 no such module）："
  if [[ ${#STRIPPED[@]} -eq 0 ]]; then
    print -r -- "#   （本轮没有任何文件需要剥 import）"
  else
    for s in "${STRIPPED[@]}"; do print -r -- "#   $s"; done
  fi
  print -r -- "# 剥之前后各记一次行数，差一条不等于 1 行脚本就当场退出。"
  print -r -- "# 探针里没有一行判定逻辑：包含匹配、类别默认风险、默认勾选全走上面这些真函数。"
  print -r -- "# 扫的是本机真 home（只读）；probe 不调用删除接口，大小只对被点名的项量。"
  print -r -- ""
  "$SCRATCH/probe"
}

if [[ $TO_STDOUT -eq 1 ]]; then
  emit
  exit $?
fi

mkdir -p "$OUT"
emit >"$OUT/contains-scope.log"
print -r -- "✅ $OUT/contains-scope.log"
tail -6 "$OUT/contains-scope.log"
