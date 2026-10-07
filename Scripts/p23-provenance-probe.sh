#!/bin/zsh
# P23 同源门禁的否证表：一次跑完四档，把"这道门禁到底拦得住什么、不该拦什么"变成可重跑的数。
#
# 为什么要有这一支（P22 那一轮的账）：P22 收口时九张照片全部重拍，起因是照片拍在
# "搬完辅助函数、还没重新构建"的那一份产物上——而当时纸面上的两行归因
# （`# repo:` 与 `MMGitCommit`）**逐字相同**。门禁立起来之后，它拦得住什么、
# 不该拦什么，不能只写在注释里：注释不能证伪。
#
# 四档：
#   ① 加一个进编译的未跟踪源文件（commit 短sha 与 `-dirty` 两行都不变）
#      → 两个 capture 脚本都必须拒：exit 4，输出目录里一个文件都不许有
#   ② 加一个**测试**源码文件（未进编译输入集合）→ 指纹不许变。
#      这条是防误伤的：改判据不改产物，为此拒拍就是逼人把门禁关掉
#   ③ 拿不带 MMSourceDigest 键的旧产物 → 必须拒，且第二行的 app 侧写"无这一键"
#      （没有这一档的话，"读不到"会被读成"一样"）
#   ④ 当前树 + 当前产物 → 必须放行（用 ONLY 挡掉所有档名，只跑检查、一张都不拍）
#      这条钉住门禁不是一句永远失败的死话
#
# 全程只往工作区里加**未跟踪**文件、退出时删掉（trap）；不动任何已提交的源码。
# 产物归因头由被调用的 capture 脚本自己写，这一支只打结论行。
#
#   ./Scripts/p23-provenance-probe.sh <本轮产物> [旧产物（无指纹键的那一份）] \
#       > docs/verification/p23-provenance/probe.log
set -e

cd "$(dirname "$0")/.."
APP=${1:?用法: ./Scripts/p23-provenance-probe.sh <app> [旧 app]}
OLD_APP=${2:-}
source "$(dirname "$0")/mm-provenance.sh"

SRC_PROBE=Sources/MacMaster/P23Probe.swift
TEST_PROBE=Packages/MMDisk/Tests/MMDiskTests/P23ProbeTests.swift
TMP=/tmp/mm-p23-probe-out
mkdir -p "$TMP"
probe_cleanup() { rm -f "$SRC_PROBE" "$TEST_PROBE"; }
trap probe_cleanup EXIT

puts() { print -r -- "$*"; }

# shot_count <dir>：那一族到底出了几张片。0 才是"一张都不出"。
# 目录压根没建也算 0——被拒的一族连 `mkdir -p "$OUT"` 都不该走到，那是更硬的一步。
shot_count() {
  if [[ -d $1 ]]; then find "$1" -type f | wc -l | tr -d ' '; else echo 0; fi
}

# run_refusing <档名> <脚本> <app>：跑一次，回显"退出码 / 出了几张片"。
# 两处都判：exit 必须是 4，而且一张都不许出——只退码不出片，等于照片已经污染了证据目录。
run_refusing() {
  local label=$1 script=$2 app=$3
  rm -rf "$TMP/$label"
  local code=0
  ONLY=zz-none-of-these-shots ./"$script" "$app" "$TMP/$label" >"$TMP/$label.err" 2>&1 || code=$?
  local n=$(shot_count "$TMP/$label")
  puts "  $label：exit=$code 产出=$n 张"
  sed -n 's/^# digest: /      digest: /p' "$TMP/$label.err" || true
  if [[ $code != 4 || $n != 0 ]]; then
    puts "  ✗ 这一档该拒（exit 4、0 张）而它没有：门禁漏了"
    fails=$((fails+1))
  else
    puts "  ✓ 拒了，且目录里什么都没有"
  fi
}

puts "# p23-provenance-probe.sh  $(date '+%Y-%m-%d %H:%M:%S %z')"
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
puts "# repo: $repoTag branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
mm_provenance_check "$PWD" "$APP" || true
mm_provenance_line
puts "# 门禁期望：① 拒 ② 不变 ③ 拒 ④ 放行。任一条不成立这一支就打出 ✗。"
puts ""

fails=0

