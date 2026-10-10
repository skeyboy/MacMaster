#!/bin/zsh
# P31a「卸载前发现应用在跑」取证：运行状态那一档要拍到**系统真的在跑那个应用**。
#
# 为什么这一族没有假快照钩子：运行状态判的是"此刻有没有这个进程"，它是系统状态；
# 喂给界面的合成值只能证明"界面会写字"，证明不了"写的是真话"。所以
# `RunningAppProbe.snapshot()` 里没有读 env 的分支（理由原文写在它的注释上），
# 照片里的「正在运行 · 进程 NNN」来自 `Scripts/p31-running-fixture.sh` 造的那两棵
# /tmp 下的 bundle 被**真的启动**——pid、路径、包名全是 LaunchServices 给的。
# 代价是这一族必须管进程生命周期：只 kill 自己 `open` 起来的那几个 pid（记在日志里），
# 绝不碰用户的应用。
#
# 哨兵是 pid，不是路径：夹具 home 里的 /tmp 路径只证明"扫的是假 home"，
# 而这一屏要证明的是"那句话背后有进程"。所以每档的日志都写一行
# `# launched: <应用名> pid=<pgrep 拿到的数>`，照片里那个数必须与它一致；
# 对不上就是这张照片拍在别的时刻上，不作数。
#
# 为什么五档夹具 + 一档真机都能零点击：这一屏要"动手"的状态全有钩子替身——
#   选中哪一行 = MM_UNINSTALL_SELECT=<bundleName>（点不到就宁可拍空态）
#   面板弹不弹 = MM_UNINSTALL_CONFIRM_MODE（none=只拍列表与详情，省略=沿用旧口径 appOnly 自动弹）
#   假 home   = MM_UNINSTALL_CONFIRM_FIXTURE_HOME（只认 /tmp，见 UninstallFixtureHooks）
# 全程不碰鼠标：合成点击会逃逸到用户的其它应用（老规矩）。
#
#   ./Scripts/p31-running-capture.sh <app 路径> <输出目录> [light|dark] [宽x高]
#   ./Scripts/p31-running-capture.sh /tmp/mm-app-p31/MacMaster.app docs/verification/p31-running
#   ONLY=05 ./Scripts/p31-running-capture.sh … 只重拍 05 那一档
#   FIX=/tmp/macmaster-running-fixture.XXXXXX ./Scripts/p31-running-capture.sh … 复用现成夹具
#
# 各档依赖的启动状态（脚本按编号顺序自己摆好，重跑单档时要注意前序档留下的进程）：
#   01 02 03 04 —— Applications/RunningFoo 在跑，IdleFoo 与 ElsewhereFoo 没跑
#                  （03 拍的正是"同一张图里一行有 chip、一行没有"）
#   05        —— 先结束 RunningFoo，再启动 **Elsewhere/ElsewhereFoo**（与清单上那一份同包名、
#                  不同位置）。界面上那一行是 Applications 里那份从没跑过的拷贝，而它背后那个
#                  进程报出的是别处的位置——「只有包名对上」那一档的实物照片。
#   06        —— 三个都没跑，窗口开好之后脚本才 `open -g` IdleFoo：那一行从「未检测到」
#                  变成「正在运行」没有走过任何重载，唯一能把新进程读进去的路径就是
#                  NSWorkspace 的启动通知。这一档拍的是通知真的把界面刷新了，
#                  也是"夹具必须是 Cocoa 应用"的由来：命令行 sleep 进程不发启动通知。
#   07        —— 真机档：不注入夹具，点名本机此刻真在跑的 /Applications 应用（默认 WeChat）。
#                它给出的真样本是"同一个位置对上两个号"：1094 是主程序（包名与位置都报得出），
#                1276 是包内的 wxplayer（报不出包名，但快照里报出的位置就是外层这个 .app），
#                两条都算"按位置对上"，所以界面写「正在运行 · 2 个进程（1094、1276）」。
#                这一档随机器状态变：换成别的机器或那个应用没开着，照片会落在「未检测到」，
#                日志里 `# real-running:` 那行会如实写"没有对应进程"。
# `undetermined`（快照里有既报不出包名也报不出位置的条目，且没有正对上）本机拍不出来：
# 当日两次现读（2026-10-10，参与判定 163 条 / 165 条，这个数随机器状态变）里那种条目都是 0 条。
# 它只有单测，这条如实记在 roadmap 里。
# 于是呈现层的四种结论里，照片覆盖三种（正在运行·就是这一份 / 正在运行·只有包名 / 未检测到），
# 只剩「无法判定」没有照片——不是漏了，是这台机器上那种进程不存在。
# 抓完即杀：MacMaster 的实例、以及我们自己 open 起来的夹具应用，都只 kill 记下的 pid。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SIZE=${4:-}
# 夹具默认每次新造：根是 mktemp 出来的，照片里的路径与日志里的 pid 要指向同一次运行。
# 复用现成的一棵用 FIX=…
FIX=${FIX:-$(./Scripts/p31-running-fixture.sh)}
[[ -x $FIX/Applications/RunningFoo.app/Contents/MacOS/RunningFoo \
   && -x $FIX/Applications/IdleFoo.app/Contents/MacOS/IdleFoo \
   && -x $FIX/Applications/ElsewhereFoo.app/Contents/MacOS/ElsewhereFoo \
   && -x $FIX/Elsewhere/ElsewhereFoo.app/Contents/MacOS/ElsewhereFoo ]] || {
  print -u2 -- "夹具不完整：$FIX（先跑 ./Scripts/p31-running-fixture.sh）"; exit 2; }

