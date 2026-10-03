#!/bin/zsh
# P6.2b「还原度收口」取证：概览页两处（「全部」的 › affordance、sparkline 满轴）
# 与守护页一处（行分隔线：卡外的标题行 + 通栏卡 + 卡内平铺行）。
#
# 为什么 sparkline 那一张要等 30 秒：这一屏没有历史注入钩子，12 格横轴只能等真实采样
# 长满（每 2 秒一格）。给截图编一段假历史是最容易的做法，也是最坏的做法——
# 照片上那些柱子没有一处能回到磁盘或内核计数器上。所以这一档的代价是时间，不是新钩子。
#
# 五档各拍什么：
#   01 概览首帧：横轴已经满宽（改前只有一根 10pt 细柱贴在左边）
#   02 概览长满：12 格真实采样 + 「全部 ›」
#   03 守护页真机态：占用两行 + 登录项列表的分隔线
#   04 守护页夹具态：TCC partial（通栏警示条 + 授权行 + 卡内脚注）与登录项 rows（含异常徽章的第三行）
#   05 守护页首帧：MM_GUARDIAN_LOAD=hold，骨架行在通栏卡里的留白
#
#   ./Scripts/p62b-capture.sh <app 路径> <输出目录> [light|dark] [宽x高]
#   ONLY=04 ./Scripts/p62b-capture.sh … 只重拍 04 那一档
#
# 全部零合成点击：勾选/展开这类状态一律由钩子在扫描落地时推到位。
# 抓完即杀，且只 kill 自己起的 pid。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SIZE=${4:-}

# 侧栏宽度：这里**不**清偏好，因为两个实验把"持久化把基线带偏"这个猜测证否了——
#   ① 往 SwiftUI 自己写的那条 `NSSplitView Subview Frames…` 里手改成 260pt 再启动：
#      分隔线仍停在 401px@2x = 200pt，退出时它又被写回 200（写了不等于被读）。
#   ② 把代码里的 ideal 从 220 改成 240 重新构建：屏幕上还是 200pt。
# 合起来是：首屏宽度取 min，ideal 与那条持久化记录都不参与。所以逐像素基线要靠代码里的
# min 保证，删键删的是一个不生效的杠杆——留着只会让下一个人以为基线由它兜住。
# 量法见脚本末尾：分隔线的 x 坐标 /2 就是 pt 值。

mkdir -p "$OUT"

# shot <文件名> <等待秒> <模块> <环境变量...>
shot() {
  local name=$1 settle=$2 module=$3; shift 3
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE="$module" \
      ${SIZE:+MM_WINDOW_SIZE="$SIZE"} "$@" "$APP/Contents/MacOS/MacMaster" >"$log" 2>&1 &
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
  print -r -- "✅ $name windowid=$wid settle=${settle}s"
}

shot 01-dashboard-first-frame 5  dashboard
shot 02-dashboard-history-full 30 dashboard
shot 03-guardian-rows        8  guardian
shot 04-guardian-fixture-rows 8 guardian \
     MM_TCC_FIXTURE=partial MM_GUARDIAN_LOGIN_FIXTURE=rows
shot 05-guardian-first-frame 4  guardian MM_GUARDIAN_LOAD=hold

print -r -- "→ $OUT"
print -r -- "侧栏分隔线量法：swift Scripts/pixel-probe.swift $OUT/03-guardian-rows.png scan y 120 200 260"
