#!/bin/zsh
# P15 管道取证：两处真跑子进程的阅读路径换用 `MMCore.CommandRunner` 之后，
# 界面上照常出**真实读数**，而且那个读数能从另一条独立读法算出来。
#
# 为什么这一轮非要照片：这一族缺陷的表现不是崩溃，是"读数变成一句没核对成"或者
# "整卡停在骨架"。P11 那一次界面看起来完全正常——「系统活动」卡写着"这台机器近 5 分钟
# 没有活动事件"，底下是一行都没读出来（管道死锁被超时保护伪装成了空结果）。
# 所以"单测全绿 + 界面有东西"在这一处都不算证据。判据沿用 `p11c-activity-capture.sh`
# 的那一条：**真值也要出现在照片里，并且要能从另一条路推出来**（`# expect:` 行）。
#
# 两条独立读法各测一处改动：
#   01 登录项卡 —— 判据是**照片里看得见**的两个数：卡头「N 项」的 N，和逐条橙色徽章
#      「没在当前会话里加载」落在哪几个标签上。这两个数都只有把 `launchctl list`
#      整批读回来才成立（徽章来自核对结论，读失败时整卡换成"这一轮没核对成"）。
#      本条命令同日多次现读 18,541–19,540 字节（本脚本取证那一刻是 18,959，写进 .log 的就是它），
#      是 `Pipe` 那 64 KB
#      内核缓冲的三成，也是全站输出量最大的一条子进程命令。旧写法在这一处**恰好**
#      没发作，而"没发作"拦不住哪天作业变多——所以脚本用 shell 另跑一次同一条命令，
#      按同一套口径（排任务族前缀、排 com.apple.、五个已知目录找 `<label>.plist`）
#      把这两个数各数一遍。卡最底部那行「launchd 里还挂着 N 个非苹果标签」也一并算
#      进 expect，但它 17 项的列表下就在折叠线外，照片里没有它——第一版拿它当判据，
#      拍回来的是一张没有判据的照片。
#   02 磁盘空间只读报告 —— 「本地快照 N 个」的 N，同样用 shell 另跑一次 `tmutil` 数。
#      这一处改的是同一个执行器，但 tmutil 在本机只输出 21–22 字节，照片证明的是"没改坏"，
#      大输出那一维由 `CommandRunnerPipeTests` 用一条必定 512 KB 的命令钉住。
#
#   ./Scripts/p15-pipe-capture.sh /tmp/mm-app-p15/MacMaster.app docs/verification/p15-pipe
#   ONLY=01 ./Scripts/p15-pipe-capture.sh …    只重拍登录项那一档
#
# 三条硬规定沿用全站取证口径：① 一个顶数据的夹具钩子都不带（这一轮要看的正是真读数，
# 注入夹具就把「读回来了」这个判据本身抽掉了）；② 零合成点击；
# ③ 只 kill 自己起的 pid，抓窗口一律带 `--pid`。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
mkdir -p "$OUT"

