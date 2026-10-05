#!/bin/zsh
# P11 hardened runtime 实测轮：同一份二进制，两种签名，逐个能力拍对照照片。
#
# 为什么要这一支脚本，而不是直接读 `docs/analysis/release-readiness.md` §3 那张表：
# §3 那张表是**预测**——每条都指着代码说"沙盒下会被拒 / hardened runtime 需实测"，
# 而"需实测"这四个字挂了几天，一条都没测过。预测不能当发版依据：
# 表里若有一行其实不会断，我们就白砍了一项能力；若有一行其实会断而我们没发现，
# 发出去的 dmg 上那一格就是空的。这一轮把它变成照片。
#
#   ./Scripts/p11-hardened-check.sh /tmp/mm-app-p11-base/MacMaster.app docs/verification/p11-hardened base
#   ./Scripts/p11-hardened-check.sh /tmp/mm-app-p11-hr/MacMaster.app   docs/verification/p11-hardened hr
#
#   ONLY=watch ./Scripts/p11-hardened-check.sh …    只重拍 kqueue 那两档（最慢，各约一分钟）
#
# 两个硬规定：
# 1) **本轮一个顶数据的夹具钩子都不带**。`MM_*_FIXTURE` 那些钩子改的正是"喂给界面的数据"，
#    而这一轮要测的是"取数的那条系统调用还通不通"——带上夹具等于把待测对象换掉，
#    照片会拍出一张漂亮的假绿。唯一例外是监听那两档：它们的钩子只把 kqueue 的
#    **监听目录**指到 /tmp（见 `TrashWatcher.watchTarget()`），事件仍走真实 DispatchSource。
# 2) 只 kill 自己起的 pid，抓窗口一律带 `--pid`；不点任何按钮（零合成点击）——
#    所以每一档都挑的是"进页即自动跑"的读数，需要点击才能触发的那条（登录项开关会真改
#    用户 launchd 状态）本轮**不测**，并且把这个空白写回 §3。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
TAG=${3:?需要档位名（base / hr）}
APPEARANCE=${APPEARANCE:-light}
SETTLE=${SETTLE:-9}
WIN=${WIN:-1100x1000}

mkdir -p "$OUT"

sig=$(codesign -dv --verbose=4 "$APP" 2>&1 \
      | grep -oE 'Identifier=[^ ]*|flags=0x[0-9a-f]+\([a-z,]+\)|Signature=[^ ]*|TeamIdentifier=.*' | tr '\n' ' ')
ver=$(plutil -p "$APP/Contents/Info.plist" 2>/dev/null \
      | sed -nE 's/.*"CFBundleShortVersionString" => "(.*)".*/\1/p')
assess=$(spctl -a -t exec -vv "$APP" 2>&1 | tr '\n' ' ' || true)

# shot <档名> <等待秒> <附加 env>…
shot() {
  local name=$1; shift
  local settle=$1; shift
  local log="$OUT/$name-$TAG.log"
  {
    print -r -- "# p11-hardened-check.sh $name-$TAG  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP"
    print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_WINDOW_SIZE=$WIN ${(j: :)@}"
    print -r -- "# fixtures: 无（本轮全部走真实读取路径，除非上面 env 里明写了 WATCH 目录钩子）"
    print -r -- "# codesign: $sig"
    print -r -- "# plist: CFBundleShortVersionString=$ver"
    print -r -- "# spctl: $assess"
  } >"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_WINDOW_SIZE="$WIN" "$@" "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
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
  screencapture -o -x -l"$wid" "$OUT/$name-$TAG.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name-$TAG windowid=$wid"
}

# ONLY 逐档点名：`ONLY=03,05` 只重拍这两档，`ONLY=watch` 只重拍监听两档，空=全跑。
# 留这个口子的理由是实打实的：监听两档各要一分多钟（等"大小已实测"跑完），
# 而改一行文案常常只需要重拍一格。
# want <档号> [组名]：档号命中或组名命中都算。第一版这里埋着一个更笨的 bug——
# 整块只用 `want shots` 把门，于是 `ONLY=03,05` 会把五档全跳过，
# 注释里承诺的逐档重拍其实从来没生效过。所以五档各自把关，不再共用一道门。
want() {
  if [[ -z ${ONLY:-} ]]; then return 0; fi
  if [[ ",$ONLY," == *",$1,"* ]]; then return 0; fi
  if [[ -n $2 && ",$ONLY," == *",$2,"* ]]; then return 0; fi
  return 1
}

