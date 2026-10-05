#!/bin/zsh
# P6.8「安装来源九档」取证：把 docs/verification/p7-brew/ 那批 P5.2 手工照片变成可重跑脚本。
#
# 背景：p7-brew 那批照片是真的，但仓库里除夹具（Scripts/provenance-fixture.sh）外没有任何
# 脚本会再拍一遍——改这块详情面板/确认面板的人拿不到回归对照。这一轮补上重跑能力。
# 照片改写到 docs/verification/p68-brew/，绝不覆盖 p7-brew（那是已提交证据）。
#
# 为什么 01–08 都能零点击：这一屏要"动手"的状态全有钩子替身——
# 选中哪一行 = MM_UNINSTALL_SELECT=<bundleName> 点名（点不到就宁可拍空态，见 confirmationTarget）；
# 面板弹不弹 = MM_UNINSTALL_CONFIRM_MODE（none=只拍列表与详情，省略=沿用旧口径 appOnly 自动弹）；
# 假 home + 假 brew 账本 = MM_UNINSTALL_CONFIRM_FIXTURE_HOME（只认 /tmp，见 UninstallFixtureHooks）。
# 全程不碰鼠标：合成点击会逃逸到用户的其它应用（老规矩）。
#
# 来源五档本身不需要"点"任何来源：是夹具让每一行各缺一种凭据——
#   01 Highball  staged 链接解析后与 bundle 同一文件（设备号+inode）→ brew 强档
#   02 CodeEdit  账本在、staged 链接指向不存在的路径 → 疑似 brew（不给命令）
#   03 Firefox   firefox 与 firefox-beta 两份账本抢同一个 bundle → 歧义（不给徽章）
#   04 WeChat    Contents/_MASReceipt → App Store
#   05 MysteryApp 什么凭据都没有 → 无法判定（也不给"手动安装"）
#
#   ./Scripts/p68-brew-capture.sh <app 路径> <输出目录> [light|dark] [宽x高]
#   ./Scripts/p68-brew-capture.sh /tmp/mm-app-p68uninst/MacMaster.app docs/verification/p68-brew
#   ONLY=04 ./Scripts/p68-brew-capture.sh … 只重拍 04 那一档
#   FIX=/tmp/已有夹具 ./Scripts/p68-brew-capture.sh … 复用现成夹具（默认每次现造一棵新的）
#
# 09 是真机档：不注入夹具、读真 /opt/homebrew，画面内容随机器与时间变，与 01–08 天然不可比。
# 抓完即杀，且只 kill 自己起的 pid。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SIZE=${4:-}
# 夹具默认每次现造：provenance-fixture.sh 用 mktemp 起新目录，staged 链接的设备号判据
# 依赖"链接指向的就是这棵树里的这份 bundle"，拿旧目录重跑没坏，但照片里的路径会指着
# 一次没发生过的运行——新造一棵，日志与照片至少对得上同一次。
FIX=${FIX:-$(./Scripts/provenance-fixture.sh)}
[[ -d $FIX ]] || { print -u2 -- "夹具不存在：$FIX（先跑 ./Scripts/provenance-fixture.sh）"; exit 2; }
SETTLE=${SETTLE:-8}
# 09 真机档要等真实应用清单测完（旧照片拍到的是"31/44 测量中"的中间态，也算合格），
# 夹具档扫描是毫秒级，8 秒全花在 SwiftUI 排版上。
REAL_SETTLE=${REAL_SETTLE:-45}

mkdir -p "$OUT"

