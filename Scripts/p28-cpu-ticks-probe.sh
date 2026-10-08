#!/bin/zsh
# P28 的发版门禁否证探针：直接读 `host_cpu_load_info` 的四个累计 tick，量"两次采样之间总 tick
# 到底会不会不前进"。
#
# 为什么要有这一支：`DashboardMetricsTests.testCPULoadSampleRangeOnRealMachine` 在作者机上
# 整包跑到这一条时红过一次（单跑全绿），而它红的那一句是 `XCTAssertNotNil(load)`，
# 也就是 `SystemSampler.load(from:to:)` 给出了 nil——唯一的路径是 `deltaTotal <= 0`。
# 那一轮的判据假设是"0.25 s 的跨度里 tick 一定在走"，而这条假设**从来没有被量过**。
# 这一支就是把它量出来：能重跑、每帧都打增量，不再靠"应该是这样"。
#
#   ./Scripts/p28-cpu-ticks-probe.sh > docs/verification/p28-cpu-probe/probe.log
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
FRAMES=${FRAMES:-12}
INTERVAL_MS=${INTERVAL_MS:-250}

print -r -- "# p28-cpu-ticks-probe.sh  $(date '+%Y-%m-%d %H:%M:%S %z')"
print -r -- "# repo: $(git -C "$ROOT" rev-parse --short HEAD)$([[ -n $(git -C "$ROOT" status --porcelain -uno 2>/dev/null) ]] && echo -dirty) branch=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
print -r -- "# 编译器: $(swift --version 2>&1 | head -1)"
print -r -- "# 机器: $(sw_vers -productVersion) / $(uname -m) / kern.boottime=$(sysctl -n kern.boottime)"
print -r -- "# 量法：$FRAMES 帧，每帧间隔 $INTERVAL_MS ms，读同一份 host_cpu_load_info（HOST_CPU_LOAD_INFO）"
print -r -- "# 判读：total_delta 只要有一帧 ≤ 0，'跨度必然 > 0' 这条前提就当场不成立"

FRAMES=$FRAMES INTERVAL_MS=$INTERVAL_MS xcrun swift "$ROOT/Scripts/p28-cpu-ticks-probe.swift"
