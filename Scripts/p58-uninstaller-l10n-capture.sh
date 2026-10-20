#!/bin/zsh
#
# p58-uninstaller-l10n-capture.sh — 卸载页接进两语以后的双语实机照片（P58c）
#
# 这一族拍的是"P58 接进 `L`/`LF` 的那 208 个新键在真窗口里跟着语言档变了没有"。
# 卸载页是九页里文案最厚的一页（证据、提醒、确认、后遗症、废纸篓、监听、启动器七族句子都在这里），
# 所以按族分档，每族一对中英：
#   01/02 残留清单 + 详情：证据措辞（`ui.evidence.*`）× 归属复核提醒（`ui.ownership.*`）
#         × 风险标签 × 类别分组 × 页脚「已选 N 项残留 · 体积」× 基本信息那八行键名
#   03/04 确认面板：`ui.uninstall.confirm_*`（标题与正文都带 %@，英文还换了语序）
#   05/06 卸载后遗症：`ui.orphan.*`（面板标题/正文/两个按钮）
#         —— 这一族**不走 P33b 那棵嵌套夹具**：孤儿判定的主人集合就是当前应用清单，
#         而那棵树的 `Applications` 里把残留的主人（Fork / IDEFoo / AssetsFork）全装着，
#         扫出来必然是 0 条（第一遍实跑就是这么报的）。唯一零点击的来路是装卸夹具那一棵：
#         `Highball` 被 depart 拿走 → `MM_APPS_WATCH_AUTO_SCAN=1` 替我们按「重新载入并扫描」
#         → 清单刷新后它散在假 `~/Library` 的残留第一次成为孤儿（`apps-watch-run.sh scan` 同一条路）。
#         面板居中、只有两行时列表在它上方全露得出来，所以逐行「路径 + 主人」那条副标题
#         （`ui.orphan.row_subtitle`）**也在画面上**——照片 06 读得到，初稿曾把它登记成没拍，已更正。
#   07/08 Steam 启动器行：`ui.launcher.*`（`basis` 那条是 `%1$@…%4$@` 四个位置参数，最险的一条）
#   09/10 废纸篓确认：`ui.trash.confirm_*`
#   11/12 装卸监听消失卡：`ui.watch.*`
#   13    英文窄窗：`MMKeyRow` 的键名列固定 80 pt，英文标签比中文长，这一张看它截不截
#   14    不带 `MM_LANGUAGE` 补拍：这张证的是"档已复位"，没有它下一族拍到的英文会被读成"这台机器一直是英文"
#
# 判据为什么必须挂在画面上而不是单测上：`MM_LANGUAGE` 会写回 UserDefaults，
# 所以"这一张忘了带变量"和"这一张是中文档"在画面上长得一模一样。
# 于是每一张的日志都要自己吐出「MM_LANGUAGE=<档> 已生效」那一行（`Localization.appliedNote`），
# 同屏双语的两张还要在像素上真的不一样——两样缺一，这张照片就不作数。
#
# 假 home 一律只认 /tmp（`UninstallFixtureHooks.canonicalHome`、`TrashWatcher.fixtureEnvironmentValue`）：
# 这一页的终点是删除按钮，钩子指向真实主目录就等于拿用户文件做截图。
# 四棵夹具都带假 `Applications`，所以列表里没有一台真机应用名，测大小也就是毫秒级。
#
# 纪律：全程零合成点击（原生控件点不进去，而且会逃逸到用户的其它应用）；
# 拖进废纸篓与装卸改动由脚本改目录触发（探针已证明这类改动会送 kqueue 事件）；
# 只 kill 自己启动的 pid；夹具与脚本入库，中间产物留 /tmp。
#
# 两条第一遍跑完才学到的规矩（都写成了判据，不是写成了注释）：
#
# ① **快门只认"这一张的状态已经在日志里落定"那一行**（`WAIT_PATTERN`）。
#   旧写法是"等固定秒数 → 拍 → 跑完再去 grep 日志"，而日志里那行凭据只证明它**发生过**，
#   不证明它发生在快门**之前**。07/08 那两张就是这么假绿的：Steam 那棵六个应用、
#   其中一个 8.4 MB，测大小比 12 秒的固定等待慢，快门先落、点名行后吐，
#   照片拍到的是点名之前的「未选择应用」空态，而事后 grep 到的日志一片绿。
#   第二遍又添一条：**这个闸不能读到自己**。声明行「# 就位凭据：等到日志出现 /$WAIT_PATTERN/」
#   逐字把 wait_pattern 印进了同一份日志，于是第一版每次都在 0 秒通过——05/06 因此
#   又假绿了一回（那两张的应用侧「已用夹具目录 …（N 条）」根本没出现过）。
#   从此所有凭据判据一律先 `grep -v '^#'` 跳过本脚本写的行，只看应用自己吐的那些。
#
# ② **这一族会把删除按钮摆在最前台**，而键盘事件按前台走，不按终端走。
#   确认面板的「移到废纸篓」带 `.keyboardShortcut(.defaultAction)`（`MMUninstaller.swift:699`），
#   实例又是自己起在前台的：这十几秒里任何人敲一次回车，面板就替我们按了。
#   05 那一张的第一遍就是这么没的——照片上只剩事后的空态和一条回执。
#   所以 05/06 的快门在凭据行出现的那一刻就落（把窗口从十几秒压到一秒级），
#   而且这两档拍完必须人眼读一遍：脚本能证"面板打开过"，证不了"照片里还开着"。
#   顺带：08 那一张上盖着一扇中文的「设置」窗口——同一条逃逸路（Cmd+,）。
#
#   ./Scripts/make-app.sh -o /tmp/mm-app-p58 -s /tmp/mm-scratch-p58        # 产物必须与源码同源
#   ./Scripts/p58-uninstaller-l10n-capture.sh /tmp/mm-app-p58/MacMaster.app \
#       docs/verification/p58-uninstaller-l10n-bilingual 2>&1 \
#       | tee docs/verification/p58-uninstaller-l10n-bilingual/00-family-run.log
#   ONLY=02-en ./Scripts/p58-uninstaller-l10n-capture.sh …   只重拍某一档
#   KEEP_FIXTURE=1 …                                         不重建夹具（默认每次重建）
#   SETTLE=12 BASELINE_BUFFER=3 AFTER_MUTATE=10 WAIT_TIMEOUT=90 …
#     前三样是盲等（09–12 那四张只有盲等可用），后一样是"有凭据可等"那九张的快门上限。
#
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SETTLE=${SETTLE:-12}
# 监听与废纸篓两档：窗口出现后先留这段时间给 onAppear 建基线，
# 基线晚于改动就会把改动吞成"启动前就在"，照片拍成一张干净的列表。
BASELINE_BUFFER=${BASELINE_BUFFER:-3}
AFTER_MUTATE=${AFTER_MUTATE:-10}
TRASH=/tmp/mmtrash
MMHOME=/tmp/mmhome
STAGE=/tmp/mmstage
APPSROOT=/tmp/mmapps

repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p58 -s /tmp/mm-scratch-p58 重新构建再取证。"
  exit 4
fi

# ---- 夹具 ----
# 默认每次重建：残留行上的体积与路径要指着"这一次真的跑过"的树，
# 拿上一轮的 mktemp 目录重跑，照片与日志只是恰好同名。
if [[ -z ${KEEP_FIXTURE:-} ]]; then
  NEST_FIX=$(./Scripts/p33b-nesting-fixture.sh)
  STEAM_FIX=$(./Scripts/p32-steam-fixture.sh)
  ./Scripts/trash-fixture.sh >/dev/null
  ./Scripts/apps-watch-fixture.sh >/dev/null
  # 废纸篓那一档原本会把真实 /Applications 的 41 个应用全测一遍大小（p68-trash 记的 45 秒代价）。
  # 这里给假 home 补一份 `Applications/Foo.app`：列表只剩夹具那一个，卡片秒级出现，
  # 照片里也不会有任何真机应用名。
  mkdir -p "$MMHOME/Applications"
  [[ -e $STAGE/Foo.app ]] || { print -u2 -- "✗ 夹具缺 $STAGE/Foo.app（重跑 ./Scripts/trash-fixture.sh）"; exit 2; }
  cp -R "$STAGE/Foo.app" "$MMHOME/Applications/"
fi
# `KEEP_FIXTURE=1` 时才走这两行：按 mtime 取最新那一棵（`-dt`），不是按名字尾巴排——
# mktemp 的后缀大小写混排，字典序会挑到上一轮那棵，照片里的路径指着一次没发生过的运行。
NEST_FIX=${NEST_FIX:-$(ls -dt /tmp/macmaster-p33b-nesting.*(N) 2>/dev/null | head -1)}
STEAM_FIX=${STEAM_FIX:-$(ls -dt /tmp/macmaster-steam-fixture.*(N) 2>/dev/null | head -1)}
for required in Fork IDEFoo AssetsFork; do
  [[ -e "$NEST_FIX/Applications/$required.app" ]] || {
    print -u2 -- "✗ P33b 夹具不完整：$NEST_FIX 缺 $required.app"; exit 2; }
done
[[ -d $NEST_FIX/Library/Caches/IDEFoo/AssetsFork ]] || {
  print -u2 -- "✗ P33b 夹具缺 Caches/IDEFoo/AssetsFork——归属复核那一族的主证行没了：$NEST_FIX"; exit 2; }
[[ -e $STEAM_FIX/Applications/SteamGame.app ]] || {
  print -u2 -- "✗ Steam 夹具不完整：$STEAM_FIX 缺 SteamGame.app"; exit 2; }
[[ -d $TRASH && -d $MMHOME && -e $MMHOME/Applications/Foo.app ]] || {
  print -u2 -- "✗ 废纸篓夹具不完整（$TRASH / $MMHOME/Applications/Foo.app）"; exit 2; }
if [[ -e $TRASH/Foo.app ]]; then
  print -r -- "# 提示：假废纸篓里已有 Foo.app（上一轮残留）——reset_trash 会在 09/10 两档各自开工前清掉它，"
  print -r -- "#        基线不会被这次拖入吞掉；不视为夹具坏了。"
fi
[[ -e $APPSROOT/Applications ]] || { print -u2 -- "✗ 装卸监听夹具不存在：$APPSROOT"; exit 2; }

