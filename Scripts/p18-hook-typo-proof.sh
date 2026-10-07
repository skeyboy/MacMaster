#!/bin/zsh
# P18 钩子留痕核验：每一档都是"故意把值写错"，看 stderr 有没有那一行。
#
# 为什么要这样拍：钩子只有"生效/没生效"两种画面结果，而"没生效"在照片上和"生效了"
# 长得一模一样——请求 system 档拿到 cache 档，画面照样是一张干净的清理页。所以判据不在
# 画面上，在 stderr 那一行上：画面对应的档必须是日志里说的那一档回落值。
# 这一支脚本把两侧都留下来（每档一张照片 + 一份原始 stderr），照片供人眼核对"确实是回落档"，
# 文本供机器核对"确实留了痕"。
#
# 背景（逐条台账在 docs/analysis/hook-typo-audit.md）：改前这些键在值写错时一声不响——
# 5 个档位选择钩子（MM_OPEN_MODULE 除外）、MM_DISK_DEPTH、MM_DEV_SELECT/SCROLL、
# MM_FAILURE_FIXTURE、三个 `== "1"` 开关、MM_PURGE_FIXTURE_HOME 的三条越界分支、
# MM_DEV_AUTO_CONTINUE、两个预算秒数（`Double("nan")` 那一支尤其阴）、
# MM_UNINSTALL_CONFIRM_MODE（改前是 case-sensitive 的 switch，大小写写错就变 appOnly）。
#
# 全程零合成点击：合成点击/滚轮会逃逸到用户的其它应用（全站取证口径）。
# 抓窗口一律带 --pid，只 kill 自己起的那个进程。
#
#   ./Scripts/p18-hook-typo-proof.sh <app 路径> [输出目录]
#   ./Scripts/p18-hook-typo-proof.sh /tmp/mm-app-p18/MacMaster.app
#   ONLY=09 ./Scripts/p18-hook-typo-proof.sh …        只重跑某一档（前缀列表，逗号分隔：
#                                                     ONLY=13,14,18；结果写 capture-partial.log，
#                                                     既有照片与 capture.log 一字不动）
#   KEEP_FIXTURE=1 …                                   不重建 /tmp 夹具
#   SETTLE=6 DISK_SETTLE=14 …                          落位秒数
#
# 退出码：有任何一档"该留痕没留"或"不该留痕却留了"就是 1，可以当发版门禁的一部分。
set -e

cd "$(dirname "$0")/.."
# 归因头要能说出自己是哪棵树：同一道门禁重跑到另一个证据目录，两份日志只差日期的话，
# 没人能对上"这 18 张照片出自哪一次改动"。工作区不干净时后缀 -dirty——
# 只看 commit 会把"未提交的树"读成"已入库的树"（P18 那一跑正是 83aaf86-dirty）。
# 用 -uno：本脚本自己正在往证据目录里写未跟踪的日志与照片，算进脏活就永远是 -dirty 了。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
APP=${1:?需要 .app 路径}
EVIDENCE=${2:-docs/verification/p18-hooks}
RAW="$EVIDENCE/raw"
PURGE_FIXTURE=/tmp/macmaster-purge-fixture
DISK_FIXTURE=/tmp/macmaster-disk-fixture
LOG="$EVIDENCE/capture.log"
SETTLE=${SETTLE:-7}
DISK_SETTLE=${DISK_SETTLE:-12}

[[ -x "$APP/Contents/MacOS/MacMaster" ]] || {
  print -u2 -- "找不到可执行文件：$APP/Contents/MacOS/MacMaster"; exit 2; }

# 同源检查（P22 之后立的规矩，配方见 mm-provenance.sh）：这一道门禁的结论是
# "每一档留痕都在"，而留痕是**那份二进制**打印的——拍在旧产物上，某一行"没留痕"
# 可能只是那一份还没这一句，判据就成了猜。
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，一档都不跑："
  mm_provenance_line >&2
  exit 4
fi