puts "① 多一个进编译的未跟踪源文件（commit 两行都不变）"
probe_cleanup
printf 'import Foundation\n\n// P23 否证探针：这一支跑完就删\nenum P23Probe { static let tag = "p23" }\n' >"$SRC_PROBE"
with_probe=$(mm_source_digest "$PWD")
puts "  基线指纹 $MM_TREE_DIGEST → 加探针之后 $with_probe"
if [[ $with_probe == "$MM_TREE_DIGEST" ]]; then
  puts "  ✗ 指纹没变：加了编译输入而门禁看不见，这道检查形同虚设"; fails=$((fails+1))
else
  puts "  ✓ 指纹变了（而 MMGitCommit 那两行不变——这正是旧归因看不见的那一类）"
fi
run_refusing 01-p7-refuse Scripts/p7-release-check.sh "$APP"
run_refusing 01-disk-skip-refuse Scripts/p22-disk-skip-capture.sh "$APP"

puts ""
puts "② 只加测试源码（不进编译输入集合）"
probe_cleanup
base=$(mm_source_digest "$PWD")
printf 'import XCTest\n\n// 只加判据不改产物的那一类改动\nfinal class P23ProbeTests: XCTestCase {}\n' >"$TEST_PROBE"
with_test=$(mm_source_digest "$PWD")
puts "  基线指纹 $base → 加测试文件之后 $with_test"
if [[ $base == "$with_test" ]]; then
  puts "  ✓ 指纹不变：改判据不该拦截图"
else
  puts "  ✗ 指纹变了：测试源码误伤，人会把这个门禁关掉"; fails=$((fails+1))
fi

puts ""
puts "③ 产物不带 MMSourceDigest 键"
probe_cleanup
if [[ -n $OLD_APP && -e $OLD_APP/Contents/Info.plist ]]; then
  local_code=0
  # 路径要打进日志：这一档的证据是"**那一份**产物没有键"，不留名的话日志只能自证"有个东西没键"。
  puts "  旧产物：$OLD_APP"
  mm_provenance_check "$PWD" "$OLD_APP" || local_code=$?
  puts "  exit=$local_code（期望 1）"
  mm_provenance_line
  if [[ $local_code == 1 ]]; then puts "  ✓ 无键当不同源处理"; else
    puts "  ✗ 无键被放过了"; fails=$((fails+1)); fi
else
  puts "  （跳过：没给旧产物路径，期望第二参数传一份 P23 之前构建的产物）"
fi

puts ""
puts "④ 当前树 + 当前产物必须放行（ONLY 挡掉所有档名，只跑检查）"
mm_provenance_check "$PWD" "$APP" && puts "  ✓ 同源，检查通过" || {
  puts "  ✗ 该放的没放："; mm_provenance_line; fails=$((fails+1)); }

puts ""
puts "⑤ 接了门禁的脚本，在同源产物上一档都不拍也要能正常退出"
# 这一档防的是反方向的失效：把检查写成永远失败，跟没有检查一样坏，
# 而且更糟——下一次真出问题没人再看它的输出。
# 只收"ONLY 挡掉全部档名 = 合法空跑"的那两支（p68-disk / p22-disk-skip）。
# p17-website 与 p18-hook 各跑一次**真**档才有意义：前者收尾要 glob `$OUT/0*.png` 做自检，
# 后者把"一档都没跑"判成 exit 2（那是它们自己的防呆，不是门禁拦的，本轮实测过）。
# p7-release-check 没有 ONLY 过滤器，它放行的那三张就是本轮归档的 p23-v1。
run_passing() {
  local label=$1 script=$2; shift 2
  rm -rf "$TMP/$label"
  local code=0
  ONLY=zz-none-of-these-shots EVIDENCE="$TMP/$label" ./"$script" "$APP" "$TMP/$label" "$@" \
    >"$TMP/$label.err" 2>&1 || code=$?
  puts "  $label：exit=$code 产出=$(shot_count "$TMP/$label") 张"
  if [[ $code != 0 ]]; then
    puts "  ✗ 同源却退非零：这条门禁会把正常取证一起挡掉"; fails=$((fails+1))
    sed -n '1,3p' "$TMP/$label.err" | sed 's/^/      │ /'
  else
    puts "  ✓ 放行"
  fi
}
run_passing 05-p68-disk Scripts/p68-disk-capture.sh
run_passing 05-disk-skip Scripts/p22-disk-skip-capture.sh

puts ""
if [[ $fails == 0 ]]; then puts "五档全部符合预期（✗ 计数 0）"
else puts "✗ 计数 = $fails"; exit 1; fi