mkdir -p "$OUT"

# 中间动作（只有废纸篓与监听两档用）：窗口出现以后由脚本改目录，模拟"真的发生了这件事"。
MID_CMD=''
MID_WAIT=$AFTER_MUTATE
# 就位凭据（扩展正则）：这一行在日志里出现才按快门。空值=这一张没有可用的应用侧凭据
# （09–12 那四张就是：卡片/面板由目录改动与钩子间接拉起，`MM_SHOW_TRASH_CONFIRM` 与
# `AppFolderWatcher` 都不吐痕），它们只能靠固定等待 + 逐张人眼读，脚本不替它们背书。
WAIT_PATTERN=''
WAIT_TIMEOUT=${WAIT_TIMEOUT:-90}

# shot <名> <语言档|-> <等待秒> "<期望>" <环境变量...>
# 第四个参数**必须加引号**：期望那句是给人读的中文，里面有空格（甚至 `?`）。
# 不加引号会被拆成多个位置参数，`shift 4` 之后剩下的那些字会漏进 env 那一段——
# 上一版就是这么把 01 那一档跑成 `env: N: No such file or directory` 的（窗口根本没起来，
# 而错误只在 .log 最后一行，看终端只会读成"查了 5 次没有可见窗口"）。
shot() {
  local name=$1 lang=$2 settle=$3 expect=$4; shift 4
  # 中间动作与就位凭据都只属于**紧接着的那一次调用**：先取走再判 ONLY，否则 `ONLY=13` 重拍时，
  # 前面某档设下的 mv/depart 会被 13 这一档误当成自己的步骤。
  local mid=$MID_CMD wait_pattern=$WAIT_PATTERN
  MID_CMD=''
  WAIT_PATTERN=''
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  rm -f "$OUT/$name.png"
  print -r -- "# p58-uninstaller-l10n-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   $(mm_provenance_line)" >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=uninstaller${lang:+ MM_LANGUAGE=$lang} $*" >>"$log"
  print -r -- "# 夹具：P33b=$NEST_FIX｜Steam=$STEAM_FIX｜废纸篓=$TRASH（假 home=$MMHOME）｜监听=$APPSROOT" >>"$log"
  print -r -- "# 期望：$expect" >>"$log"
  if [[ -n $mid ]]; then
    print -r -- "# 中间动作：$mid（窗口出现后 ${BASELINE_BUFFER}s 执行，再等 ${MID_WAIT}s）" >>"$log"
  fi
  if [[ -n $wait_pattern ]]; then
    print -r -- "# 就位凭据：等到日志出现 /$wait_pattern/ 才按快门（上限 ${WAIT_TIMEOUT}s）" >>"$log"
  fi
  local pid
  if [[ -n $lang ]]; then
    env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=uninstaller MM_LANGUAGE="$lang" "$@" \
        "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  else
    env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=uninstaller "$@" \
        "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  fi
  pid=$!
  sleep "$settle"
  local wid i
  for i in {1..5}; do
    wid=$(swift Scripts/window-ids.swift --pid "$pid" 2>/dev/null \
          | sed -n 's/^windowid=\([0-9]*\).*/\1/p' | head -1)
    [[ -n $wid ]] && break
    sleep 3
  done
  if [[ -z "$wid" ]]; then
    print -u2 -- "⚠ $name：pid=$pid 查了 5 次没有可见窗口（不产出空照片）"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  if [[ -n $mid ]]; then
    sleep "$BASELINE_BUFFER"
    print -r -- "# 执行中间动作：$mid" >>"$log"
    # 失败不中断这一族（其余档还要拍），但必须在日志里留下痕迹：
    # 下面的凭据循环（Foo.app 进没进废纸篓、Highball 还在不在）会把它算成一个问题。
    eval "$mid" >>"$log" 2>&1 \
      || print -r -- "# ⚠ 中间动作失败：$mid（这张照片显示的态不是要证的那个态）" >>"$log"
    # 有就位凭据时不再盲等：等到那一行就按快门。05/06 尤其要紧——那两张的默认按钮是
    # 「移到废纸篓」，盲等的每一秒都是把删除按钮摆在最前台等人敲回车。
    [[ -n $wait_pattern ]] || sleep "$MID_WAIT"
  fi
  # 快门前的就位闸：凭据行没落，就不算拍到。等满超时也按一张（那张照片要留下来看它到底停在哪一步），
  # 但必须在日志里留下 ⚠——末尾的断言循环按问题计，这一族不结案。
  #
  # **只读应用自己写的那些行**（跳过以 `# ` 开头的本脚本行）。第一版没跳，于是这个闸
  # 每次都在第一时间通过：第 158 行那句声明把 wait_pattern 逐字印进了同一份日志，
  # `grep -qE "$wait_pattern"` 匹配到的是它自己的声明——05/06 两张因此"等了 0s"就按了快门，
  # 而应用侧那行「已用夹具目录 …（N 条）」从头到尾没出现过（面板还没打开）。
  # 一个"等状态落定"的闸如果能把了自己的哨，它就退化成了它要替代的盲等，而且绿得理直气壮。
  if [[ -n $wait_pattern ]]; then
    local waited=0
    credential_present() { grep -v '^#' "$log" | grep -qE -- "$wait_pattern"; }
    while ! credential_present; do
      (( waited >= WAIT_TIMEOUT )) && break
      sleep 1
      waited=$((waited + 1))
    done
    if credential_present; then
      print -r -- "# 就位凭据：等了 ${waited}s 后日志里出现 /$wait_pattern/" >>"$log"
    else
      print -r -- "# ⚠ 就位凭据超时 ${WAIT_TIMEOUT}s 没出现：/$wait_pattern/（这张照片拍的是状态落定之前的画面）" >>"$log"
    fi
  fi
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid settle=${settle}s"
}