# 归因头 + 内容指纹门禁（配方见 mm-provenance.sh）：同一个 -dirty 底下可以是两份不同源码，
# 不等就一张都不出。用 -uno：本脚本正往证据目录里写未跟踪的 .log/.png。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p31 -s /tmp/mm-scratch-p31 重新构建再取证。"
  exit 4
fi

SETTLE=${SETTLE:-8}
# 真机档要等的是**整张列表的体积测量**：`.task` 里点名（`MM_UNINSTALL_SELECT`）排在
# `await model.loadApps()` 之后，而 loadApps 含测大小那一趟。这台机器现读 45 个应用
# 约 60–75 秒（45 秒时页头还是「已测 31 · 14 个测量中」，详情格是「未选择应用」；
# 75 秒才是「大小已实测」＋WeChat 被选中）。所以这一档的等待给到 90 秒。
REAL_SETTLE=${REAL_SETTLE:-90}
# 05 用：窗口出现后到 `open -g` 之间留给基线读取的时间，以及通知回来后的排版时间。
PRELAUNCH_BUFFER=${PRELAUNCH_BUFFER:-3}
POSTLAUNCH_SETTLE=${POSTLAUNCH_SETTLE:-6}
REAL_SELECT=${REAL_SELECT:-WeChat}

mkdir -p "$OUT"

# 我们自己 open 起来的夹具进程的 pid，收尾时只 kill 这些。
# LAUNCHED_PID 是 launch_bundle 的"返回值"（全局，不走命令替换，原因写在那个函数上）。
typeset -a LAUNCHED_PIDS
LAUNCHED_PID=""

# wants <档位名前缀>：ONLY 没设就是全跑。分组条件也用它，免得"重拍 07"时
# 还按旧顺序把前一档留下的进程一起带上画面。
wants() { [[ -z ${ONLY:-} || $1 == ${ONLY}* ]] }

# bundle_pid <夹具内相对目录>：例如 Applications/RunningFoo、Elsewhere/ElsewhereFoo。
# 用相对目录而不是应用名：ElsewhereFoo 在同一次运行里有两份**同包名**的拷贝，
# 07 那一档要证明的正是"跑着的是别处那一份"，按名字找会把两份混成一个。
# 匹配串写 $FIX 的 /tmp 拼法就够：`open` 把可执行路径按解析后的 /private/tmp/… 传下去
# （现读 ps 的 args 就是这样），而 pgrep -f 是子串匹配，两种拼法里都含这一段。
bundle_pid() {
  pgrep -f "$FIX/$1.app/Contents/MacOS/" 2>/dev/null | head -1
}

# launch_bundle <相对目录>：后台启动（-g 不抢前台），pid 留在**全局** LAUNCHED_PID 里。
# 不用 `X=$(launch_bundle …)` 这种取返回值的写法：命令替换是子 shell，
# 里面往 LAUNCHED_PIDS 的 append 会跟着子 shell 一起消失，收尾就漏杀
# （实跑 05 时真漏了一个 IdleFoo，是事后 pgrep 抓出来的）。
# 打印仍保留，是为了让调用方能直接把它写进日志行。
launch_bundle() {
  open -g "$FIX/$1.app"
  sleep 2
  LAUNCHED_PID=$(bundle_pid "$1")
  [[ -n $LAUNCHED_PID ]] || { print -u2 -- "✗ $1 启动后 pgrep 找不到进程，不拍依赖它的档位"; exit 3; }
  LAUNCHED_PIDS+=$LAUNCHED_PID
  print -r -- "$LAUNCHED_PID"
}

