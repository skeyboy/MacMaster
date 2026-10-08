#!/bin/zsh
# P28「假绿」夹具：喂给 run-all-tests.sh 六种 XCTest/swift-testing 结论行形态，
# 断言它每次都能把测试数、失败数、跳过数取对。
#
#   ./Scripts/p28-test-summary-shapes.sh
#
# 为什么要单独一份夹具：这九包的结论行是从日志里 grep 出来的，而日志只有真跑过才有。
# 一次 CI 失败（`with 1 test skipped and 1 failure`）让屏幕上打出"0 个失败"，
# 而同一份原始日志里明写着 1 failure——这种 bug 只在"有包真失败"那一跑才现形，
# 本地全绿的时候永远测不到。所以这里用一把假 `swift` 把日志形态直接摆出来。
#
# 假 `swift` 只做一件事：把 $MM_FIXTURE_LOGS/<包名>.log 打到 stdout，退出码照
# $MM_FIXTURE_EXITS/<包名>（没有就 0）。它不碰 Packages/，也就不会被真的构建牵扯。
set -e
cd "$(dirname "$0")/.."
ROOT=$PWD

dir=$(mktemp -d /tmp/macmaster-summary-shapes.XXXXXX)
trap 'rm -rf "$dir"' EXIT
logs="$dir/logs"
exits="$dir/exits"
bin="$dir/bin"
mkdir -p "$logs" "$exits" "$bin"

# 每份日志都带一行"测试类级"的 Executed 作诱饵：只有 `Test Suite 'All tests'`
# 后面那一行才是包总数，按第一行匹配会取到类级计数。
cat > "$logs/ShapeA.log" <<'EOF'
Test Case '-[MMCoreTests.ThingTests testOne]' passed (0.001 seconds).
Test Suite 'ThingTests' passed at 2026-10-08.
	 Executed 10 tests, with 0 failures (0 unexpected) in 0.010 (0.011) seconds
Test Suite 'All tests' passed at 2026-10-08.
	 Executed 43 tests, with 0 failures (0 unexpected) in 0.100 (0.105) seconds
EOF

# 只有跳过、没有失败：`with` 后面先跟 skipped，测试数那半截不能被它带跑。
cat > "$logs/ShapeB.log" <<'EOF'
Test Suite 'All tests' passed at 2026-10-08.
	 Executed 77 tests, with 1 test skipped and 0 failures (0 unexpected) in 0.188 (0.193) seconds
EOF

# 单数失败：老写法 `with ([0-9]+) failures` 在这一行整体不匹配，f 落回 0。
cat > "$logs/ShapeC.log" <<'EOF'
Test Case '-[MMDiskTests.RemoveTests testOne]' failed (0.002 seconds).
Test Suite 'All tests' failed at 2026-10-08.
	 Executed 12 tests, with 1 failure (0 unexpected) in 0.020 (0.025) seconds
EOF
printf '1\n' > "$exits/ShapeC"

# 既有跳过又有失败：`with` 后面跟的是 skipped，不是 failures——这是 CI 的
# testlogs-4 里真实出现过的形态，也是这一版解析器要钉住的那一条。
cat > "$logs/ShapeD.log" <<'EOF'
DiskRemovalTests.swift:69: error: -[MMDiskTests.DiskRemovalTests testSystemTreeIsBlockedButUserLibraryIsNot] : XCTAssertEqual failed: ("[]") is not equal to ("/Users/lee/Library/Caches")
Test Case '-[MMDiskTests.DiskRemovalTests testSystemTreeIsBlockedButUserLibraryIsNot]' failed (0.030 seconds).
Test Suite 'All tests' failed at 2026-10-08.
	 Executed 77 tests, with 1 test skipped and 1 failure (0 unexpected) in 0.188 (0.198) seconds
EOF
printf '1\n' > "$exits/ShapeD"

# 只有一个用例的包：`Executed 1 test`（单数），写死 `tests` 的正则取不到 t。
cat > "$logs/ShapeE.log" <<'EOF'
Test Suite 'All tests' passed at 2026-10-08.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.002) seconds
EOF

# swift-testing 那一支：根本不出 XCTest 行。
cat > "$logs/ShapeF.log" <<'EOF'
◇ Test run started.
✔ Test run with 6 tests in 2 suites passed after 0.010 seconds.
EOF

cat > "$bin/swift" <<'EOF'
#!/bin/zsh
pkg=unknown
for a in "$@"; do
  if [[ "$a" == Packages/* ]]; then pkg=${a#Packages/}; break; fi
done
cat "$MM_FIXTURE_LOGS/$pkg.log"
code=0
if [[ -f "$MM_FIXTURE_EXITS/$pkg" ]]; then code=$(cat "$MM_FIXTURE_EXITS/$pkg"); fi
exit "$code"
EOF
chmod +x "$bin/swift"

fail=0
check() {  # $1=描述 $2=期望出现的片段
  # 逐包行是 `%-4s`/`%-2s` 填空的，列宽随数字位数变；比对前把连续空格压成一个。
  want=$(printf '%s' "$2" | tr -s ' ')
  if printf '%s' "$out" | tr -s ' ' | grep -qF -- "$want"; then
    printf '  ok   %-24s ← %s\n' "$1" "$want"
  else
    printf '  FAIL %-24s 缺片段：%s\n' "$1" "$want"
    fail=1
  fi
}

echo "六种结论形态 → run-all-tests.sh 的取数"
out=$(PATH="$bin:$PATH" MM_FIXTURE_LOGS="$logs" MM_FIXTURE_EXITS="$exits" \
      PKGS="ShapeA ShapeB ShapeC ShapeD ShapeE ShapeF" LOG="$dir/run" \
      "$ROOT/Scripts/run-all-tests.sh" 2>&1) || true
printf '%s\n\n' "$out"

check 'A 常规'              'ShapeA          XCTest=43   swift-testing=0   skipped=0   该包失败=no'
check 'B 只跳过'            'ShapeB          XCTest=77   swift-testing=0   skipped=1   该包失败=no'
check 'C 单数失败'          'ShapeC          XCTest=12   swift-testing=0   skipped=0   该包失败=YES'
check 'D 跳过+失败'         'ShapeD          XCTest=77   swift-testing=0   skipped=1   该包失败=YES'
check 'E 单数用例'          'ShapeE          XCTest=1    swift-testing=0   skipped=0   该包失败=no'
check 'F 纯 swift-testing'  'ShapeF          XCTest=0    swift-testing=6   skipped=0   该包失败=no'
check '总计 216 个测试'      '合计：216 个测试，2 个失败，2 个跳过'
check '失败的包两个都点名'   '失败的包：ShapeC ShapeD'

echo
[[ $fail == 0 ]] && echo '夹具通过：六种形态都取对了数。' || echo '夹具失败。'
exit $fail
