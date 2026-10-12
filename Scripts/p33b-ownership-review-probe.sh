#!/bin/zsh
# P33b 取证：「祖先归属复核」在本机真 home 上到底把哪几行从默认勾选改成了谨慎，改完之后
# 清单里的条目集合有没有少一条（召回不降）。
#
# 这是一支 **同一二进制上的 A/B 量尺**：对每个应用、每一档跑两次真扫描——
# `foreignApps=[]`（复核接入前的行为）与 `foreignApps=整张已装清单`（页面现在的传法，
# 剔除自己由引擎负责）。两遍之间不存在"上一次跑的是另一棵树"这种漂移。
#
# 判定逻辑一行都不在这个脚本与探针里：风险档来自 ResidualCategory.defaultRisk 与
# ResidualCollector 的复核，命中集合来自 ResidualScanner.scan，大小来自
# DirectoryResidualSizeMeasurer。探针只做对读与打印。
#
# 参与编译的真源文件与 `p33a-contains-scope-probe.sh` 同一份清单（含 OrphanScanner.swift，
# 它定义 `InstalledAppIdentity`），UI 文件不参与。
#
# 这台机器是**真 home**（默认档）：只读，不调用任何删除接口；大小只对被点名的降级项量。
#
#   ./Scripts/p33b-ownership-review-probe.sh              写 docs/verification/p33b-nesting/ownership-review.log
#   ./Scripts/p33b-ownership-review-probe.sh --stdout     只打终端，不写证据目录
#   OUT=… ./Scripts/p33b-ownership-review-probe.sh        换输出目录
#
# 夹具档（`FIX=<p33b 夹具根>`）：同一支二进制改扫那棵假 home，逐应用逐档把**整张残留清单**
# 连证据串、风险档、默认勾选、字节、提醒一起打成表，写到 `fixture-rows.log`。
# 它是截图脚本的前置：照片的预期行必须由真扫描器在同一棵树上返值，不能由我照代码推导——
# 推导写进 `.log` 之后，照片拍到什么都能自圆其说。
#
#   FIX=$(./Scripts/p33b-nesting-fixture.sh) ./Scripts/p33b-ownership-review-probe.sh
#
# 退出码恒为 0（量尺）。"召回不降"那条不变量违例时会在日志里打出 ⚠ 行，但不改变退出码——
# 这一支先负责把数说清楚，真正的门是 p16 与单测。
set -e

cd "$(dirname "$0")/.."
TO_STDOUT=0
[[ "${1:-}" == "--stdout" ]] && TO_STDOUT=1
FIX=${FIX:-}
OUT=${OUT:-docs/verification/p33b-nesting}
if [[ -n $FIX ]]; then
  LOG=fixture-rows.log
  [[ -d "$FIX/Applications" ]] || { print -u2 -- "✗ FIX=$FIX 底下没有 Applications，夹具档拍不了（先跑 ./Scripts/p33b-nesting-fixture.sh）"; exit 2; }
else
  LOG=ownership-review.log
fi

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
  Scripts/p33b-ownership-review-probe.swift
)
for f in "${SOURCES[@]}"; do
  [[ -f $f ]] || { print -u2 -- "⚠ 编译清单里的文件不存在：$f（真源改名后要同步这一份清单）"; exit 2; }
done

SCRATCH=$(mktemp -d /tmp/mm-p33b-probe.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

# 归因头用的内容指纹配方在这里（它是函数库，不能直接当脚本跑）。
source "$(dirname "$0")/mm-provenance.sh"

# ---- 合成一个模块：唯一的机械改动是去掉 `import MMCore` 那一行 ----
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
  print -r -- "# p33b-ownership-review-probe.sh  $(date '+%Y-%m-%d %H:%M:%S %z')"
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
  print -r -- "# 每个应用每一档扫两遍：foreignApps=[]（复核前）与 foreignApps=整张已装清单（现在页面的传法）。"
  if [[ -n $FIX ]]; then
    print -r -- "# 本轮是**夹具档**：home=$FIX（假 home，由 Scripts/p33b-nesting-fixture.sh 生成），三档全打。"
    print -r -- "# 这份表是截图脚本的预期行来源：照片上每一行的证据、勾选、提醒都取自这里。"
  else
    print -r -- "# 扫的是本机真 home（只读）；probe 不调用删除接口，大小只对被点名的降级项量。"
  fi
  print -r -- ""
  P33B_PROBE_FIXTURE_HOME="$FIX" "$SCRATCH/probe"
}

if [[ $TO_STDOUT -eq 1 ]]; then
  emit
  exit $?
fi

mkdir -p "$OUT"
emit >"$OUT/$LOG"
print -r -- "✅ $OUT/$LOG"
tail -6 "$OUT/$LOG"
