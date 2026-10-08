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
  fi
  # 每个测试类都会打一行 `Executed N tests`，只有「Test Suite 'All tests' passed/failed」
  # 后面那一行才是这个包的总数。别按字面顺序匹配 "with X failures"：
  # 有跳过项时那行长成 `with 1 test skipped and 0 failures`，MMDisk 曾被这样解析成 0 个测试。
  # **`failures` 要写成可选**：XCTest 按数字单复数变形，1 条失败时那行是 `with 1 failure`，
  # 照原来的复数写法这条正则整体不匹配、`f` 落回 0——于是屏幕上打出"0 个失败"，
  # 而同一份原始日志里明写着 `with 1 failure`（P28 现读到过这一对，见 §7.19）。
  # **同一形态还有第三种躲法**（CI 的 testlogs-4 里现读到）：既有跳过又有失败时那行是
  # `with 1 test skipped and 1 failure`——`with` 后面跟的是 skipped，不是 failures，
  # 所以"with <数> failures"这个写法整体不匹配，`f` 又落回 0，屏幕上第二次打出"0 个失败"。
  # 修法不能是"先把 skipped 那半截 sed 掉再按 with 取"：那半截连 `with` 一起吃掉了，
  # 剩下 `tests, 1 failure` 里根本没有 `with`，这一版就这么在夹具上被 ShapeD 抓出来（P28）。
  # 正确取法是**绕开 `with`、按 `failure(s)` 这个词前面那个数取**；`skipped` 同理。
  # `Executed ([0-9]+) tests` 同理要写 `tests?`：只有 1 个用例的包那行是 `Executed 1 test`。
  line=$(grep -A1 "Test Suite 'All tests' \(passed\|failed\)" "$out" | grep -m1 "Executed" || true)
  t=$(printf '%s' "$line" | sed -nE 's/.*Executed ([0-9]+) tests?.*/\1/p')
  f=$(printf '%s' "$line" | sed -nE 's/.*[^0-9]([0-9]+) failures?.*/\1/p')
  sk=$(printf '%s' "$line" | sed -nE 's/.*[^0-9]([0-9]+) tests? skipped.*/\1/p')
  # swift-testing 那一支（有些包用的是 @Test 宏，不出 XCTest 行）。
  st=$(grep -oE "Test run with [0-9]+ tests" "$out" | grep -oE "[0-9]+" | awk '{s+=$1} END {print s+0}')
  stsk=$(grep -cE "^⏭" "$out" || true)
  t=${t:-0}; f=${f:-0}; sk=${sk:-0}
  # **两道互不相干的取数对撞**：汇总行解析出来的失败数，与逐条 `Test Case '…' failed` 的行数。
  # 前者可能更大（一个用例里两条断言算两条失败），所以这里只咬 0/非 0 这一侧：
  # 屏幕上写"0 个失败"而包里明明有 failed 行，就是 §7.19 那一类假绿——现在它当场改判并留一行说明。
  fc=$(grep -c "Test Case '.*' failed" "$out" || true)
  fc=${fc:-0}
  note=''
  if [[ "$f" == 0 && "$fc" != 0 ]]; then
    f=$fc
    ok=no
    note="（汇总行说 0 条失败，包里有 $fc 行 Test Case failed：按后者记账并判这个包失败）"
  fi
  # 一个包只记一次名：`swift test` 非零与对撞改判可以同时发生，append 在两处就会点名两遍。
  if [[ "$ok" == no ]]; then failed_pkgs+=("$p"); fi
  tests=$((tests + t + st))
  failures=$((failures + f))
  skipped=$((skipped + sk + stsk))
  printf '%-14s XCTest=%-4s swift-testing=%-3s skipped=%-2s 该包失败=%s %s\n' \
    "$p" "$t" "$st" "$((sk + stsk))" "$([[ $ok == no ]] && echo YES || echo no)" "$note"
done

echo
echo "合计：${tests} 个测试，${failures} 个失败，${skipped} 个跳过"
echo "逐包原始输出：$LOG/<pkg>.log"
if (( ${#failed_pkgs[@]} > 0 )); then
  echo "失败的包：${failed_pkgs[*]}"
  exit 1
fi