nest=(MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$NEST_FIX" MM_UNINSTALL_CONFIRM_MODE=none)
steam=(MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$STEAM_FIX" MM_UNINSTALL_CONFIRM_MODE=none)

# 两档"由脚本改目录"的夹具复位（05/06/09/10/11/12 都要）：这些动作都是一次性的，
# 不复位的话第二档拍到的是空态，而 `ONLY=` 单独重拍时上一轮的残留会直接被当成基线吞掉。
reset_trash() {
  [[ -e "$MMHOME/Applications/Foo.app" ]] || {
    print -u2 -- "✗ 假 home 缺 $MMHOME/Applications/Foo.app：无法复位拖入（重跑 ./Scripts/trash-fixture.sh）"; exit 2; }
  rm -rf "$TRASH/Foo.app" "$STAGE/Foo.app"
  mkdir -p "$STAGE"
  cp -R "$MMHOME/Applications/Foo.app" "$STAGE/"
}
reset_watch() { ./Scripts/apps-watch-fixture.sh >/dev/null; }

# 01/02 残留清单：增强档让「名称包含应用名」那一条出现（严格档按构造到不了它），
# 归属复核的降级行与「（位于 IDEFoo 内）」那一层都挂在同一段列表上。
# 点名行（`已点名到` 或 `没有对应的应用`）就是这一族的状态落定时刻：详情面板、残留清单、
# 页脚那句「已选 N 项残留」全在 `loadApps()` 返回之后的同一个同步块里被填上。
# 等它 = 等到"清单测完大小、点名也点完"，固定秒数做不到这件事（07/08 的第一遍就是证据）。
SELECTED='已点名到|没有对应的应用'
WAIT_PATTERN=$SELECTED
shot 01-zh-residuals zh $SETTLE \
  "「已选 N 项残留 · 体积」页脚、证据句、降级行的提醒、风险标签、类别标题、基本信息八行键名全中文" \
  $nest MM_UNINSTALL_SENSITIVITY=enhanced MM_UNINSTALL_SELECT=Fork MM_WINDOW_SIZE=1400x1000 || true
shot 02-en-residuals en $SETTLE \
  "同一次扫描、同一棵树：以上每一句都换成英文表里那一条，路径与数字一个都不动" \
  $nest MM_UNINSTALL_SENSITIVITY=enhanced MM_UNINSTALL_SELECT=Fork MM_WINDOW_SIZE=1400x1000 || true

# 03/04 确认面板：标题「清理 X 的 N 项残留？」与正文里的 %@ 顺序在英文里是反的（`%2$@`）。
WAIT_PATTERN=$SELECTED
shot 03-zh-confirm zh $SETTLE \
  "面板标题与正文（带应用名、项数、体积）+「仅卸载应用」「移入废纸篓」「取消」三个按钮" \
  MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$NEST_FIX" MM_UNINSTALL_CONFIRM_MODE=withResiduals \
  MM_UNINSTALL_SENSITIVITY=enhanced MM_UNINSTALL_SELECT=Fork MM_WINDOW_SIZE=1400x1000 || true
WAIT_PATTERN=$SELECTED
shot 04-en-confirm en $SETTLE \
  "同一档面板：标题应是「Remove N leftovers of X?」那一种语序，按钮 Uninstall only / Move to Trash / Cancel" \
  MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$NEST_FIX" MM_UNINSTALL_CONFIRM_MODE=withResiduals \
  MM_UNINSTALL_SENSITIVITY=enhanced MM_UNINSTALL_SELECT=Fork MM_WINDOW_SIZE=1400x1000 || true

# 05/06 卸载后遗症：走「重新载入并扫描」那条零点击的来路（理由见文件头 05/06 那一段）。
# `MM_ORPHAN_FIXTURE_HOME` 一生效，`runOrphanScan` 就自动全选并打开确认面板——
# 合成点击进不了勾选框，没有别的办法截到确认态。面板居中，两行列表在它上方照样露出来，
# 所以这一张同时截到确认态与逐行副标题（`MM_UNINSTALL_CONFIRM_MODE=none` 只管卸载面板，管不到这张）。
reset_watch
MID_CMD="./Scripts/apps-watch-fixture.sh depart"; MID_WAIT=$AFTER_MUTATE
# 面板一开就按快门：这一张的默认按钮是「移到废纸篓」，多留一秒就是多一秒被人家的回车替我们按掉。
WAIT_PATTERN="已用夹具目录 $APPSROOT"
shot 05-zh-orphans zh 8 \
  '后遗症确认面板：标题、逐行路径与体积、Highball 那一族（刚消失的那个应用留下的残留）、两个按钮' \
  MM_UNINSTALL_PANE=apps MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$APPSROOT" MM_UNINSTALL_CONFIRM_MODE=none \
  MM_APPS_WATCH_FIXTURE_DIR="$APPSROOT/Applications" MM_APPS_WATCH_AUTO_SCAN=1 \
  MM_ORPHAN_FIXTURE_HOME="$APPSROOT" MM_WINDOW_SIZE=1400x1000 || true
reset_watch
MID_CMD="./Scripts/apps-watch-fixture.sh depart"; MID_WAIT=$AFTER_MUTATE
WAIT_PATTERN="已用夹具目录 $APPSROOT"
shot 06-en-orphans en 8 \
  '同一棵树的英文档：面板句子换英文，路径与主人名（Highball / com.example.Highball）照原样' \
  MM_UNINSTALL_PANE=apps MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$APPSROOT" MM_UNINSTALL_CONFIRM_MODE=none \
  MM_APPS_WATCH_FIXTURE_DIR="$APPSROOT/Applications" MM_APPS_WATCH_AUTO_SCAN=1 \
  MM_ORPHAN_FIXTURE_HOME="$APPSROOT" MM_WINDOW_SIZE=1400x1000 || true

# 07/08 Steam 启动器行：`ui.launcher.basis` 一条塞四个位置参数，是本轮最容易拼错的一句。
# 这两档正是第一遍假绿的那两张：六个应用、其中一个 8.4 MB，12 秒的固定等待比测大小快。
WAIT_PATTERN=$SELECTED
shot 07-zh-launcher zh $SETTLE \
  "详情面板「启动器」那一行：名称、徽章、被指的那个脚本，以及四个参数那句判定依据" \
  $steam MM_UNINSTALL_SELECT=SteamGame MM_UNINSTALL_SENSITIVITY=enhanced MM_WINDOW_SIZE=1400x1000 || true
WAIT_PATTERN=$SELECTED
shot 08-en-launcher en $SETTLE \
  '同一行英文档：四个参数按 %1$@…%4$@ 落位，脚本路径与 appid 一个都不翻' \
  $steam MM_UNINSTALL_SELECT=SteamGame MM_UNINSTALL_SENSITIVITY=enhanced MM_WINDOW_SIZE=1400x1000 || true

# 09/10 废纸篓确认：拖入这个动作由脚本 mv 完成（kqueue 收到的是真实目录改动），
# `MM_SHOW_TRASH_CONFIRM` 替我们按下「清理勾选的残留」——合成点击进不了原生勾选框。
#
# 每一档**先复位再拍**（清空假废纸篓 + 把 Foo.app 放回 /tmp/mmstage）：
# mv 是一次性动作，第二档若不先复位，源目录已经空了，照片拍到的是一张"什么都没拖进来"的列表；
# 而 `ONLY=09` 单独重拍时，上一轮留下的 `$TRASH/Foo.app` 会直接被基线吞掉。
#
# 这四张（09–12）**没有应用侧的就位凭据**：`MMHookValue.flag` 与 `TrashWatcher`/`AppFolderWatcher`
# 都不为"卡片画出来了"吐痕，所以 `WAIT_PATTERN` 留空、只靠改目录 + 等 ${AFTER_MUTATE}s。
# 于是它们的凭据证的是"目录真的改了"，不是"卡片已经在画面上"——这一档的判据比 01–08 弱一级，
# 必须逐张人眼读，只看退出码等于没读。
WAIT_PATTERN=''
reset_trash
MID_CMD="mv $STAGE/Foo.app $TRASH/"; MID_WAIT=$AFTER_MUTATE
shot 09-zh-trash zh 8 \
  "废纸篓确认面板：标题「清理 示例应用 的 N 项残留？」（那棵假 home 里的 Foo.app 显示名是示例应用）、正文那句只删勾选残留、按钮对调" \
  MM_TRASH_FIXTURE_DIR="$TRASH" MM_TRASH_SCAN_HOME="$MMHOME" MM_SHOW_TRASH_CONFIRM=1 \
  MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$MMHOME" MM_UNINSTALL_CONFIRM_MODE=none MM_WINDOW_SIZE=1400x1000 || true
reset_trash
MID_CMD="mv $STAGE/Foo.app $TRASH/"; MID_WAIT=$AFTER_MUTATE
shot 10-en-trash en 8 \
  "同一档面板英文：标题应是「Clean N leftovers of 示例应用?」那一种语序（应用名不翻）；假废纸篓里躺的是这一次自己的拖入" \
  MM_TRASH_FIXTURE_DIR="$TRASH" MM_TRASH_SCAN_HOME="$MMHOME" MM_SHOW_TRASH_CONFIRM=1 \
  MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$MMHOME" MM_UNINSTALL_CONFIRM_MODE=none MM_WINDOW_SIZE=1400x1000 || true

# 11/12 装卸监听消失卡：改动必须发生在监听建好基线之后，否则这一档被吞进基线（老规矩）。
# 同理每档先重建夹具：`depart` 拿走 Highball 是一次性的，第二档若不重建，
# 目录里既没有 Highball、Notion 又已在基线里，卡片会空——而空卡片和"报了 0 条"在照片上分不出来。
reset_watch
MID_CMD="./Scripts/apps-watch-fixture.sh depart"; MID_WAIT=$AFTER_MUTATE
shot 11-zh-watch zh 8 \
  '「刚从应用目录消失」那张卡：卡上那句 + 逐条跳过的说明（ui.watch.banner_clause_* / skip_line）' \
  MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$APPSROOT" MM_UNINSTALL_CONFIRM_MODE=none \
  MM_APPS_WATCH_FIXTURE_DIR="$APPSROOT/Applications" MM_WINDOW_SIZE=1400x1000 || true
reset_watch
MID_CMD="./Scripts/apps-watch-fixture.sh depart"; MID_WAIT=$AFTER_MUTATE
shot 12-en-watch en 8 \
  "同一档卡片的英文：被消失的应用名（Highball）与路径照原样，句子换英文" \
  MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$APPSROOT" MM_UNINSTALL_CONFIRM_MODE=none \
  MM_APPS_WATCH_FIXTURE_DIR="$APPSROOT/Applications" MM_WINDOW_SIZE=1400x1000 || true

# 13 英文窄窗：`MMKeyRow` 的键名列固定 80 pt（`MMDesign.swift:387`），英文标签一律更长。
# 这一张还顺带量到另一件事：页头副标题在 1000 pt 下会不会把「合计」那一段吃掉（第一遍读图读到的）。
WAIT_PATTERN=$SELECTED
shot 13-en-narrow en $SETTLE \
  "1000×800 英文档的详情面板：基本信息那八行的键名会不会被省略号吃掉" \
  $nest MM_UNINSTALL_SENSITIVITY=enhanced MM_UNINSTALL_SELECT=Fork MM_WINDOW_SIZE=1000x800 || true

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)
print -r -- "# 语言档落在 UserDefaults：域=$BUNDLE_ID key=app.language（跑完会 delete）"
if [[ -n $BUNDLE_ID ]]; then
  defaults delete "$BUNDLE_ID" app.language 2>/dev/null || print -r -- "  （该域本来没有 app.language，delete 空手而归）"
  print -r -- "# 复位后 defaults read：$(defaults read "$BUNDLE_ID" app.language 2>&1 | tr '\n' ' ')"
else
  print -u2 -- "⚠ 读不到 $APP 的 CFBundleIdentifier：`defaults delete` 没跑，语言档可能还留在 UserDefaults"
fi
WAIT_PATTERN=$SELECTED
shot 14-zh-after-reset "" $SETTLE \
  "不带 MM_LANGUAGE：应回到中文档（这张证的是复位，不是新状态）" \
  $nest MM_UNINSTALL_SELECT=Fork MM_WINDOW_SIZE=1400x1000 || true

# ---- 正向断言 ----
typeset -a PROBLEMS FAILED SHOTS
SHOTS=(01-zh-residuals 02-en-residuals 03-zh-confirm 04-en-confirm 05-zh-orphans 06-en-orphans
       07-zh-launcher 08-en-launcher 09-zh-trash 10-en-trash 11-zh-watch 12-en-watch
       13-en-narrow 14-zh-after-reset)
print -r -- ""
print -r -- "# 留痕：每一张都要自己说出用的是哪一档"
for f in "${SHOTS[@]}"; do
  [[ -z ${ONLY:-} || $f == ${ONLY}* ]] || continue
  lg="$OUT/$f.log"
  [[ -s $lg ]] || { FAILED+=$f; continue; }
  if [[ $f == 14-* ]]; then
    # 反向判据也只读应用那一侧：本脚本的 `# env:` 头行逐字记着自己传了什么变量，
    # 将来若把 MM_LANGUAGE 写进某一档的期望句或声明里，这条就会永远报"没复位"。
    if grep -v '^#' "$lg" | grep -qF 'MM_LANGUAGE='; then
      PROBLEMS+=("14 那张不带变量的照片里出现了 MM_LANGUAGE 留痕 ⟹ defaults delete 没把档复位")
    else
      print -r -- "  ✓ $f：无 MM_LANGUAGE 留痕（复位成立）"
    fi
    continue
  fi
  case $f in
    *zh-*) lang=zh-Hans ;;
    *) lang=en ;;
  esac
  line=$(grep -v '^#' "$lg" | grep -m1 -F "MM_LANGUAGE=$lang 已生效" || true)
  if [[ -n $line ]]; then
    print -r -- "  ✓ $f：$line"
  else
    PROBLEMS+=("$f 没有「MM_LANGUAGE=$lang 已生效」这一行——照片无从认档（日志头 120 字：$(head -c 120 "$lg" | tr '\n' ' ')）")
  fi
