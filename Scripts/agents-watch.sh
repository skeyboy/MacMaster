#!/bin/zsh
# 并行施工进度探针：只看元数据，不读任何子代理的输出内容。
# 为什么这么判活：子代理的 transcript 文件持续增长 = 它还在产出；mtime 停滞而进程仍在
# 就是「假死/等输入」的信号，这时该去查它的进程树而不是猜。
# 用法：./Scripts/agents-watch.sh            # 概览
#      ./Scripts/agents-watch.sh -q         # 只打印异常行
setopt null_glob

ROOT=$(cd "$(dirname "$0")/.." && pwd)
QUIET=0
[[ "$1" == "-q" ]] && QUIET=1

stale_minutes() {  # 文件距上次修改多少分钟
  local f=$1
  local m=$(stat -f %m "$f" 2>/dev/null) || { print -- "-"; return; }
  echo $(( ( $(date +%s) - m ) / 60 ))
}

print -- "== 系统负载 =="
print -r -- "  $(uptime | sed 's/^.*load averages://')"
print -r -- "  正在编译/测试：$(pgrep -l -U $(id -u) swift-frontend | wc -l | tr -d ' ') 个 swift-frontend"
print -r -- "  本仓库实例：$(pgrep -f 'MacMaster.app/Contents/MacOS/MacMaster' | wc -l | tr -d ' ') 个 MacMaster 进程"
for pid in $(pgrep -f 'MacMaster.app/Contents/MacOS/MacMaster'); do
  print -r -- "    pid=$pid 已运行 $(ps -o etime= -p $pid | tr -d ' ')  路径=$(ps -o comm= -p $pid)"
done
# screencapture 卡住通常意味着 windowid 失效（实例已退出），会一直等
for pid in $(pgrep -x screencapture); do
  print -r -- "    ⚠ screencapture pid=$pid 已运行 $(ps -o etime= -p $pid | tr -d ' ')"
done

# transcript 不能当活性信号：实测所有 .output 都停在 ~169B 直到任务结束才刷盘，
# 用它判活会把正常干活的代理误判成假死。真正的活性信号只有副作用：写文件、起构建、留夹具。
print -- "\n== SwiftPM 全局锁（--scratch-path 也躲不开 manifest 缓存锁，并发构建会串行）=="
for l in "$TMPDIR"_Users_lee_Library_Caches_org.swift.swiftpm_manifests_manifest.db.lock "$HOME/Library/Caches/org.swift.swiftpm/manifests/"manifest.db; do
  [[ -e "$l" ]] && print -r -- "  $(basename "$l") $(stale_minutes "$l")min 前动过"
done

print -- "\n== 隔离构建足迹（约定名 /tmp/mmscratch-<模块>、/tmp/mmapp-<模块>）=="
for track in mmcleaner mmuninstaller mmdisk mmmonitor mmguardian mmoptimizer coordinator; do
  s="/tmp/mmscratch-$track"; a="/tmp/mmapp-$track"
  line=""
  [[ -d "$s" ]] && line="${line}scratch $(stale_minutes "$s")min 前 "
  [[ -d "$a" ]] && line="${line}appbundle $(stale_minutes "$a")min 前 "
  print -r -- "  $track ${line:-无足迹}"
done

print -- "\n== 各路写权限面（相对 HEAD 的改动数 / 最近一次写入距今）=="
typeset -A scopes
scopes=(
  mmcleaner     "Packages/MMCleaner docs/design-system/screens/mmcleaner docs/verification/mmcleaner docs/analysis/fidelity-cleaner.md"
  mmuninstaller "Packages/MMUninstaller docs/design-system/screens/mmuninstaller docs/verification/mmuninstaller docs/analysis/fidelity-uninstaller.md"
  mmdisk        "Packages/MMDisk docs/design-system/screens/mmdisk docs/verification/mmdisk docs/analysis/fidelity-disk.md"
  mmmonitor     "Packages/MMMonitor docs/design-system/screens/mmmonitor docs/verification/mmmonitor docs/analysis/fidelity-monitor.md"
  mmguardian    "Packages/MMGuardian docs/design-system/screens/mmguardian docs/verification/mmguardian docs/analysis/fidelity-guardian.md"
  mmoptimizer   "Packages/MMOptimizer docs/design-system/screens/mmoptimizer docs/verification/mmoptimizer docs/analysis/fidelity-optimizer.md"
  coordinator   "Sources/MacMaster Packages/MMUI docs/design-system/screens/shell docs/design-system/screens/mmui docs/verification/shell docs/analysis/fidelity-shell.md docs/design-system/tokens.css docs/design-system/screen.css docs/design-system/README.md"
)
for track in mmcleaner mmuninstaller mmdisk mmmonitor mmguardian mmoptimizer coordinator; do
  paths=(${(z)scopes[$track]})
  changed=$(git -C "$ROOT" status --porcelain -- "${paths[@]}" | wc -l | tr -d ' ')
  newest=$(ls -td "${paths[@]}"(N/) 2>/dev/null | head -1)
  # 目录 mtime 只反映增删文件，取该范围内最近被改的普通文件更准
  newest_file=$(find "${paths[@]}"(N) -type f -newermt '-3 hours' 2>/dev/null | head -50 | xargs -I{} stat -f '%m {}' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
  [[ -n "$newest_file" ]] && mins=$(stale_minutes "$newest_file") || mins="-"
  if (( QUIET == 0 )); then
    print -r -- "  ${track} 改动 ${changed} 项 · 最近写入 ${mins}min 前 · ${newest_file:-无}"
  fi
done

print -- "\n== 越界与遗留 =="
# 1) 未跟踪文件里散落在 /tmp 之外的临时产物
git -C "$ROOT" status --porcelain | grep -E '^\?\? ' | grep -vE 'docs/verification/|docs/analysis/|docs/design-system/|Packages/|Scripts/|Sources/' | sed 's/^/  未预期路径：/'
# 2) 构建隔离是否被绕过：仓库根 .build 最近是否被人动过
bmin=$(stale_minutes "$ROOT/.build")
print -r -- "  仓库根 .build 最近变动 ${bmin}min 前（并发期应基本静止，动它=有人没带 --scratch-path）"
print -r -- "  共享 app 包 mtime：$(stale_minutes "$ROOT/build/MacMaster.app")min 前"

print -- "\n== 各模块审计文档到位情况 =="
for d in docs/analysis/fidelity-shell.md docs/analysis/fidelity-cleaner.md docs/analysis/fidelity-uninstaller.md docs/analysis/fidelity-disk.md docs/analysis/fidelity-monitor.md docs/analysis/fidelity-guardian.md docs/analysis/fidelity-optimizer.md; do
  if [[ -f "$ROOT/$d" ]]; then
    print -r -- "  ✅ $d（$(wc -l < "$ROOT/$d" | tr -d ' ') 行，$(stale_minutes "$ROOT/$d")min 前更新）"
  else
    print -r -- "  ⏳ $d 尚未出现"
  fi
done
