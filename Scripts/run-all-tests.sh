#!/bin/zsh
# 九包全量单测，逐包给一行结论，末尾给总计。
#
# 为什么要脚本而不是手敲 `swift test | tail -4`：SwiftPM 的结论行有两种形态——
# XCTest 打在「Test Suite 'All tests'」后面的 `Executed N tests`，swift-testing 打在
# `Test run with N tests`，而且前者每个测试类还会各出一行。tail -4 只剩 swift-testing
# 那一行，于是 MMCore 的 43 个测试在屏幕上显示成 "0 tests"：跑过了，看起来却像没跑。
#
# 用法：./Scripts/run-all-tests.sh          # 全九包
#       PKGS="MMCleaner MMCore" ./Scripts/run-all-tests.sh
set -e
cd "$(dirname "$0")/.."

PKGS=${PKGS:-"MMCore MMUI MMFileScanner MMCleaner MMUninstaller MMDisk MMMonitor MMGuardian MMOptimizer"}
LOG=${LOG:-/tmp/macmaster-tests}
rm -rf "$LOG"
mkdir -p "$LOG"

tests=0
failures=0
skipped=0
failed_pkgs=()

for p in ${=PKGS}; do
  out="$LOG/$p.log"
  if swift test --package-path "Packages/$p" > "$out" 2>&1; then
    ok=yes
  else
    ok=no
    failed_pkgs+=("$p")
  fi
  # 每个测试类都会打一行 `Executed N tests`，只有「Test Suite 'All tests' passed/failed」
  # 后面那一行才是这个包的总数。别按字面顺序匹配 "with X failures"：
  # 有跳过项时那行长成 `with 1 test skipped and 0 failures`，MMDisk 曾被这样解析成 0 个测试。
  line=$(grep -A1 "Test Suite 'All tests' \(passed\|failed\)" "$out" | grep -m1 "Executed" || true)
  t=$(printf '%s' "$line" | sed -nE 's/.*Executed ([0-9]+) tests.*/\1/p')
  f=$(printf '%s' "$line" | sed -nE 's/.*with ([0-9]+) failures.*/\1/p')
  sk=$(printf '%s' "$line" | sed -nE 's/.*with ([0-9]+) test(s)? skipped.*/\1/p')
  # swift-testing 那一支（有些包用的是 @Test 宏，不出 XCTest 行）。
  st=$(grep -oE "Test run with [0-9]+ tests" "$out" | grep -oE "[0-9]+" | awk '{s+=$1} END {print s+0}')
  stsk=$(grep -cE "^⏭" "$out" || true)
  t=${t:-0}; f=${f:-0}; sk=${sk:-0}
  tests=$((tests + t + st))
  failures=$((failures + f))
  skipped=$((skipped + sk + stsk))
  printf '%-14s XCTest=%-4s swift-testing=%-3s skipped=%-2s 该包失败=%s\n' \
    "$p" "$t" "$st" "$((sk + stsk))" "$([[ $ok == no ]] && echo YES || echo no)"
done

echo
echo "合计：${tests} 个测试，${failures} 个失败，${skipped} 个跳过"
echo "逐包原始输出：$LOG/<pkg>.log"
if (( ${#failed_pkgs[@]} > 0 )); then
  echo "失败的包：${failed_pkgs[*]}"
  exit 1
fi