if [[ -z ${KEEP_FIXTURE:-} ]]; then
  ./Scripts/purge-fixture.sh >/dev/null
  ./Scripts/disk-fixture.sh >/dev/null
fi
for d in "$PURGE_FIXTURE" "$DISK_FIXTURE"; do
  [[ -d $d ]] || { print -u2 -- "夹具不存在：$d（去掉 KEEP_FIXTURE 让脚本自己重建）"; exit 2; }
done
# 23 档要的卸载确认夹具：provenance-fixture.sh 的目录名是 mktemp 随机生成的，
# 没有"复用上一次那棵"这回事，所以每次现造、跑完删掉（KEEP_FIXTURE 对它不做承诺）。
UNFIX=$(./Scripts/provenance-fixture.sh)
[[ $UNFIX == /tmp/macmaster-provenance-fixture.* ]] || {
  print -u2 -- "卸载夹具路径不符合预期：$UNFIX"; exit 2; }
trap 'rm -rf "$UNFIX"' EXIT
mkdir -p "$EVIDENCE" "$RAW"
# ONLY 是"重跑某一档"，不是"重拍整轮"：整目录清空会让上一次那 15 张照片和它们的归因行一起消失，
# 剩下两份证据说不同的话。所以局部重跑写自己的 capture-partial.log，一个字都不碰既有照片。
if [[ -n ${ONLY:-} ]]; then
  LOG="$EVIDENCE/capture-partial.log"
