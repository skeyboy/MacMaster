#!/bin/zsh
# P6.6 取证：优化页四 tab 的夹具档位（fidelity-optimizer §5 #1–#7）。
#
# 立项原因：`MM_OPTIMIZER_FIXTURE`（`969e548`，2026-09-30）把 §6 #1 建议的档位全部落地了，
# 但**一条照片都没拍过**——`grep -r MM_OPTIMIZER_FIXTURE Scripts/` 当时 0 命中。
# 也就是说这六行一直卡在"能力就绪、尚未取证"，不是"验不了"。这个脚本把它一次结掉。
#
# 全程零合成点击：夹具在 OptimizerView 的 `.task` 里注入（`MMOptimizer.swift:74`），
# tab 由 `MM_OPEN_TAB` 决定，所以每一档都是"应用自己在正常渲染里走到那个状态"。
# 按 pid 抓自己的窗口，抓完即杀，只 kill 自己起的进程。
#
# 判据不只在照片里：非法取值那一档（12）的**结论在 stderr**，照片只证明"没半生效"。
#
#   ./Scripts/p66-optimizer-capture.sh <app 路径> <输出目录> [light|dark]
#   ONLY=07 ./Scripts/p66-optimizer-capture.sh ...   # 只跑某一档
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}

mkdir -p "$OUT"

# shot <文件名> <等待秒> <tab> <环境变量...>
shot() {
  local name=$1 settle=$2 tab=$3; shift 3
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=optimizer MM_OPEN_TAB="$tab" \
      "$@" "$APP/Contents/MacOS/MacMaster" >"$log" 2>&1 &
  local pid=$!
  sleep "$settle"
  local wid
  wid=$(swift Scripts/window-ids.swift --pid "$pid" 2>/dev/null \
        | sed -n 's/^windowid=\([0-9]*\).*/\1/p' | head -1)
  if [[ -z "$wid" ]]; then
    print -u2 -- "⚠ $name：pid=$pid 没有可见窗口（不产出空照片）"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid settle=${settle}s tab=$tab"
}

# 01 无夹具首帧：不注任何夹具，页面自己开真扫（`scanIfNeeded`）。等 3 秒正是**扫描中态**——
#    §5 #2 那条原本写着"要 HOLD 钩子才拍得到"，其实真实扫描本身就慢到能被抓拍：
#    进度条 / 骨架 / 「停止」按钮都在这一帧里。这一步同时是"生产路径没被夹具改坏"的回归证据。
shot 01-optimizer-duplicates-scanning 3 duplicates
# 02 §5 #1 分组卡：4 组确定分组（路径全在 `/tmp/mm-optimizer-fixture/` 下，一眼可辨），headline 走
#    「N 组 · M 个文件内容完全相同 · 每组保留一份后可释放 X」，末列是"需保留"禁用态。
shot 02-optimizer-duplicates-groups 6 duplicates MM_OPTIMIZER_FIXTURE=duplicates:4
# 03 §5 #1 的 caveat 横幅：本轮新加的 `caveat:unreadable:N` / `caveat:dataless:N` 两档
#    （横幅文案是按这两个数拼句子的，只给一类就不该出现分号）。
shot 03-optimizer-duplicates-caveat 6 duplicates \
  MM_OPTIMIZER_FIXTURE=duplicates:3,caveat:unreadable:2,caveat:dataless:1
# 04 §5 #5 PROTECTED 拒绝态回执（08d 底部 + 面板橙底）。只给 2 组：失败面板挂在列表**下方**，
#    窗口高度钳在约 1080pt，靠"缩短上方内容"把它顶进画面（见 hook-ledger §5），
#    并把窗口拉高到 1000pt 兜底。不触发任何真实删除。
shot 04-optimizer-duplicates-protected 6 duplicates \
  MM_OPTIMIZER_FIXTURE=duplicates:2,protected MM_WINDOW_SIZE=1320x1000
# 05 §5 空态两档之一：未扫过（「按文件内容比对，不看文件名。」）。
shot 05-optimizer-duplicates-never-scanned 6 duplicates MM_OPTIMIZER_FIXTURE=duplicates:empty
# 06 另一档：扫过但没有（「未发现内容完全相同的文件。」）——与 05 必须是两句话。
shot 06-optimizer-duplicates-scanned-empty 6 duplicates MM_OPTIMIZER_FIXTURE=duplicates:scannedEmpty
# 07 §5 #3/#4 浏览器缓存列表（08c 右）：三行 + 末位 size=nil 渲染成「测量中」。
#    夹具只给三行（Safari/Chrome/示例浏览器），稿上画的是四台浏览器——这条差异记进文档，不改夹具。
shot 07-optimizer-browser-rows 6 browser MM_OPTIMIZER_FIXTURE=browser:rows
# 08 浏览器空列表档。
shot 08-optimizer-browser-empty 6 browser MM_OPTIMIZER_FIXTURE=browser:empty
# 09 §5 #6 系统状态"全只读"三行（08d 右）：真机上 host_statistics64 / 卷读取 / 废纸篓
#    不会同时失败，只有夹具能凑齐。
shot 09-optimizer-status-all-readonly 6 status MM_OPTIMIZER_FIXTURE=status:allReadOnly
# 10 §5 #7 devtools 两档（08e 推演档）：未安装 → 位置按默认规则算、不给 owner 命令实跑；
#    读不到 → 大小与状态都不知道，**不显示数字**。两档都不给 bytes。
shot 10-optimizer-devtools-not-installed 6 devtools MM_OPTIMIZER_FIXTURE=devtools:notInstalled
shot 11-optimizer-devtools-unreadable 6 devtools MM_OPTIMIZER_FIXTURE=devtools:unreadable
# 12 夹具守卫：含非法取值 → 整批作废并写 stderr（判据在 .log 里，不是照片）。
#    这一张证明的是"没有半生效"：照片应当停在未注入的样子。
shot 12-optimizer-fixture-invalid-voided 6 duplicates MM_OPTIMIZER_FIXTURE=duplicates:2,devtools:notinstal

print -r -- "→ $OUT（$APPEARANCE）"