done

# 快门前的就位闸有没有超时：这一条把"日志里出现过凭据"升级成"凭据出现在快门之前"。
# 超时的那一张照样留下照片（要看它到底停在哪一步），但这一族不结案。
print -r -- ""
print -r -- "# 就位闸：每一张带凭据的照片都要在快门之前等到那一行"
for f in "${SHOTS[@]}"; do
  [[ -z ${ONLY:-} || $f == ${ONLY}* ]] || continue
  lg="$OUT/$f.log"
  [[ -s $lg ]] || continue
  if grep -qF '⚠ 就位凭据超时' "$lg"; then
    PROBLEMS+=("$f：快门前没等到就位凭据（见 $f.log 的 ⚠ 行）——这张拍的是状态落定之前的画面，P6.7b 那一族「日志绿、照片空」的坑在这儿重新张开")
  elif grep -qF '# 就位凭据：等了 ' "$lg"; then
    print -r -- "  ✓ $f：$(grep -m1 -F '# 就位凭据：等了 ' "$lg")"
    # 点名那一族的凭据是"成对"的：点到了与没点到都算落定，但只有前者配当凭据。
    # **只认应用自己写的那一行**（行首 `MM_UNINSTALL_SELECT=`，见 `MMUninstaller.swift:119/:121`）。
    # 第一版这里写的是不带锚的 `grep -qF '没有对应的应用'`，于是它匹配到的是本脚本
    # 第 158 行那句凭据声明——声明里逐字带着 wait_pattern（含这个反面分支），
    # 七个档被报成"照片是一张空态"而照片其实是好的。判据不能读到自己。
    if grep -qE '^MM_UNINSTALL_SELECT=[^ ]+ 没有对应的应用' "$lg"; then
      PROBLEMS+=("$f：点名没点到应用（$lg 行首那条 MM_UNINSTALL_SELECT 报「没有对应的应用」）——清单里没这个名字，照片是一张空态")
    fi
  else
    print -r -- "  – $f：这一张没有应用侧凭据可等（09–12 那一族，判据弱一级，必须人眼读）"
  fi
