#!/bin/zsh
# P6.2b「还原度收口」取证：概览页两处（「全部」的 › affordance、sparkline 满轴）
# 与守护页一处（行分隔线：卡外的标题行 + 通栏卡 + 卡内平铺行）。
#
# 为什么 sparkline 那一张要等 30 秒：这一屏没有历史注入钩子，12 格横轴只能等真实采样
# 长满（每 2 秒一格）。给截图编一段假历史是最容易的做法，也是最坏的做法——
# 照片上那些柱子没有一处能回到磁盘或内核计数器上。所以这一档的代价是时间，不是新钩子。
#
# 十档各拍什么：
#   01 概览首帧：横轴已经满宽（改前只有一根 10pt 细柱贴在左边）
#   02 概览长满：12 格真实采样 + 「全部 ›」
#   03 守护页真机态：占用两行 + 登录项列表的分隔线
#   04 守护页夹具态：TCC partial（通栏警示条 + 授权行 + 卡内脚注）与登录项 rows（含异常徽章的第三行）
#   05 守护页首帧：MM_GUARDIAN_LOAD=hold，骨架行在通栏卡里的留白
#   06 占用行图标环：camera=inuse + mic=idle 同屏，红环/红底与中性环的唯一取证
#   07 系统活动卡：MM_GUARDIAN_CARDS=activity + MM_GUARDIAN_ACTIVITY_FIXTURE=rows
#      （实现独有、稿 06 没画的那第 4 张卡；单独取景，理由见该段注释）
#   08 登录项"没对表"档：CARDS=login + indeterminate 脚注在卡内的分隔线
#   09 登录项"扫描报错"档：CARDS=login + 页面顶部黄条（scanErrors 非空即出条，两条失败原文）
#   10 活动卡 empty 档：CARDS=activity + 单行空态在通栏卡里的留白
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
# 06：本机没有摄像头也没有麦克风，03/04/05 里占用两行永远是 absent 态——**图标环的红/中性规则
# 一张都拍不到**。只有夹具能同时摆出 live（红环 + 红底）与 idle（中性环 + 绿色只在右侧徽章），
# 所以这一档不是补充，是那条判据唯一的取证路径。
shot 06-guardian-ring-fixture 8 guardian MM_GUARDIAN_FIXTURE=camera=inuse,mic=idle
# 07：系统活动卡是实现独有的第 4 张卡，钩子 `MM_GUARDIAN_ACTIVITY_FIXTURE` 早就有、一直没拍过。
#     一直没拍过的原因是它**根本不在取景范围内**：这张卡排在最后，760pt 窗口里永远在折叠线下。
#     第一版的手法是"拉高窗口 + 把上面两张卡换成矮夹具态"，实测两条都不成立：
#       ① 窗口拉不高——屏高 1080pt，`MM_WINDOW_SIZE=1400x…` 会被 AppKit 夹到 ~1050（夹取后的
#          真实尺寸由 `LaunchBehavior` 回读，不是我们请求的那个数）；
#       ② 夹具压矮不可复现——`MM_GUARDIAN_LOGIN_FIXTURE=rows` 是 7 行 ≈500pt，换 `empty` 那张
#          空态卡（图标 + 居中一行）**比 3 行还高**，第 4 张卡进不进画面取决于三张卡的随机高度。
#     所以改成 `MM_GUARDIAN_CARDS=activity`：只渲染要拍的那张卡，位置由钩子钉死而不是由高度碰运气。
#     代价写清楚：这一张证明的是**活动卡自身的排版**，不证明卡片顺序、卡间距与整页留白
#     （那几条仍由 03/04/05/06 负责）。
#     等待 25 秒不是保守：夹具分支**先真跑一次** `ActivityScanner.scan()`（含 `log show` 子进程，
#     秒级）再顶替展示数据，8 秒时拍到的还是覆盖前的空态——第一次就是这么踩到的。
shot 07-guardian-activity-rows 25 guardian \
     MM_GUARDIAN_CARDS=activity MM_GUARDIAN_ACTIVITY_FIXTURE=rows
# 08：登录项"这一轮没对表"那一档（脚注在卡内、上面压一条分隔线），04 拍的是 rows 档、看不到它。
#     取景同样走 `MM_GUARDIAN_CARDS=login`：登录项卡单独渲染时 ~490pt，760pt 窗口装得下整张卡。
shot 08-guardian-login-indeterminate 8 guardian \
     MM_GUARDIAN_CARDS=login MM_GUARDIAN_LOGIN_FIXTURE=indeterminate
# 09：§6.6.5 剩下的两档之一。拍的不是卡内脚注而是**页面顶部的黄条**（`vm.scanErrors` 非空即在
#     ScrollView 第一行出条，排在所有卡之上），两条失败原文各一行、`lineLimit(2)`。
#     黄条不受取景钩子影响，所以这一档连 `CARDS=login` 一起给，画面里就只有"黄条 + 登录项卡"。
shot 09-guardian-login-scanerror 8 guardian \
     MM_GUARDIAN_CARDS=login MM_GUARDIAN_LOGIN_FIXTURE=scanerror
# 10：活动卡 `empty` 档——它只有一行文字，要看的正是"单行空态在通栏卡里的留白"，
#     这与 05 首帧骨架是同一类判据。
shot 10-guardian-activity-empty 25 guardian \
     MM_GUARDIAN_CARDS=activity MM_GUARDIAN_ACTIVITY_FIXTURE=empty

print -r -- "→ $OUT"
print -r -- "侧栏分隔线量法：swift Scripts/pixel-probe.swift $OUT/03-guardian-rows.png scan y 120 200 260"