# quit_bundle <相对目录> <pid>：结束自己启动的那一份，等它真的消失——
# 05 依赖"窗口打开时它确实还没在跑"，靠猜不行。
quit_bundle() {
  local name=$1 pid=$2
  [[ -n $pid ]] || return 0
  kill "$pid" 2>/dev/null || true
  for i in {1..20}; do
    [[ -z $(bundle_pid "$name") ]] && return 0
    sleep 1
  done
  print -u2 -- "✗ $name（pid=$pid）没能在 20 秒内退出，依赖它停下来的那一档前提就不成立"
  exit 3
}

# main_window_id <pid> <日志文件>：把这个 pid 的窗口清单原样写进日志，再只认"标题正好是
# MacMaster 的那扇普通层窗口"，而且要求这样的窗口**正好一扇**。挑不到就返回 1 让调用方拒拍，
# 绝不退回 head -1：CGWindowList 是前→后的顺序，head -1 拿的是最靠前那扇，而最靠前的
# 未必是要拍的那一屏——实跑 05 就拍到过一扇盖在主窗口前面的设置窗，那张照片当场作废，
# 而日志里连"当时这个 pid 有几扇窗、各是什么标题"都没留下，事后无从判断是谁的窗口。
main_window_id() {
  local pid=$1 log=$2 quiet=${3:-} all wid n
  all=$(swift Scripts/window-ids.swift --pid "$pid" 2>>"$log" || true)
  [[ -n $quiet ]] || print -r -- "# windows(pid=$pid): ${all//$'\n'/ | }" >>"$log"
  n=$(printf '%s\n' "$all" | grep -c 'layer=0 title=MacMaster bounds=' || true)
  [[ $n == 1 ]] || return 1
  wid=$(printf '%s\n' "$all" | sed -n 's/^windowid=\([0-9]*\) .*layer=0 title=MacMaster bounds=.*/\1/p')
  [[ -n $wid ]] || return 1
  print -r -- "$wid"
}