else
  rm -f "$RAW"/*.log(N) "$EVIDENCE"/*.png(N)
fi

# 留痕行长什么样：MMHookValue 的三类文案 + 两条启动钩子自有文案 + 夹具越界文案
# + P4 之前那批 /tmp 守卫的"忽略该钩子"（措辞不同，但同样是留痕，负向档一样不许出现）。
# 负向档（expect=-）用这个集合反查：一档里出现任何一条都算"多说话"。
TRACE='含非法取值|沿用系统外观|解析失败|钩子已忽略|不在 /tmp 之下|realpath 失败|解引用后落在|不是 light/dark|忽略该钩子'

{
  print -r -- "# p18-hook-typo-proof.sh 钩子写错值留痕核验"
  print -r -- "# date: $(date '+%Y-%m-%d %H:%M:%S %z')"
  print -r -- "# command: ./Scripts/p18-hook-typo-proof.sh $APP $EVIDENCE"
  print -r -- "# repo: $repoTag branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
  local ver bld gcommit
  ver=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 未知)
  bld=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null || echo 未知)
  gcommit=$(/usr/libexec/PlistBuddy -c 'Print :MMGitCommit' "$APP/Contents/Info.plist" 2>/dev/null || echo 未知)
  print -r -- "# app: $ver ($bld)"
  # 两个 repo 行是分开的两件事：`# repo:` 是跑这条脚本的那棵树，`# app-repo:` 是被测二进制
  # 打包时的那棵树。改完取证脚本重跑旧产物时它们就不一样，只有一个行的话会指错。
  print -r -- "# app-repo: $gcommit"
  mm_provenance_line
  print -r -- "# shape under test: 档位选择与夹具路径钩子在取值写错时的行为（改前：静默回落，日志一行没有）"
  print -r -- "# expected: 正向档的 stderr 里必须有该行给出的 expect 子串；负向档（expect=-）里"
  print -r -- "            一条留痕都不许出现。照片用来人眼核对'确实落在文案说的那一档'。"
  print -r -- "# observed: 见下面每档的 result 行；原始 stderr 逐档存在 raw/<档名>.log"
  print -r -- "# restore: 本脚本不写用户任何状态；夹具目录在 /tmp，需要时用 purge-fixture.sh --clean / disk-fixture.sh --clean 删"
} >"$LOG"

failed=0
checked=0

# proof [-n] <档名> <期望子串，或 - 表示不许有留痕> <等待秒> <环境变量...>
# -n 表示这一档不出照片：钩子被拒之后回落的是真实主目录，画面上是全机器的项目名，
# 那种图既不该进仓库，也证明不了任何事（要核的是日志那一行，不是画面）。
proof() {
  local no_photo=0
  if [[ $1 == -n ]]; then no_photo=1; shift; fi
  local name=$1 expect=$2 settle=$3; shift 3
  # ONLY 是前缀列表（逗号分隔）：ONLY=09 只跑 09 那一档，ONLY=13,14,18 跑三档。
  # 这里用显式循环而不是 `== ${ONLY}*`：zsh 不会把变量里的 [348] 再当字符类展开，
  # 写成括号类会一声不响地一档都不匹配，然后脚本报"全部 0 档符合预期"——绿色的空跑。
  if [[ -n ${ONLY:-} ]]; then
    local matched=0 only_item
    for only_item in ${(s:,:)ONLY}; do
      [[ $name == "${only_item}"* ]] && matched=1 && break
    done
    (( matched )) || return 0
  fi
  local raw="$RAW/$name.log"
  : >"$raw"
  env MM_APPEARANCE=dark "$@" "$APP/Contents/MacOS/MacMaster" >>"$raw" 2>&1 &
  local pid=$!
  sleep "$settle"
  local wid photo="无（这一档不出照片）"
  wid=$(swift Scripts/window-ids.swift --pid "$pid" 2>/dev/null \
        | sed -n 's/^windowid=\([0-9]*\).*/\1/p' | head -1)
  if [[ -n "$wid" && $no_photo == 0 ]]; then
    # 抓不到就记一笔，别让 set -e 把整轮砍在半路（那一轮的照片与日志会只剩一半）。
    if screencapture -o -x -l"$wid" "$EVIDENCE/$name.png" 2>/dev/null; then
      photo="$EVIDENCE/$name.png"
    else
      photo="抓帧失败（windowid=$wid）"
    fi
  elif [[ -n "$wid" ]]; then
    photo="按 -n 跳过（钩子被拒后画面是真实主目录）"
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  checked=$((checked + 1))

  local verdict hit
  if [[ $expect == "-" ]]; then
    hit=$(grep -E "$TRACE" "$raw" | head -3)
    if [[ -z $hit ]]; then verdict="✅ 无留痕（如预期）"; else
      verdict="❌ 不该留痕却留了：$hit"; failed=$((failed + 1)); fi
  else
    hit=$(grep -F -- "$expect" "$raw" | head -1)
    if [[ -n $hit ]]; then verdict="✅ 留痕命中：$hit"; else
      verdict="❌ 没找到期望的留痕行（期望子串：$expect）"; failed=$((failed + 1)); fi
  fi
  {
    print -r -- "# ---- $name ----"
    print -r -- "# env: $*"
    print -r -- "# expect: $expect"
    print -r -- "# windowid: ${wid:-无}  pid: $pid  settle: ${settle}s  照片: $photo"
    print -r -- "# result: $verdict"
  } >>"$LOG"
  print -r -- "$name  $verdict"
}

# 1) 模块档：写错一个字母会停在概览——这一档的照片要人眼确认"真的是概览页"。
proof 01-module-typo 'MM_OPEN_MODULE 含非法取值（cleanner）' "$SETTLE" MM_OPEN_MODULE=cleanner
proof 02-module-ok - "$SETTLE" MM_OPEN_MODULE=cleaner MM_OPEN_TAB=cache

# 2) 清理页 tab：systeme 不是任何档，回落 cache。
proof 03-tab-typo 'MM_OPEN_TAB 含非法取值（systeme）' "$SETTLE" \
      MM_OPEN_MODULE=cleaner MM_OPEN_TAB=systeme

# 3) 跨模块同键不同词表：MM_OPEN_TAB 在磁盘页只认 tree|list|large，
#    把清理页的写法或视图标题（treemap）传进来必须被拒。
proof 04-disk-tab-alias 'MM_OPEN_TAB 含非法取值（treemap）' "$SETTLE" \
      MM_OPEN_MODULE=disk MM_OPEN_TAB=treemap
proof 05-disk-tab-ok - "$SETTLE" MM_OPEN_MODULE=disk MM_OPEN_TAB=list

