#!/bin/zsh
# P6.2b「还原度收口」取证：概览页两处（「全部」的 › affordance、sparkline 满轴）
# 与守护页一处（行分隔线：卡外的标题行 + 通栏卡 + 卡内平铺行）。
#
# 为什么 sparkline 那一张要等 30 秒：这一屏没有历史注入钩子，12 格横轴只能等真实采样
# 长满（每 2 秒一格）。给截图编一段假历史是最容易的做法，也是最坏的做法——
# 照片上那些柱子没有一处能回到磁盘或内核计数器上。所以这一档的代价是时间，不是新钩子。
#
# 八档各拍什么：
#   01 概览首帧：横轴已经满宽（改前只有一根 10pt 细柱贴在左边）
#   02 概览长满：12 格真实采样 + 「全部 ›」
#   03 守护页真机态：占用两行 + 登录项列表的分隔线
#   04 守护页夹具态：TCC partial（通栏警示条 + 授权行 + 卡内脚注）与登录项 rows（含异常徽章的第三行）
#   05 守护页首帧：MM_GUARDIAN_LOAD=hold，骨架行在通栏卡里的留白
#   06 占用行图标环：camera=inuse + mic=idle 同屏，红环/红底与中性环的唯一取证
#   07 系统活动卡：MM_GUARDIAN_ACTIVITY_FIXTURE=rows（实现独有、稿 06 没画的那第 4 张卡）
#      —— 同屏的 TCC/登录项两卡被换成矮夹具态把它顶进画面，那两卡的内容在本张不作依据
#   08 登录项"没对表"档：indeterminate 脚注在卡内的分隔线（TCC 卡同样压矮）
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
#     一直没拍过的原因是它**根本不在取景范围内**：这张卡排在最后，而它上面那张"读不到"的
#     TCC 空态卡有 ~600pt 高，真机 17 条登录项再叠一层——760pt 窗口里第 4 张卡永远在折叠线下。
#     所以这一档要同时做三件事：窗口拉高到 1000pt（屏 1920x1080pt，再高会被系统裁），
#     并把上面两张卡换成**矮的夹具态**（`MM_TCC_FIXTURE=rows`、`MM_GUARDIAN_LOGIN_FIXTURE=empty`）。
#     代价写在这里：这张照片上的 TCC 行与"登录项为空"**都不是本机状态**，只是为了把第 4 张卡顶进画面；
#     它证明的是活动卡 `rows` 档的排版，别的一概不作依据。
#     等待 25 秒不是保守：夹具分支**先真跑一次** `ActivityScanner.scan()`（含 `log show` 子进程，
#     秒级）再顶替展示数据，8 秒时拍到的还是覆盖前的空态——第一次就是这么踩到的。
shot 07-guardian-activity-rows 25 guardian \
     MM_WINDOW_SIZE=1100x1000 MM_TCC_FIXTURE=rows MM_GUARDIAN_LOGIN_FIXTURE=empty \
     MM_GUARDIAN_ACTIVITY_FIXTURE=rows
# 08：登录项"这一轮没对表"那一档（脚注在卡内、上面压一条分隔线），04 拍的是 rows 档、看不到它。
#     同理需要拉高窗口 + 压矮 TCC 卡，否则登录项卡本身就在折叠线下。
shot 08-guardian-login-indeterminate 8 guardian \
     MM_WINDOW_SIZE=1100x1000 MM_TCC_FIXTURE=rows \
     MM_GUARDIAN_LOGIN_FIXTURE=indeterminate

print -r -- "→ $OUT"
print -r -- "侧栏分隔线量法：swift Scripts/pixel-probe.swift $OUT/03-guardian-rows.png scan y 120 200 260"