done

# 中间动作那一档的凭据：改动没落到目录上，照片就只是一张空列表，而它和"报了什么"看着一样。
# 判据看**这一张自己的日志**（`mv` 有没有失败），不看跑完之后的目录状态：
# 目录状态会被下一档的同一次拖入覆盖，10 那一张的成功会替 09 顶罪。
for f in 09-zh-trash 10-en-trash; do
  [[ -z ${ONLY:-} || $f == ${ONLY}* ]] || continue
  [[ -s "$OUT/$f.log" ]] || continue
  if grep -qF '中间动作失败' "$OUT/$f.log"; then
    PROBLEMS+=("$f：那一次 mv 失败了（见 $f.log 的「⚠ 中间动作失败」行）——$TRASH/Foo.app 没进来，那张卡片无从凭信")
  elif grep -qF "# 执行中间动作：mv $STAGE/Foo.app $TRASH/" "$OUT/$f.log"; then
    print -r -- "  ✓ $f 拖入凭据：本张日志里 mv 执行过且没报错（$TRASH/Foo.app 由这一次产生）"
  else
    PROBLEMS+=("$f：日志里没有「执行中间动作：mv」这一行 ⟹ 拖入这一步压根没跑，照片里那句「在废纸篓里」是假的")
  fi
done
for f in 11-zh-watch 12-en-watch; do
  [[ -z ${ONLY:-} || $f == ${ONLY}* ]] || continue
  [[ -s "$OUT/$f.log" ]] || continue
  if grep -qF '中间动作失败' "$OUT/$f.log"; then
    PROBLEMS+=("$f：那一次 depart 失败了（见 $f.log）——$APPSROOT/Applications/Highball.app 没被移走，消失卡无从产生")
  elif grep -qF "# 执行中间动作：./Scripts/apps-watch-fixture.sh depart" "$OUT/$f.log"; then
    print -r -- "  ✓ $f 装卸凭据：本张日志里 depart 执行过且没报错（当前目录态：$( [[ -e $APPSROOT/Applications/Highball.app ]] && echo 'Highball 仍在' || echo 'Highball 已消失' )）"
  else
    PROBLEMS+=("$f：日志里没有「执行中间动作：…depart」这一行 ⟹ 目录没改过，卡片上那句「刚从应用目录消失」是假的")
  fi