# 01 TCC.db 只读 sqlite：不看有没有授权，只看**两档之间授权状态有没有变**。
if want 01 shots; then
shot 01-tcc "$SETTLE" MM_OPEN_MODULE=guardian MM_GUARDIAN_CARDS=tcc
fi
# 02 登录项核对：卡里的脚注来自真实 `launchctl list` 快照（只读那一侧）。
if want 02 shots; then
shot 02-login "$SETTLE" MM_OPEN_MODULE=guardian MM_GUARDIAN_CARDS=login
fi
# 03 「密钥与自启配置的改动时间」卡。**P11c 起这一档不再是 hardened runtime 的判据**：
#    从前它测的是 `/usr/bin/log show` 子进程在两种签名下通不通（判据"有没有出现「系统日志事件」行"），
#    P11c 量完谓词口径后把日志族整族撤下、`scanUnifiedLog` 已删，这一卡现在只读目录 mtime 与
#    `~/Library/LaunchAgents` 的 .plist 清单——没有子进程，hardened runtime 拦不到它。
#    这一档留着只为旁证：这一屏在 runtime 下照样渲染，且 mtime 那一路读得到东西。
#    ⚠️ P11c 之前那两张 `03-activity-*.png` 拍的是已撤下的日志族，它们证明的是当时的判据，
#    不证明今天这一格；改名后的重拍记在 `p11c-activity-capture.sh` 那一档。
#    当初这一格第一轮拍出来是空的，查下去是我们自己的读法问题，不是签名问题
#    （见 `Scripts/p11-pipe-deadlock-repro.swift`）。
if want 03 shots; then
shot 03-activity "$SETTLE" MM_OPEN_MODULE=guardian MM_GUARDIAN_CARDS=activity
fi
# 04 SMC 温度/风扇 + IOKit 磁盘统计：两张卡同屏，一次拍掉 §3 表里第 4、5 两行。
if want 04 shots; then
shot 04-monitor "$SETTLE" MM_OPEN_MODULE=monitor MM_MONITOR_CARDS=sensors,disk
fi
# 05 `/usr/bin/tmutil` 本地快照：那块「磁盘空间只读报告」在缓存表格**下面**，
#    16 类全列时它落在折叠线外（第一版就这么拍了一张"看不见"的照片）。
#    `MM_CLEANER_FILTER=邮件` 只给搜索框一个初值（列表缩到一行），报告块因此进画面；
#    它不改数据源——tmutil 那一路照旧真跑。等待给足是因为扫描本身进页自动跑。
if want 05 shots; then
shot 05-space 26 MM_OPEN_MODULE=cleaner MM_OPEN_TAB=cache MM_CLEANER_FILTER=邮件
fi

# 06/07 kqueue 两档：**不自己造时序**，直接调已验证的两支取证脚本。
# 第一版在这里栽过一次：脚本自己往 /tmp 夹具目录 mv 一个 .txt、等 9 秒拍照，
# 两档照片逐字节相同——看上去像"签名不影响这一行"，其实是什么都没拍到：
# ① 拖进废纸篓那颗必须是 .app（卡片走残留识别，普通文件不成卡）；
# ② 改动要发生在监听建好基线**之后**（`p68-trash-capture.sh` 先轮询到窗口再留缓冲）；
# ③ mv 之后等的是"大小实测跑完"，本机约 45 秒，不是几秒（那个脚本把 AFTER_MOVE 定在 60）。
# 这三条都是前几轮踩过并修好的，重复发明一遍只会得到一张假证。
if want watch; then
    ./Scripts/trash-fixture.sh
    ONLY=01 ./Scripts/p68-trash-capture.sh "$APP" "$OUT/watch-trash-$TAG" "$APPEARANCE"
    APP="$APP" OUT="$OUT/watch-apps-$TAG" ./Scripts/apps-watch-run.sh notice "$APPEARANCE"
fi

print -r -- "→ $OUT（档位 $TAG）。判据不是「这一档好不好看」，而是同一能力在两档之间有没有差："
print -r -- "  01 TCC 的徽章与脚注；02 有没有那句「没能和 launchd 对表」；03 活动卡是「有事件」还是"
print -r -- "  「近 5 分钟没有可读到的活动事件」；04 温度/风扇/磁盘 IO 是真数还是「—」+原因；"
print -r -- "  05 本地快照落在「有 / 没有 / 不可用（原因）」哪一档；"
print -r -- "  watch-trash-$TAG / watch-apps-$TAG 里有没有「刚拖进废纸篓」「刚从应用目录消失」两张回声卡。"