# 标签条数这种东西不能靠记忆（同一支脚本自己产出过 549，手写注释里抄着 551/555/557——
# 它随作业启停浮动，抄进注释的那一刻就开始漂）。每次拍照前用 shell 现算一遍，算完写进 .log；
# 注释里不保留任何"当前值"。口径必须与代码一致，否则对不上数时报的是"脚本错了"
# 而不是"读错了"：
# 解析层按 \t 切、取第 3 列、要求至少 3 列（`LaunchctlListParser.parse`），
# 判定层排掉 application./pid./gui//system/ 与 com.apple. 前缀，
# 再到五个已知目录找 <label>.plist（`LoginItemAuditor.knownPlistPaths`）。
expect_login() {
  local raw=$1
  local bytes=${#raw}
  print -r -- "# expect: launchctl-list-bytes=$bytes"
  local labels
  labels=$(print -r -- "$raw" | /usr/bin/awk -F'\t' 'NR>1 && NF>=3 {
             gsub(/^ +| +$/, "", $3); if ($3 != "") print $3 }' | /usr/bin/sort -u)
  local -a labelArr
  labelArr=(${(f)labels})
  local -a orphans
  orphans=()
  for L in $labelArr; do
    case "$L" in
      application.*|pid.*|gui/*|system/*|com.apple.*) continue ;;
    esac
    local found=0
    for D in "$HOME/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons" \
             "/System/Library/LaunchAgents" "/System/Library/LaunchDaemons"; do
      if [[ -e "$D/$L.plist" ]]; then found=1; break; fi
    done
    # 用 if 而不是 `(( found == 0 )) && …`：后者在 found=1 时整条返回非零，
    # 而脚本开着 set -e——这一族"最后一句恰好没执行"的写法能把整支脚本带走。
    if (( found == 0 )); then orphans+="$L"; fi
  done
  # 界面上那句只在 orphans>0 时出现；=0 时判据改成"不许出现『这一轮没核对成』"。
  print -r -- "# expect: launchctl-labels=${#labelArr}"
  print -r -- "# expect: orphan-labels=${#orphans}"
  # 分隔符用空格而不是顿号：`${(j:、)arr}` 这种多字节分隔符在 zsh 里是
  # "error in flags"，脚本会在拍照**之后**、写日志的这一步炸掉，
  # 于是留下一个没人收的实例和一份没有照片的 .log（第一版就是这么栽的）。
  print -r -- "# expect: orphan-labels-list=${(j: :)orphans}"

  # 下面两条才是**照片里看得见**的数：孤儿那一行在卡的最底部，17 项的列表把它顶到了
  # 折叠线外（第一版拿它当判据，拍回来一张没有判据的照片）。
  # 卡头「N 项」= 三个目录里 .plist + .disabled 的个数（`LoginItemScanner.scan`），
  # 逐条徽章「没在当前会话里加载」= 可判定项里 enabled 且标签不在快照里的那些
  # （`LoginItemAuditor.isJudgable` + `.plistNotLoaded`）——改名停用的不判、
  # /Library/LaunchDaemons 的不判，这两条排除也要照抄，否则对不上的是脚本。
  local -a itemFiles
  itemFiles=()
  for D in "$HOME/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons"; do
    for f in "$D"/*(.N); do
      case "${f:t}" in
        *.plist|*.disabled) itemFiles+="$f" ;;
      esac
    done
  done
  print -r -- "# expect: login-item-files=${#itemFiles}（判据：卡头「N 项」的 N；"
  print -r -- "#          对不上时必须能在界面上看到某条读取/解析失败，否则就是数错了）"

  local -a notLoaded
  notLoaded=()
  for f in $itemFiles; do
    case "${f:t}" in *.disabled) continue ;; esac          # 改名停用一律不判
    [[ $f == /Library/LaunchDaemons/* ]] && continue        # 系统域守护进程不判
    local label=${${f:t}:r}
    local extracted
    extracted=$(/usr/bin/plutil -extract Label raw "$f" 2>/dev/null) || extracted=""
    [[ -n $extracted ]] && label=$extracted
    local disabled
    disabled=$(/usr/bin/plutil -extract Disabled raw "$f" 2>/dev/null) || disabled="false"
    if [[ $disabled != "true" ]] && ! (print -r -- "$labels" | /usr/bin/grep -qxF "$label"); then
      notLoaded+="$label"
    fi
  done
  print -r -- "# expect: not-loaded-labels=${#notLoaded} ${(j: :)notLoaded}"
  print -r -- "#          （判据：照片上每一条橙色「没在当前会话里加载」都要在这里出现，"
  print -r -- "#           反向也要成立——这里列出的标签在照片里必须带橙色徽章）"
}

expect_space() {
  local out
  out=$(/usr/bin/tmutil listlocalsnapshots / 2>&1) || true
  print -r -- "# expect: tmutil-bytes=${#out}"
  local n
  n=$(print -r -- "$out" | /usr/bin/awk '/^com\.apple\./ {c++} END {print c+0}')
  print -r -- "# expect: snapshot-lines=$n（界面「本地快照 N 个」的 N；n=0 时界面写"
  print -r -- "#          『这台 Mac 目前没有本地快照』，两种都不许写成『不可用』）"
}

# shot <档名> <等待秒> <环境变量...>
shot() {
  local name=$1; shift
  local settle=$1; shift
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  {
    print -r -- "# p15-pipe-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP"
    print -r -- "# env: MM_APPEARANCE=light ${(j: :)@}"
    print -r -- "# fixtures: 无（这一轮要看的就是真读数；注入夹具会把「读回来了」这个判据本身抽掉）"
    print -r -- "# codesign: $(codesign -dvv "$APP" 2>&1 | grep -oE 'flags=0x[0-9a-f]+[a-z()]*' | head -1)"
  } >"$log"
  env MM_APPEARANCE=light "$@" \
      "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  local pid=$!
  print -r -- "# pid: $pid（由本脚本启动，也由本脚本 kill；不是用户的实例）" >>"$log"
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
  # 先拍照，再补 expect 行：照片是主证据，expect 只是注解。
  # 顺序反过来 + 开着 set -e，注解里任何一个语法错都会把已经起好的实例丢在那儿没人收
  # ——第一版就炸在这里（`${(j:、)arr}` 是个 zsh 语法错），实例留在屏幕上，
  # 靠 .log 里那一行 `# pid:` 才找得回来。
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  { case "$name" in
      01-login) expect_login "$(/bin/launchctl list 2>&1)" ;;
      02-space) expect_space ;;
    esac
  } >>"$log" || print -u2 -- "⚠ $name：expect 行没写成（照片已存，判据要人工对另一条读法）"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid settle=${settle}s"
}

# 01 登录项卡（只渲染这一张：`MM_GUARDIAN_CARDS=login`，绕开"第 4 张卡在折叠线下"那处取景死角）。
#    判据两条，都要在照片里数得出来：卡头「N 项」= expect 的 `login-item-files`；
#    橙色「没在当前会话里加载」出现在哪几个标签上 = expect 的 `not-loaded-labels`，
#    反向也要成立。读失败时这两条都会换成一句「这一轮没核对成」——那正是本轮要拦的话。
shot 01-login 14 MM_OPEN_MODULE=guardian MM_GUARDIAN_CARDS=login

# 02 「磁盘空间只读报告」在缓存表格下面，16 类全列时落在折叠线外，
#    所以沿用 `p11-hardened-check.sh` 里 05-space 那一档的取景法（MM_CLEANER_FILTER=邮件
#    只给搜索框一个初值，把列表缩到一行，数据源不动）。等待给足 26 秒：进页自动跑的
#    缓存扫描要先落位，报告块才在画面上。
shot 02-space 26 MM_OPEN_MODULE=cleaner MM_OPEN_TAB=cache MM_CLEANER_FILTER=邮件

print -r -- "→ $OUT"