done

# 后遗症那两张：面板是被钩子自动打开的，条数只有日志里那一行说得出。
# 0 条也写（空面板与没扫描是两件事），但 0 条的照片对不上"这一族要拍的那一行"，所以按问题记。
for f in 05-zh-orphans 06-en-orphans; do
  [[ -z ${ONLY:-} || $f == ${ONLY}* ]] || continue
  [[ -s "$OUT/$f.log" ]] || continue
  # 同样只读应用那一侧：这一档的 wait_pattern 声明行里也带着「已用夹具目录 …」那一串，
  # 上一版 `grep -m1` 取到的第一条就是声明本身（不带「（N 条）」），于是条数判空判不出来，
  # ✓ 打的是脚本自己的话。
  line=$(grep -v '^#' "$OUT/$f.log" | grep -m1 -F "已用夹具目录 $APPSROOT" || true)
  n=$(printf '%s' "$line" | sed -nE 's/.*（([0-9]+) 条）.*/\1/p')
  if [[ -z $line ]]; then
    # 应用侧在"清单还在枚举/为空"时会点名退出并留一行拒绝原因（`MMUninstaller.swift:562`）：
    # 有那一行就把它抄进问题里，省得下次再靠猜。
    refusal=$(grep -v '^#' "$OUT/$f.log" | grep -m1 -F '孤儿夹具扫描**没有执行**' || true)
    PROBLEMS+=("$f：日志里没有「已用夹具目录 $APPSROOT …自动勾选并打开确认面板」这一行 ⟹ 要么 depart 没让 Highball 的残留变成孤儿，要么「重新载入并扫描」没跑（清单为空会被点名拒绝），面板没打开${refusal:+（应用自己说的：$refusal）}")
  elif [[ $n == 0 ]]; then
    PROBLEMS+=("$f：孤儿扫出 0 条——$APPSROOT 这棵树或那次 depart 不对，照片里那张面板是空的")
  else
    print -r -- "  ✓ $f 后遗症凭据：$line"
  fi