# 4) 设置页：sheet 得先被唤出来才会构造，所以带 MM_SHOW_SETTINGS。
proof 06-settings-tab-typo 'MM_SETTINGS_TAB 含非法取值（abotu）' "$SETTLE" \
      MM_SHOW_SETTINGS=1 MM_SETTINGS_TAB=abotu

# 5) 卸载页 pane。
proof 07-pane-typo 'MM_UNINSTALL_PANE 含非法取值（oran）' "$SETTLE" \
      MM_OPEN_MODULE=uninstaller MM_UNINSTALL_PANE=oran

# 6) 数字档：深度只认 1~4。
proof 08-depth-typo 'MM_DISK_DEPTH 含非法取值（9）' "$DISK_SETTLE" \
      MM_OPEN_MODULE=disk MM_DISK_SCAN="$DISK_FIXTURE" MM_DISK_DEPTH=9

# 7) 优化页 tab（键与清理/磁盘同名，词表不同）。
proof 09-optimizer-tab-typo 'MM_OPEN_TAB 含非法取值（duplicate）' "$SETTLE" \
      MM_OPEN_MODULE=optimizer MM_OPEN_TAB=duplicate

# 8) 夹具路径：这是最危险的一档。目录不存在 → realpath 失败 → 扫描根将是真实 home，
#    那一屏每行都带勾选框，所以"说了"和"说得够明白"都要核。
proof -n 10-purge-fixture-missing 'MM_PURGE_FIXTURE_HOME=/tmp/macmaster-does-not-exist realpath 失败' "$SETTLE" \
      MM_OPEN_MODULE=cleaner MM_OPEN_TAB=dev MM_PURGE_FIXTURE_HOME=/tmp/macmaster-does-not-exist
proof -n 11-purge-fixture-outside-tmp 'MM_PURGE_FIXTURE_HOME=/Users 不在 /tmp 之下' "$SETTLE" \
      MM_OPEN_MODULE=cleaner MM_OPEN_TAB=dev MM_PURGE_FIXTURE_HOME=/Users
proof 12-purge-fixture-ok - "$SETTLE" \
      MM_OPEN_MODULE=cleaner MM_OPEN_TAB=dev MM_PURGE_FIXTURE_HOME="$PURGE_FIXTURE"

# 8b) 另外两处 /tmp 守卫（P4 之前就有，本轮没动它们的解析）也纳入门禁：
#     它们的"失败"是**回落到真实目录**，跟 10/11 同一个性质，所以同样 `-n`。
#     磁盘这一条尤其不能拍：MM_DISK_SCAN 指错到真实家目录时，画面上就是用户整个 home 的树。
proof -n 13-disk-scan-outside-tmp 'MM_DISK_SCAN=/Users 不在 /tmp 之下，忽略该钩子' "$SETTLE" \
      MM_OPEN_MODULE=disk MM_DISK_SCAN=/Users
proof 14-disk-hold-typo 'MM_DISK_HOLD 含非法取值（holddd），只接受 hold，钩子已忽略' "$SETTLE" \
      MM_OPEN_MODULE=disk MM_DISK_HOLD=holddd

# 9) 等值 token 与快照档：这四条与上面共用同一套 flag/文案函数，实机各跑一档确认
#    文案真的落进 stderr（尤其是快照那档：可接受集合由夹具表现算，加了档不会说旧话）。
proof 15-dev-select-typo 'MM_DEV_SELECT 含非法取值（untouchd），只接受 untouched' "$SETTLE" \
      MM_OPEN_MODULE=cleaner MM_OPEN_TAB=dev MM_PURGE_FIXTURE_HOME="$PURGE_FIXTURE" MM_DEV_SELECT=untouchd
proof 16-dev-scroll-typo 'MM_DEV_SCROLL 含非法取值（nedd），只接受 end' "$SETTLE" \
      MM_OPEN_MODULE=cleaner MM_OPEN_TAB=dev MM_PURGE_FIXTURE_HOME="$PURGE_FIXTURE" MM_DEV_SCROLL=nedd