# shot <文件名> <等待秒> <环境变量...>
# 公共部分（模块/外观/尺寸）在这里统一注入；夹具 home 与各档钩子由 "$@" 自带，
# 好让 09 那一档能干净地"不注入夹具"。尾部重复变量覆盖同名前值（MM_APPEARANCE 靠这点做逐档特例）。
shot() {
  local name=$1 settle=$2; shift 2
  # ONLY=04 ./Scripts/p68-brew-capture.sh … 只重拍一档：九档各起一次应用，改一处文案全跑太慢。
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  # 归因头：日志得自己说清这张是拿哪些变量拍的。09 真机档没有夹具哨兵，
  # 点名了哪个应用（REAL_SELECT）只有写下来才事后对得上；夹具档同理，
  # 否则照片旁边那份 .log 只证明"进程起过"，不证明"注入过什么"。
  print -r -- "# p68-brew-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP  fixture=$FIX" >"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=uninstaller ${SIZE:+MM_WINDOW_SIZE=$SIZE }$*" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=uninstaller \
      ${SIZE:+MM_WINDOW_SIZE="$SIZE"} "$@" "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
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

# 01–05 的共同前缀：假 home 夹具 + 面板不弹（弹了会盖掉这一轮真正要拍的列表与详情）。
# 用数组而不是函数：函数名会当命令传给 env，数组在 shot 的参数位上逐元素展开。
brew=(MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$FIX" MM_UNINSTALL_CONFIRM_MODE=none)

# 01 brew 强档：详情徽章「Homebrew cask · highball」+ 来源凭据指假账本 + 对应命令。
shot 01-fixture-homebrew-cask "$SETTLE" $brew MM_UNINSTALL_SELECT=Highball
# 02 疑似 brew：行内橙色 chip，详情不给「对应命令」这一行（弱证据不配会改动系统的指令）。
shot 02-fixture-name-only "$SETTLE" $brew MM_UNINSTALL_SELECT=CodeEdit
# 03 歧义：两份账本抢同一个 bundle，列表与详情都不给徽章，判定依据点名 firefox 与 firefox-beta。
shot 03-fixture-ambiguous-device-identity "$SETTLE" $brew MM_UNINSTALL_SELECT=Firefox
# 04 App Store：_MASReceipt 档，来源行「Mac App Store」，没有来源凭据/对应命令两行。
shot 04-fixture-app-store "$SETTLE" $brew MM_UNINSTALL_SELECT=WeChat
# 05 无法判定：不给徽章也不说"手动安装"。
shot 05-fixture-unknown "$SETTLE" $brew MM_UNINSTALL_SELECT=MysteryApp
# 06 确认面板：省略 MM_UNINSTALL_CONFIRM_MODE → appOnly 自动弹，面板带「来源」行 + 橙色 brew 提醒。
shot 06-fixture-confirm-sheet "$SETTLE" MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$FIX" MM_UNINSTALL_SELECT=Highball
# 07 深色档：与 01 同一态，只换外观（尾部 MM_APPEARANCE 覆盖公共注入）。
shot 07-fixture-dark "$SETTLE" MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$FIX" MM_UNINSTALL_CONFIRM_MODE=none \
     MM_UNINSTALL_SELECT=Highball MM_APPEARANCE=dark
# 08 最小窗口：请求 900×600（窗口有 1000 宽下限，会被夹住），看「来源凭据」长路径折行不重叠。
shot 08-fixture-min-window "$SETTLE" MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$FIX" MM_UNINSTALL_CONFIRM_MODE=none \
     MM_UNINSTALL_SELECT=Highball MM_WINDOW_SIZE=900x600
# 09 真机档：不注入夹具，来源读真 /opt/homebrew 的 Caskroom。这一档画面是真数据，
#     没有假路径可当哨兵——它的哨兵是"与夹具同一套代码路径"（见 §12）。
#     点名目标可覆盖：P5.2 当时点的是 Highball，而本机后来把它卸了（/Applications 里
#     没有 Highball.app，只剩 Caskroom 账本——那正是 §8.3 说的"悬空链"态），
#     点名落空时日志会诚实写「没有对应的应用」，照片落"未选择应用"空态。
REAL_SELECT=${REAL_SELECT:-Highball}
shot 09-real-machine "$REAL_SETTLE" MM_UNINSTALL_SELECT="$REAL_SELECT"

print -r -- "→ $OUT"
print -r -- "转 jpeg（与 p7-brew 同格式，可选）：for f in $OUT/*.png; do sips -s format jpeg -Z 1400 \"\$f\" --out \"\${f%.png}.jpg\" >/dev/null; done"