done

print -r -- ""
print -r -- "# 画面交叉核对（同屏双语必须不同，否则语言档在画面上没起作用）"
for png in "$OUT"/*.png(N); do print -r -- "  md5 $(md5 -q "$png")  $(basename "$png")"; done
typeset -a PIX_PAIRS=("01-zh-residuals|02-en-residuals" "03-zh-confirm|04-en-confirm"
                      "05-zh-orphans|06-en-orphans" "07-zh-launcher|08-en-launcher"
                      "09-zh-trash|10-en-trash" "11-zh-watch|12-en-watch")
pix_report=''
pix_rc=0
if ! python3 -c 'import PIL' >/dev/null 2>&1; then
  PROBLEMS+=("本机 python3 没有 PIL：像素比对没跑，这一族的画面判据不能空过")
else
  pix_report=$(python3 - "$OUT" "${PIX_PAIRS[@]}" <<'PY'
import os
import sys
from PIL import Image, ImageChops

SIDEBAR_X = 218


def count(img_a, img_b, left):
    d = ImageChops.difference(img_a, img_b).convert('RGB')
    r, g, b = d.split()
    hist = ImageChops.lighter(ImageChops.lighter(r, g), b).histogram()
    above = sum(hist[9:])
    peak = max(i for i in range(256) if hist[i])
    d = d.crop((left, 0, d.size[0], d.size[1]))
    r, g, b = d.split()
    hist = ImageChops.lighter(ImageChops.lighter(r, g), b).histogram()
    return above, sum(hist[9:]), peak


out = sys.argv[1]
for spec in sys.argv[2:]:
    a, b = spec.split('|')
    fa = os.path.join(out, a + '.png')
    fb = os.path.join(out, b + '.png')
    if not (os.path.exists(fa) and os.path.exists(fb)):
        print('\t'.join((a, b, 'missing', '-', '-', '-')))
        continue
    ia = Image.open(fa).convert('RGB')
    ib = Image.open(fb).convert('RGB')
    if ia.size != ib.size:
        print('\t'.join((a, b, 'sizediff', '%s vs %s' % (ia.size, ib.size), '-', '-')))
        continue
    whole, content, peak = count(ia, ib, SIDEBAR_X)
    print('\t'.join((a, b, str(content), str(peak), str(whole), str(whole - content))))
PY
) || pix_rc=$?
fi
pix_lines=$(printf '%s\n' "$pix_report" | grep -c . || true)
if (( pix_lines < ${#PIX_PAIRS[@]} )); then
  PROBLEMS+=("像素比对只出了 $pix_lines 行，该出 ${#PIX_PAIRS[@]} 行（python 退出码 $pix_rc）——判据没跑完就是没过")
fi
while IFS=$'\t' read -r a b above maxd whole strip; do
  [[ -n $a ]] || continue
  case $above in
    missing) PROBLEMS+=("$a ↔ $b：有一张没拍出，比对无从进行"); continue ;;
    sizediff) PROBLEMS+=("$a ↔ $b 两张尺寸不同（$maxd）：不是一扇窗口的两种档，比对无意义"); continue ;;
  esac
  print -r -- "  · $a ↔ $b：内容区 $above 个可辨像素｜侧栏条（不参与判据）$strip 个｜全帧 $whole 个｜最大幅度 $maxd"
  if (( above > 0 )); then
    print -r -- "  ✓ $a ↔ $b：内容区有可辨差异 $above 个像素"
  else
    PROBLEMS+=("$a ↔ $b：内容区可辨差异 0 个像素（最大幅度 $maxd）——这一对本该不同：语言档没在界面上起作用")
  fi
done <<< "$pix_report"

for f in "${SHOTS[@]}"; do
  [[ -z ${ONLY:-} || $f == ${ONLY}* ]] || continue
  [[ -s "$OUT/$f.png" ]] || FAILED+=$f
done

if (( ${#PROBLEMS[@]} > 0 )); then
  for p in "${PROBLEMS[@]}"; do print -u2 -- "⚠ $p"; done
  print -u2 -- "✗ 核对没过，这一族不算取证完成"
  exit 1
fi
if (( ${#FAILED[@]} > 0 )); then
  print -u2 -- "✗ 这些档位没拍出照片：${FAILED[*]}"
  print -r -- "→ $OUT"
  exit 1
fi

print -r -- "→ $OUT（$APPEARANCE）｜残留清单 / 确认面板 / 后遗症 / 启动器 / 废纸篓 / 监听 × 双语 + 英文窄窗 + 复位"
print -r -- "夹具：$NEST_FIX · $STEAM_FIX · $TRASH/$MMHOME · $APPSROOT（留 /tmp，不入库）"