proof 17-failure-fixture-typo 'MM_FAILURE_FIXTURE 含非法取值（protectd），只接受 protected' "$SETTLE" \
      MM_OPEN_MODULE=cleaner MM_FAILURE_FIXTURE=protectd
#    快照这一档把整串可接受集合写死在期望里，是故意的：那串由夹具表 `keys.sorted()` 现算，
#    以后加一个快照档，这一档就会红——要么把新档写进期望，要么承认文档与实现分家了。
proof 18-snapshot-fixture-typo 'MM_SNAPSHOT_FIXTURE 含非法取值（mixd），只接受 broken|mixed|none|overflow|updateonly' "$SETTLE" \
      MM_OPEN_MODULE=cleaner MM_SNAPSHOT_FIXTURE=mixd

# 10) 启动钩子的两条文案（改前就有留痕，这里只是把它们也纳入门禁）。
proof 19-appearance-typo 'MM_APPEARANCE=pink 不是 light/dark，沿用系统外观' "$SETTLE" MM_APPEARANCE=pink
proof 20-window-size-typo 'MM_WINDOW_SIZE=900 解析失败' "$SETTLE" MM_WINDOW_SIZE=900

# 11) P18 收尾的三档：这三个键改前一声不响，形状各异，所以各留一条实机凭据。
#     21 数字档带"0 = 关"的语义（回落 0 就是"没开自动续扫"）；
#     22 秒数是 Double 而不是 Int，而且 `Double("nan")` 能解析、`nan > 0` 是假的——
#        这一档就是为 nan 留的（写 15s 只是让人看得懂）；
#     23 只有确认夹具成立时才会被读到（面板不会凭空弹），所以这档依赖 provenance 夹具。
#     21/22 都 `-n`：钩子被拒之后画面就是"按默认预算扫真 home"，那种图不该进仓库。
proof -n 21-auto-continue-typo 'MM_DEV_AUTO_CONTINUE 含非法取值（3s），只接受 1~3，已回落 0' "$SETTLE" \
      MM_OPEN_MODULE=cleaner MM_OPEN_TAB=dev MM_PURGE_FIXTURE_HOME="$PURGE_FIXTURE" MM_DEV_AUTO_CONTINUE=3s
proof -n 22-budget-typo 'MM_DEV_ROOT_BUDGET_SECONDS 含非法取值（15s），只接受大于 0 的秒数，钩子已忽略，这一轮按默认预算' "$SETTLE" \
      MM_OPEN_MODULE=cleaner MM_OPEN_TAB=dev MM_PURGE_FIXTURE_HOME="$PURGE_FIXTURE" MM_DEV_ROOT_BUDGET_SECONDS=15s
proof 23-confirm-mode-typo 'MM_UNINSTALL_CONFIRM_MODE 含非法取值（withresidual），只接受 apponly|withresiduals|none，已回落 apponly 档' "$SETTLE" \
      MM_OPEN_MODULE=uninstaller MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$UNFIX" MM_UNINSTALL_CONFIRM_MODE=withresidual

{
  print -r -- "# ---- 结论 ----"
  print -r -- "# 核对 $checked 档，失败 $failed 档"
  print -r -- "# 照片 $(ls "$EVIDENCE"/*.png(N) | wc -l | tr -d ' ') 张，原始 stderr 在 $RAW/"
} >>"$LOG"

# 拼错 ONLY 以前是"绿色地跑了个空集合"：退出 0、一行核对结果都没有，看着像全过。
# 门禁工具最坏的失效不是报错，是**报错的形态和通过一样**。
if (( checked == 0 )); then
  print -u2 -- "❌ 一档都没跑（ONLY=${ONLY:-}写错了？这一轮没有任何核对结果）"
  print -r -- "# result: 空跑——ONLY 没匹配到任何档" >>"$LOG"
  exit 2
fi

if (( failed > 0 )); then
  print -u2 -- "❌ $failed/$checked 档留痕不符合预期，详见 $LOG"
  exit 1
fi
print -r -- "全部 $checked 档符合预期。日志：$LOG"