# 收尾自查写在 cleanup 里，不写在脚本末尾：trap 既兜异常分支也兜正常跑完，
# 而写在末尾的版本是在 trap 之前读数——每次跑完都虚报一行"仍有进程在跑"
# （第一版就是这样，警告天天响，等于没有警告）。
# 一个都没启动过就不必自证（`ONLY=07` 的真机档、以及被 provenance 门禁挡回去的那次）。
#
# 但 trap 只在**显式 exit** 和正常走到末尾时跑：zsh 在 errexit 那条路上是直接退出的，
# EXIT 钩子一次都没执行（现测：`if true; then <返回 1 的函数>; fi` 配 set -e，
# 退出码 1、trap 里的 print 一行不出）。第一版_full run 就是这么把 IdleFoo 留在了系统里，
# 而屏幕上连"有残留"那句话都没说。所以 shot 的失败一律走 FAILED_SHOTS，
# 不让 errexit 抓到任何一条 shot 调用——收尾与点名都由正常路径完成。
cleanup() {
  if (( ${#LAUNCHED_PIDS[@]} == 0 )); then return 0; fi
  for pid in $LAUNCHED_PIDS; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  sleep 1
  leftover=$(pgrep -f "$FIX/" 2>/dev/null | tr '\n' ' ' || true)
  if [[ -n ${leftover// /} ]]; then
    print -u2 -- "⚠ 收尾后仍有本脚本启动的夹具进程在跑：$leftover（pid 全在各档日志的 # launched: 行里）"
  else
    print -r -- "✓ 夹具进程已全部结束（本脚本 open 起来的：${LAUNCHED_PIDS[*]}）"
  fi
}
trap cleanup EXIT

# shot <文件名> <等待秒> <环境变量...>：公共部分在这里统一注入，夹具 home 与各档钩子由
# "$@" 自带，好让 07 真机档能干净地"不注入夹具"。尾部重复变量覆盖同名前值。
# NOTE 是调用方写好的哨兵行（pid 归因），只进日志、不进环境变量。
# 拍不到窗口时它返回 1，但调用位一律接 `|| FAILED_SHOTS+=(…)`：
# 不能让 errexit 抓走整趟跑法——它一抓，EXIT 钩子就不执行了
# （上面 cleanup 那段记的就是这件事留下的那次漏杀）。
typeset -a FAILED_SHOTS
NOTE=""
shot() {
  local name=$1 settle=$2; shift 2
  if ! wants $name; then return 0; fi
  local log="$OUT/$name.log"
  print -r -- "# p31-running-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP  fixture=$FIX" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=uninstaller ${SIZE:+MM_WINDOW_SIZE=$SIZE }$*" >>"$log"
  [[ -n $NOTE ]] && print -r -- "# $NOTE" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=uninstaller \
      ${SIZE:+MM_WINDOW_SIZE="$SIZE"} "$@" "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  local pid=$!
  sleep "$settle"
  # 窗口发现要重试，也要把 swift 的 stderr 留在日志里。第一版在这两处各踩一次：
  # 单次查询配 `2>/dev/null`，实跑 07 时报"没有可见窗口"，而当场手动重跑同样的参数
  # 2 秒就拿到了 windowid——`swift` 脚本模式自己失败过一次，错误被 /dev/null 吃掉，
  # 于是"工具没跑成"被记成了"那一档没有窗口"。这正是要防的那类假失败。
  # 挑哪一扇由 main_window_id 负责（它同时把清单写进日志），这里只管等。
  local wid
  for i in {1..5}; do
    wid=$(main_window_id "$pid" "$log" || true)
    [[ -n $wid ]] && break
    sleep 3
  done
  if [[ -z "$wid" ]]; then
    print -u2 -- "⚠ $name：pid=$pid 反复查了 5 次，标题为 MacMaster 的主窗口不是正好一扇（不产出空照片，清单见 $log 的 # windows 行）"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid settle=${settle}s"
}

# 假 home + 面板不弹（弹了会盖掉这一轮真正要拍的列表与详情）。数组在 shot 的参数位上
# 逐元素展开——写成函数名会被当命令传给 env。
fx=(MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$FIX" MM_UNINSTALL_CONFIRM_MODE=none)

# 01–04 的共同前提：Applications/RunningFoo 真的在跑，IdleFoo 与 ElsewhereFoo 真的没跑。
RUNNING_PID=""
if wants 01-fixture-running || wants 02-fixture-confirm || wants 03-fixture-idle \
   || wants 04-fixture-min-window; then
  launch_bundle Applications/RunningFoo >/dev/null
  RUNNING_PID=$LAUNCHED_PID
fi

# 01 「正在运行」占两格：列表行的橙色 chip + 详情「运行状态」的「正在运行 · 进程 NNN」。
NOTE="launched: Applications/RunningFoo pid=$RUNNING_PID（照片里『正在运行 · 进程 <这个数>』应与之一致）"
shot 01-fixture-running "$SETTLE" $fx MM_UNINSTALL_SELECT=RunningFoo || FAILED_SHOTS+=(01-fixture-running)
# 02 确认面板：省略 MM_UNINSTALL_CONFIRM_MODE → appOnly 自动弹，面板里那句提醒要说清
#    "移到废纸篓不会让它退出"，同时不拦住卸载按钮。
NOTE="launched: Applications/RunningFoo pid=$RUNNING_PID（面板里的提醒要落得下这句，字号随面板走）"
shot 02-fixture-confirm-sheet "$SETTLE" MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$FIX" MM_UNINSTALL_SELECT=RunningFoo \
  || FAILED_SHOTS+=(02-fixture-confirm-sheet)
# 03 同一张图里的对照：选中的是 IdleFoo（未检测到），RunningFoo 那一行仍带着 chip。
NOTE="launched: Applications/RunningFoo pid=$RUNNING_PID；IdleFoo 未启动（这一档要的就是这一对照）"
shot 03-fixture-idle "$SETTLE" $fx MM_UNINSTALL_SELECT=IdleFoo || FAILED_SHOTS+=(03-fixture-idle)
# 04 最小窗口：请求 900×600（窗口有 1000 宽下限，会被夹住），看提醒块那三行折行不重叠。
NOTE="launched: Applications/RunningFoo pid=$RUNNING_PID"
shot 04-fixture-min-window "$SETTLE" MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$FIX" MM_UNINSTALL_CONFIRM_MODE=none \
     MM_UNINSTALL_SELECT=RunningFoo MM_WINDOW_SIZE=900x600 || FAILED_SHOTS+=(04-fixture-min-window)

# 05 「只有包名对上」那一档的实物：先结束 RunningFoo（免得画面里两处橙色分不清哪一处的依据是什么），
#    再启动 Elsewhere/ 里那份**同包名**的拷贝。清单上只有一行 ElsewhereFoo（扫描根是
#    $home/Applications），它自己从没跑过，而它背后那个进程报出的是另一个位置——
#    这一档以前只有单测，照片上第一次说的是"这一行是选中项、那份进程在别处"。
#    这一档也是 `runningWarning` 那句话的合同现场：它只能说"写法不同"，
#    因为判定只比路径字符串；这里两份是真的两个文件，话仍要说得下这一种情形。
if wants 05-fixture-identifier-only; then
  quit_bundle Applications/RunningFoo "$RUNNING_PID"
  launch_bundle Elsewhere/ElsewhereFoo >/dev/null
  ELSEWHERE_PID=$LAUNCHED_PID
  NOTE="launched: Elsewhere/ElsewhereFoo pid=$ELSEWHERE_PID（清单上那一行是 Applications/ 里没跑过的同包名拷贝；照片里『位置是 …/Elsewhere/ElsewhereFoo.app』应与之一致）"
  shot 05-fixture-identifier-only "$SETTLE" $fx MM_UNINSTALL_SELECT=ElsewhereFoo \
    || FAILED_SHOTS+=(05-fixture-identifier-only)
else
  ELSEWHERE_PID=""
fi

# 06 活的刷新：窗口先开好（此时 IdleFoo 没在跑），脚本再把 IdleFoo 启动起来。
#    照片里那一行如果是「正在运行 · 进程 <新 pid>」，那就只能是 NSWorkspace 的启动通知
#    把界面推的——列表是在启动之前载入的，这一跑没有任何重载、也没有点任何按钮。
#    先把前面几档留下的 RunningFoo / ElsewhereFoo 都结束掉，免得照片里两处橙色的分不清
#    哪一处是新的。启动通知只对**连上窗口服务**的应用发，所以夹具必须是 Cocoa 应用
#    （配方在 p31-running-fixture.sh 的顶上）。
if wants 06-live-launch-refresh; then
  quit_bundle Applications/RunningFoo "$RUNNING_PID"
  quit_bundle Elsewhere/ElsewhereFoo "$ELSEWHERE_PID"
  [[ -n $(bundle_pid Applications/IdleFoo) ]] && { print -u2 -- "✗ IdleFoo 已经在跑，06 的『从没用过到在用』前提不成立"; exit 3; }
  log="$OUT/06-live-launch-refresh.log"
  print -r -- "# p31-running-capture.sh 06-live-launch-refresh  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP  fixture=$FIX" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=uninstaller MM_UNINSTALL_CONFIRM_FIXTURE_HOME=$FIX MM_UNINSTALL_CONFIRM_MODE=none MM_UNINSTALL_SELECT=IdleFoo" >>"$log"
  print -r -- "# 时刻表：窗口出现（$PRELAUNCH_BUFFER 秒前 IdleFoo 未运行）→ open -g IdleFoo → 等 $POSTLAUNCH_SETTLE 秒 → 拍" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=uninstaller \
      MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$FIX" MM_UNINSTALL_CONFIRM_MODE=none \
      MM_UNINSTALL_SELECT=IdleFoo "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  pid=$!
  # 主窗口一出现就往下走（这一档要的是"窗口先开好、应用后启动"这个先后顺序），
  # 所以这里允许在 30 秒内边等边查；挑哪一扇一律交给 main_window_id。
  wid=""
  for i in {1..30}; do
    sleep 1
    wid=$(main_window_id "$pid" "$log" || true)
    [[ -n $wid ]] && break
  done
  if [[ -z "$wid" ]]; then
    print -u2 -- "06：pid=$pid 30 秒内没有唯一的主窗口（清单见 $log 的 # windows 行），杀掉自己起的进程并中止"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    exit 1
  fi
  sleep "$PRELAUNCH_BUFFER"
  IDLE_PID=$(bundle_pid Applications/IdleFoo)
  [[ -z $IDLE_PID ]] || { print -u2 -- "✗ 窗口已出现但 IdleFoo 竟然在跑（pid=$IDLE_PID），06 作废"; kill "$pid" 2>/dev/null; exit 3; }
  launch_bundle Applications/IdleFoo >/dev/null
  IDLE_PID=$LAUNCHED_PID
  print -r -- "# launched: Applications/IdleFoo pid=$IDLE_PID（照片里那一行的进程号应与之一致；它是窗口出现之后才起的）" >>"$log"
  sleep "$POSTLAUNCH_SETTLE"
  screencapture -o -x -l"$wid" "$OUT/06-live-launch-refresh.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ 06-live-launch-refresh windowid=$wid 夹具 pid=$IDLE_PID"
fi

# 07 真机档：不注入夹具，读真 /Applications 与真进程快照。画面内容随机器与时间变，
#    与 01–06 天然不可比——它的价值正是在真数据上走同一套判定。
if wants 07-real-machine; then
  # 照片里那句话背后有没有进程，靠 `Scripts/running-apps-probe.swift` 当场独立读一次快照自证。
  # 这一档以前是拿 `pgrep` + CFBundleExecutable 挑"主程序那一个号"，理由写的是
  # "界面按 bundleURL 归因，照片上只会有主进程那一个号"——实跑 07 拍到的是
  # 「正在运行 · 2 个进程（1094、1276）」，日志里却只有 1094：那句话的前提是错的，
  # 1276（wxplayer，包内的另一个可执行文件）在快照里报出的 bundleURL 就是外层这个 .app，
  # 所以它和 1094 一样算"位置对上"。哨兵比画面少报一个号，等于没核对照片上那句话。
  # 现在哨兵与界面读同一条 API、同一套比较规则（见那个脚本顶上的注释）。
  REAL_PROBE=$(swift Scripts/running-apps-probe.swift "/Applications/$REAL_SELECT.app" 2>&1 || true)
  REAL_PIDS=$(print -r -- "$REAL_PROBE" | sed -n 's/^count=[0-9]* pids=//p')
  [[ -n $REAL_PIDS ]] || REAL_PIDS="（本机此刻没有位置或包名对上 /Applications/$REAL_SELECT.app 的进程：这一档会拍到「未检测到」）"
  NOTE="real-running: $REAL_SELECT 快照口径 pid=$REAL_PIDS（口径与照片同源：Scripts/running-apps-probe.swift；照片里那一行的每个号都应在其中）"
  shot 07-real-machine "$REAL_SETTLE" MM_UNINSTALL_SELECT="$REAL_SELECT" || FAILED_SHOTS+=(07-real-machine)
  # 那几条快照的原文（各报出什么包名、什么位置、算哪一档）**在拍完之后**再读一遍追记进去：
  # 上面那次是启动前读的，而这一档要等 90 秒，中间那个应用完全可能被人退出或重启过——
  # 追记的这份与照片是同一时刻两侧的读数，对不上就说明这一档的时段不可信。
  if [[ -f "$OUT/07-real-machine.log" ]]; then
    print -r -- "$REAL_PROBE" | while IFS= read -r line; do
      [[ -n $line ]] && print -r -- "# snapshot(拍前): $line" >>"$OUT/07-real-machine.log"
    done
    swift Scripts/running-apps-probe.swift "/Applications/$REAL_SELECT.app" 2>&1 | while IFS= read -r line; do
      [[ -n $line ]] && print -r -- "# snapshot(拍后): $line" >>"$OUT/07-real-machine.log"
    done
  fi
fi

# 有档位没拍出照片就点名，并以此退出（显式 exit，EXIT 钩子才会跑）。
# 不这么做的话"跑完了"和"七档都在"是两件事——前者只在退出码上成立，
# 而退出码会被管道、被 `| tail` 这一类东西吃掉（实跑第一次就是这样：
# 07 报了一句"没有可见窗口"，脚本被 errexit 带走，屏幕上连退出码都没留下痕迹）。
if (( ${#FAILED_SHOTS[@]} > 0 )); then
  print -u2 -- "✗ 这些档位没拍出照片：${FAILED_SHOTS[*]}"
  print -r -- "→ $OUT"
  exit 1
fi

print -r -- "→ $OUT"
print -r -- "转 jpeg（与其它证据族同格式，可选）：for f in $OUT/*.png; do sips -s format jpeg -Z 1400 \"\$f\" --out \"\${f%.png}.jpg\" >/dev/null; done"
