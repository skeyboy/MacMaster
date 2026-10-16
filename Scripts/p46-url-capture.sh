#!/bin/zsh
# P46e 取证：深链 `macmaster://uninstall?path=…` 打进真 app，卸载页切到哪一行。
#
# 这一族要钉的是**单测钉不到的那一段**：解析、去重、`%20`→空格 这些 `URLComponents` 的
# 行为已经在 `UninstallerOpenURLTests` 里钉死了，这里量的是"一条真 URL 交给真 app，
# 中间穿过 LaunchServices 那一段有没有被拆坏、界面到底切没切"。合同原文在
# `docs/analysis/uninstally-adoption.md` 落地顺序第 5 条：
#   「验收：`open -a` 一条命令送进一个 `.app` 路径，页面切到该项的残留清单；
#     并附一条否证：同一个 URL 里塞 `/System/Library`，断言它进不了删除计划的入参。」
# 否证的**代码**那一半已由 `testSystemPathFromAUrlCannotBecomeADeletionInput` 钉住，
# 这里补的是**画面**那一半：06 那一档送的是 `/System/Library/CoreServices/Finder.app`，
# 判据是①stderr 有「入站点名的 bundle 不在应用清单里」，②画面与 01 没有任何一处可辨差异。
# ②不写成"逐字节相同"：那是第一版的写法，它立不住，理由整段记在下面 ③。
#
# 01 那张**不是**"什么都没选中"：`MM_UNINSTALL_CONFIRM_FIXTURE_HOME` 一设，
# `confirmationTarget()`（`MMUninstaller.swift:109-120`）就把兜底落在"夹具 home 里的第一个应用"，
# 于是基线停在 OtherFoo、页脚还带着默认勾选的「已选 1 项残留」。
# 所以 02 的判据是"选中条从 OtherFoo 挪到 UrlFoo"，不是"从空变成有"。
# 这一条是重看第一张 01 照片才发现的：写脚本时我按"没送 URL = 没选中"想当然，
# 而照片一句话就把这个想法否了——判据得跟着画面改，不能跟着设想改。
#
# 为什么全程走 `open` 而不是像别的族那样直接起二进制：URL 是**外部事件**，只能由
# LaunchServices 投递（`.onOpenURL` 收的是 `kAEOpenURLs`）。直接起进程送不进去。
# 代价是环境变量得靠 `open --env`（本机 `open` 支持，实测），收尾要按 pgrep 找 pid
# 而不是 `$!`——`open` 自己立刻退出，留下的进程不是它的子进程。
#
# 顺手钉住的第二件事（写这一族之前不知道）：`WindowGroup` 把"外部送进来一个 URL"当成
# "再开一个窗口"。实测 `open -a MacMaster.app -u macmaster://…` 之后 pid 不变、
# `title=MacMaster` 的窗口从 1 扇变 2 扇，新那扇还是 1100×700（`.defaultSize`，
# 而 `LaunchWindowSizeOverride` 是一次性的，只夹得住第一扇）。两扇 `MainWindow` 各有
# 自己的 `@StateObject`，点名队列却是进程级的，谁先 `onChange` 谁吃掉——用户会看到
# 两扇窗口对同一条 URL 给出相反的答案。所以场景换成了单例 `Window("MacMaster", id:"main")`，
# **每一档都数一遍窗口数**（`# windows` 行），08 那一档还额外数"送 URL 之前"一次。
#
# 八档各拍什么（夹具见 `Scripts/p46-url-fixture.sh`）：
#   01 基线：不送 URL → 停在兜底选中的第一行 OtherFoo（页脚「已选 1 项残留 · 1 MB」）。
#   02 主用例：送 `path=<夹具>/UrlFoo.app` → 选中条从 OtherFoo 挪到 UrlFoo，右侧是它的三行残留。
#   03 顺序：两条 `path=`（ThirdFoo 在前、UrlFoo 在后）→ 点的是**第一个**。
#   04 空格：`Space%20Foo.app` → 选中 "Space Foo"。钉的是"URL 原样穿过 LS 没被拆坏"。
#   05 覆盖：`MM_UNINSTALL_SELECT=OtherFoo` 先把一行选上，再送 UrlFoo → 仍是 URL 说了算。
#   06 否证：`path=/System/Library/CoreServices/Finder.app` → 什么都没变 + stderr 留痕。
#   07 空点名：`macmaster://uninstall`（一个 `path=` 都没有）→ 什么都没变 + 另一条留痕。
#   08 热实例：先把 app 起起来（无 URL），稳定之后再送同一条 URL → 仍是一扇窗、选中 UrlFoo。
#      这一档才是"访达右键 → 打开方式"的真实时序（用户那侧 MacMaster 早就开着了）。
#
# 全程零合成点击；只 kill 自己按 pid 起的那一份；夹具在 /tmp 下、退出即删；不碰废纸篓、
# 不请求权限、不删任何东西——点名只是一次"看哪一个"的切换。
#
#   ./Scripts/p46-url-capture.sh <app 路径> <输出目录> [light|dark]
#   ./Scripts/p46-url-capture.sh /tmp/mm-app-p46/MacMaster.app docs/verification/p46-url \
#       2>&1 | tee docs/verification/p46-url/00-run.log
#   ONLY=02 ./Scripts/p46-url-capture.sh …      只重拍 02 那一档
#   SETTLE=12 …                                  改基础等待（清单要等 `loadApps()` 跑完）
#
# 那一条 `tee` 不是可选的：下面三组核对（窗口数 / 留痕 / 像素）只往 stdout 报，
# 每档的 `.log` 里只有头部凭据和进程 stderr，跑完不接住 stdout 就等于把判据留在终端上——
# 档案里剩下八张照片，谁也没法从照片核出"被拒的那条 URL 真的没动画面"这一句。
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SETTLE=${SETTLE:-9}

# 归因头 + 内容指纹门禁（配方见 mm-provenance.sh）：不等就一张都不出。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)
source "$HERE/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p46 -s /tmp/mm-scratch-p46 重新构建再取证。"
  exit 4
fi

# scheme 不抄字面量：判据在 `UninstallerOpenURL.scheme`，抄一份进脚本，改了代码忘了改脚本
# 时这一族会假绿。这里从**产物 plist** 读回来（`make-app.sh` 的 `CFBundleURLTypes` 与代码里
# 那一个是同一件事的两处落点，读不到就说明其中一处没落地）。
scheme=$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw "$APP/Contents/Info.plist" 2>/dev/null) \
  || { print -u2 -- "⚠ 产物 plist 里没有 CFBundleURLTypes：深链根本进不了这个 app，一张都不出"; exit 4; }
print -r -- "产物注册的 scheme：$scheme"

app_bin=$(cd "$APP/Contents/MacOS" && pwd -P)/$(basename "$APP" .app)
# 只认这一份产物起起来的进程：用户机器上可能正跑着 /Applications/MacMaster.app，
# 按进程名 pgrep 会把它一起 kill 掉。
own_pids() { pgrep -f "$app_bin" || true }

# 前置检查：这份产物一份都不能已经在跑。每一档都靠"本产物的进程正好一份"认 pid
# （`own_pids` 要轮询到 1 才继续），外面多一份同产物在跑，这一档就只能作废。
# 这里只报 pid、不代关：脚本没有资格替用户关掉他正在看的窗口。
stray=$(own_pids)
if [[ -n $stray ]]; then
  print -u2 -- "⚠ 这份产物已经有实例在跑：${stray//$'\n'/ }"
  print -u2 -- "  先关掉它们再取证，否则每一档都没法认定 pid 归属。"
  exit 5
fi

FIX=$("$HERE/p46-url-fixture.sh")
# 钩子会把假 home 规范化（`UninstallFixtureHooks.canonicalHome`），而 `AppScanner` 拼出来的
# 清单路径跟着那份规范化走；/tmp 是 /private/tmp 的符号链接，所以 URL 里必须写**规范形**，
# 否则点的是"清单里没有的那一句"。这不是代码缺陷：真实清单根（/Applications、NSHomeDirectory()、
# 挂载卷）本来就是规范形，只有夹具会撞上这条。
FIX_CANON=$(cd "$FIX" && pwd -P)
cleanup() { rm -rf "$FIX"; }
trap cleanup EXIT

mkdir -p "$OUT"
# 当场转绝对：`open --stderr` 交出去的路径与 `.log` 里写的都是这个目录下的文件，
# 留相对路径等于让凭据跟着调用方的 cwd 变——换个目录重跑，日志里那串路径讲的就不是同一件事了。
OUT="$(cd "$OUT" && pwd -P)"
wants() { [[ -z ${ONLY:-} || $1 == ${ONLY}* ]] }

main_window_id() {
  local pid=$1 err=$2 all wid n
  all=$(swift "$HERE/window-ids.swift" --pid "$pid" 2>>"$err" || true)
  print -r -- "# windows(pid=$pid): ${all//$'\n'/ | }" >>"$err"
  n=$(printf '%s\n' "$all" | grep -c 'layer=0 title=MacMaster bounds=' || true)
  [[ $n == 1 ]] || return 1
  wid=$(printf '%s\n' "$all" | sed -n 's/^windowid=\([0-9]*\) .*layer=0 title=MacMaster bounds=.*/\1/p')
  [[ -n $wid ]] || return 1
  print -r -- "$wid"
}

# 每一档都要的五个 `open --env` 参数。写成数组而不是函数返回一段字符串：zsh 默认
# 不对 `$(…)` 做词分割，`$(base_env)` 会整段变成一个参数。
base_env=(--env "MM_APPEARANCE=$APPEARANCE" --env MM_WINDOW_SIZE=1400x900
          --env MM_OPEN_MODULE=uninstaller --env "MM_UNINSTALL_CONFIRM_FIXTURE_HOME=$FIX_CANON"
          --env MM_UNINSTALL_CONFIRM_MODE=none)

# shot <文件名> <URL（空=不送）> [额外 --env 参数…]
# 返回非 0 = 这一档没拍到；调用处一律 `|| true` 兜住 `set -e`，最后由 png 存在性统一判失败。
shot() {
  local name=$1 url=$2; shift 2
  wants $name || return 0
  local log="$OUT/$name.log" err="$OUT/$name.stderr"
  # 只删、**不预先创建**这个文件。实测两因子叠加才会让 `open` 整次启动失败：
  #   err 已存在 ∧ 它在 `~/Desktop` 下（TCC 保护目录）→ `_LSOpenURLsWithCompletionHandler() … -10810`；
  #   文件不存在（LS 自己建）或目录在 /tmp 下 → rc=0。四格都跑过，只有那一格红。
  # 所以以前那句 `: >"$err"`（为了后面 `cat` 不扑空而先占个文件）就是根因，
  # 而它只在证据目录写进仓库时才炸——换到 /tmp 下重跑同一份脚本立刻就好，
  # 这个"换个目录就好"的假象让我先怀疑了参数、又怀疑了野实例，两轮都是白跑。
  # 代价是 stderr 可能压根不存在，读它的那几处一律 `2>/dev/null || true`。
  rm -f "$OUT/$name.png" "$err"
  local -a urlargs
  [[ -n $url ]] && urlargs=(-u "$url")
  if ! open -F -n -g "${base_env[@]}" "$@" --stderr "$err" -a "$APP" "${urlargs[@]}"; then
    print -u2 -- "⚠ $name：open 送 URL 失败"
    rm -f "$err"
    return 1
  fi
  local pid="" wid="" i n
  for i in {1..10}; do
    sleep 2
    n=$(own_pids | wc -l | tr -d ' ')
    if (( n == 1 )); then pid=$(own_pids); break; fi
    if (( n > 1 )); then print -u2 -- "⚠ $name：同时有 $n 份本产物在跑，这一档作废"; rm -f "$err"; return 1; fi
  done
  if [[ -z $pid ]]; then print -u2 -- "⚠ $name：没找到本产物的进程（$app_bin）"; rm -f "$err"; return 1; fi
  for i in {1..5}; do
    wid=$(main_window_id "$pid" "$err" || true)
    [[ -n $wid ]] && break
    sleep 3
  done
  if [[ -z $wid ]]; then
    print -u2 -- "⚠ $name：pid=$pid 反复查了 5 次，标题为 MacMaster 的主窗口不是正好一扇（stderr 见下）"
    kill "$pid" 2>/dev/null || true
    [[ -f $err ]] && cat "$err" >&2 || true
    rm -f "$err"
    return 1
  fi
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  # .log = 头部凭据 + 进程 stderr 原文（`open --stderr` 会自己开文件，不能直接当 .log 用）。
  {
    print -r -- "# p46-url-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP"
    print -r -- "# repo: $repoTag   # app-repo: $appRepoTag"
    mm_provenance_line
    print -r -- "# fixture: $FIX_CANON"
    print -r -- "# url: ${url:-（不送 URL）}"
    print -r -- "# 额外 env：$*"
    print -r -- "# 进程 stderr："
    cat "$err" 2>/dev/null || true
  } >"$log"
  rm -f "$err"
  print -r -- "✅ $name pid=$pid windowid=$wid ${url:+url=<已送>}"
}

url_for() { print -r -- "$scheme://uninstall?path=$1" }

# 01 基线：什么都不送 → 停在兜底选中的第一行（见开头那段：`confirmationTarget()` 的兜底）。
#    06/07 两张要跟它逐字节相同才算"拒了 = 画面一个像素都没动"。
shot 01-baseline-no-url "" || true
# 02 主用例：合同里那一条。
shot 02-url-named-app "$(url_for "$FIX_CANON/Applications/UrlFoo.app")" || true
# 03 顺序：两条 path=，点第一个（访达多选的时序就是用户点的那个在前）。
shot 03-url-multi-first-wins "$(url_for "$FIX_CANON/Applications/ThirdFoo.app")&path=$FIX_CANON/Applications/UrlFoo.app" || true
# 04 空格：`%20` 要穿过 open/LaunchServices 这一段才回到空格。
shot 04-url-space-percent20 "$(url_for "$FIX_CANON/Applications/Space%20Foo.app")" || true
# 05 覆盖：另一条点名钩子先选上 OtherFoo，URL 后到，仍由 URL 说了算
#    （消费顺序见 `MMUninstaller.swift` 的 `.task`：`confirmationTarget()` 在前、`applyScanRequestIfNeeded()` 在后）。
shot 05-url-overrides-select-hook "$(url_for "$FIX_CANON/Applications/UrlFoo.app")" \
     --env MM_UNINSTALL_SELECT=OtherFoo || true
# 06 否证：送一条系统路径。它点不中任何东西，画面该与 01 一模一样。
shot 06-url-system-path-refused "$(url_for "/System/Library/CoreServices/Finder.app")" || true
# 07 空点名：scheme 与 host 都对、一个 path= 都没有。
shot 07-url-without-path-refused "$scheme://uninstall" || true

# 08 热实例：先把 app 起起来（无 URL），数一次窗口，再送同一条 URL。
#    这一档不走 `shot`：它要在**同一个进程**上做两次投递，而 shot 是一档一进程。
if wants 08-hot-instance-receives-url; then
  name=08-hot-instance-receives-url
  log="$OUT/$name.log"; err="$OUT/$name.stderr"
  rm -f "$OUT/$name.png" "$err"   # 同 `shot`：绝不预先创建 err，见那里的两因子说明
  url8=$(url_for "$FIX_CANON/Applications/UrlFoo.app")
  print -r -- "# p46-url-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# fixture: $FIX_CANON" >>"$log"
  print -r -- "# 时序：先起（无 URL）→ 数窗口 → 送 $url8 → 再数窗口" >>"$log"
  # 这一行以前没兜住：`set -e` 下 open 一失败整个脚本当场终止，留下半截 .log，
  # 看起来像"这一档自己出问题"，其实前七档全都没起来。
  open -F -n -g "${base_env[@]}" --stderr "$err" -a "$APP" \
    || print -u2 -- "⚠ $name：open 起进程失败（失败原因见 shot 里那两因子：err 不能预先存在）"
  pid8=""; i=""
  for i in {1..10}; do
    sleep 2
    [[ $(own_pids | wc -l | tr -d ' ') == 1 ]] && { pid8=$(own_pids); break; }
  done
  if [[ -z $pid8 ]]; then
    print -u2 -- "⚠ $name：没找到本产物的进程（$app_bin）"
    rm -f "$err"
  else
    sleep $SETTLE
    before=$(swift "$HERE/window-ids.swift" --pid "$pid8" 2>>"$err" | grep -c 'layer=0 title=MacMaster bounds=' || true)
    print -r -- "# 送 URL 之前：主窗口 $before 扇" >>"$log"
    # 这一档的核心事件就是"投递进一个已经活着的热实例"，所以它的返回码本身要进日志：
    # 光看照片分不清"URL 没送到"与"送到了但界面没动"。
    rc8=0; open -g -a "$APP" -u "$url8" || rc8=$?
    print -r -- "# 第二次 open（送 URL 进热实例）rc=$rc8" >>"$log"
    sleep $SETTLE
    after=$(swift "$HERE/window-ids.swift" --pid "$pid8" 2>>"$err" || true)
    n_after=$(printf '%s\n' "$after" | grep -c 'layer=0 title=MacMaster bounds=' || true)
    print -r -- "# windows(pid=$pid8): ${after//$'\n'/ | }" >>"$log"
    print -r -- "# 送 URL 之后：主窗口 $n_after 扇" >>"$log"
    if [[ $n_after == 1 ]]; then
      wid8=$(printf '%s\n' "$after" | sed -n 's/^windowid=\([0-9]*\) .*layer=0 title=MacMaster bounds=.*/\1/p')
      screencapture -o -x -l"$wid8" "$OUT/$name.png"
      print -r -- "✅ $name pid=$pid8 windowid=$wid8（送前 $before 扇 / 送后 $n_after 扇）"
    else
      print -u2 -- "⚠ $name：送完 URL 变成 $n_after 扇（送前 $before）——单例场景没兜住热实例这一路"
    fi
    kill "$pid8" 2>/dev/null || true
    print -r -- "# 进程 stderr：" >>"$log"; cat "$err" >>"$log"; rm -f "$err"
  fi
fi

typeset -a FAILED
for f in 01-baseline-no-url 02-url-named-app 03-url-multi-first-wins 04-url-space-percent20 \
         05-url-overrides-select-hook 06-url-system-path-refused 07-url-without-path-refused \
         08-hot-instance-receives-url; do
  wants $f || continue
  [[ -s "$OUT/$f.png" ]] || FAILED+=($f)
done

# ── 核对：三组断言 ─────────────────────────────────────────────────
# ① 窗口数：每一档都必须**正好一扇** `title=MacMaster`。这是单例场景那一处改动的正面证据
#    （`WindowGroup` 下 02–07 每一档都是两扇，`main_window_id` 当场判不出主窗口）。
# ② 留痕：06 必须有「入站点名的 bundle 不在应用清单里」，07 必须有「收到的 URL 里没有可用的 path=」；
#    01–05 与 08 两条都必须**没有**（有就说明点名的东西没落进清单，那张照片讲的就不是"切到了"）。
# ③ 画面：01↔02 有可辨差异（URL 确实把选中条挪了）、02↔03 有（两条 path= 点第一个）、
#    02↔04 有（`%20` 穿过 LS 没被拆坏）、01↔05 有（URL 盖过了点名钩子）；
#    06、07 与 01 **没有**（被拒的那条 URL 不该动画面）。
#    比的是"单通道差 >8/255 的像素个数"，**不是 md5**。换成这个量是因为 md5 两头都错过：
#      · 会假红：页头那条信息横幅是半透明材质，合成结果带 ±1/255 的抖动，八张照片里它的
#        R 通道在 228/229 之间随机落（01=228、02=229、05=228、06=229、07=228），
#        跟这一档送没送 URL 一点关系都没有。第一版拿 md5 当判据，正是在功能全对的一跑上
#        把 06 判成红——而它当时唯一的错就是"少了一张照片该说的话"，画面其实一模一样。
#      · 会假绿：反过来"两张 md5 不同"只说明**至少一个像素**不一样，差的全是 banner 抖动时
#        它也算不一样。那四条"该不同"的判据就可能在选中条根本没挪的一跑上白白过。
#    实测这个量把两类分得极开：真挪了选中条的是 66 197–94 044 个像素，只差 banner 抖动的是
#    **0** 个（最大幅度 1）。所以判据取 0 / >0 这一刀，门槛 8 留着一个数量级以上的余量。
#    05 那一条判据**第一版写反了**：写成"02↔05 不同"，于是它把一次成功跑判成红。
#    想钉的是"URL 说了算"，而 URL 点的是 UrlFoo、钩子点的是 OtherFoo（= 01 的兜底那一行），
#    所以"URL 赢了"的画面就是**跟 02 一样、跟 01 不一样**。实测正是 02 与 05 零可辨差异，
#    它讲的是同一件事，只是我拿它当反证了。02↔05 因此降成信息行，01↔05 才是硬判据。
print -r -- ""
print -r -- "# 窗口数核对"
typeset -a PROBLEMS
for lg in "$OUT"/*.log(N); do
  name=$(basename "$lg" .log)
  if grep -q 'title=MacMaster bounds=.*title=MacMaster bounds=' "$lg"; then
    PROBLEMS+=("$name：日志里的窗口清单有两扇 title=MacMaster——单例场景没兜住")
    continue
  fi
  if grep -q 'layer=0 title=MacMaster bounds=' "$lg"; then
    print -r -- "  ✓ $name：主窗口正好一扇"
  elif [[ $name == 08-* ]]; then
    PROBLEMS+=("08：日志里没有窗口行，这一档没数成")
  else
    PROBLEMS+=("$name：日志里没有 title=MacMaster 的窗口行")
  fi
done

print -r -- ""
print -r -- "# 留痕核对"
for pair in "01-baseline-no-url:none" "02-url-named-app:ok" "03-url-multi-first-wins:ok" \
            "04-url-space-percent20:ok" "05-url-overrides-select-hook:ok" \
            "06-url-system-path-refused:miss" "07-url-without-path-refused:nopath" \
            "08-hot-instance-receives-url:ok"; do
  name=${pair%%:*}; want=${pair##*:}
  lg="$OUT/$name.log"
  # 判留痕之前先问"这一档拍出照片了吗"：没拍出的那一档日志里只剩头部，
  # 两条拒绝留痕当然都是 0，于是 `ok`/`none` 档会**假绿**（第一遍取证时 08 就是这么
  # 拿到一个 ✓ 的——它连进程都没起来）。没出片的档由下面的 FAILED 统一报红。
  [[ -s "$OUT/$name.png" ]] || continue
  [[ -s $lg ]] || continue
  has_miss=$(grep -c '入站点名的 bundle 不在应用清单里' "$lg" || true)
  has_nopath=$(grep -c '收到的 URL 里没有可用的 path=' "$lg" || true)
  case $want in
    miss)
      if (( has_miss > 0 )); then print -r -- "  ✓ $name：有「不在应用清单里」留痕"
      else PROBLEMS+=("$name：该有「不在应用清单里」却没有——系统路径没被拒？"); fi ;;
    nopath)
      if (( has_nopath > 0 )); then print -r -- "  ✓ $name：有「没有可用的 path=」留痕"
      else PROBLEMS+=("$name：该有「没有可用的 path=」却没有"); fi ;;
    ok)
      if (( has_miss == 0 && has_nopath == 0 )); then print -r -- "  ✓ $name：两条拒绝留痕都没有（点名落进了清单）"
      else PROBLEMS+=("$name：点名没落进清单（miss=$has_miss nopath=$has_nopath），这张照片讲的不是「切到了」"); fi ;;
    none)
      if (( has_miss == 0 && has_nopath == 0 )); then print -r -- "  ✓ $name：没送 URL，自然没有留痕"
      else PROBLEMS+=("$name：这一档没送 URL 却出现留痕，说明有别的进程把 URL 投了进来"); fi ;;
  esac
done

print -r -- ""
print -r -- "# 画面交叉核对"
# md5 照样打出来：它是给人对账用的（"这两张是不是同一份"一眼能扫），只是不再当判据。
for png in "$OUT"/*.png(N); do
  print -r -- "  md5 $(md5 -q "$png")  $(basename $png)"
done
# 每对都写清"该有可辨差异"还是"该没有"。`info` 那两对只报数不判：
# 02↔05 相同才是预期（见上），02↔08 的差别是等待时长（08 多等两轮，侧栏体积徽标落值）。
typeset -a PIX_PAIRS=(
  "01-baseline-no-url|02-url-named-app|diff"
  "02-url-named-app|03-url-multi-first-wins|diff"
  "02-url-named-app|04-url-space-percent20|diff"
  "01-baseline-no-url|05-url-overrides-select-hook|diff"
  "01-baseline-no-url|06-url-system-path-refused|same"
  "01-baseline-no-url|07-url-without-path-refused|same"
  "02-url-named-app|05-url-overrides-select-hook|info"
  "02-url-named-app|08-hot-instance-receives-url|info"
)
# 比对跑在 python+PIL 上（本机有；按通道取最大值再数直方图，纯 shell 做不到不逐像素循环）。
# **跑不了就判红，不退回 md5**：退回去等于把一条会假红的判据换成一条会假绿的；
# 静默跳过更糟——这一族的价值全在"被拒的 URL 没动画面"这一条上。
pix_report=''
pix_rc=0
if ! python3 -c 'import PIL' >/dev/null 2>&1; then
  PROBLEMS+=("本机 python3 没有 PIL：像素比对没跑，这一族的画面判据不能空过")
else
  pix_report=$(python3 - "$OUT" "${PIX_PAIRS[@]}" <<'PY'
import os
import sys
from PIL import Image, ImageChops

out = sys.argv[1]
for spec in sys.argv[2:]:
    a, b, kind = spec.split('|')
    fa = os.path.join(out, a + '.png')
    fb = os.path.join(out, b + '.png')
    if not (os.path.exists(fa) and os.path.exists(fb)):
        print('\t'.join((a, b, kind, 'missing', '-')))
        continue
    ia = Image.open(fa).convert('RGB')
    ib = Image.open(fb).convert('RGB')
    if ia.size != ib.size:
        print('\t'.join((a, b, kind, 'sizediff', '%s vs %s' % (ia.size, ib.size))))
        continue
    r, g, bl = ImageChops.difference(ia, ib).split()
    hist = ImageChops.lighter(ImageChops.lighter(r, g), bl).histogram()
    print('\t'.join((a, b, kind, str(sum(hist[9:])),
                     str(max(i for i in range(256) if hist[i])))))
PY
) || pix_rc=$?
fi
# 出的行数比要对的少（python 崩了、一张图没读成），不能等于"判据过了"——补一个硬失败。
pix_lines=$(wc -l <<<"$pix_report" | tr -d ' ')
if (( pix_lines < ${#PIX_PAIRS[@]} )); then
  PROBLEMS+=("像素比对只出了 $pix_lines 行，该出 ${#PIX_PAIRS[@]} 行（python 退出码 $pix_rc）——判据没跑完就是没过")
fi
while IFS=$'\t' read -r a b kind above maxd; do
  [[ -n $a ]] || continue
  case $above in
    missing) print -r -- "  – $a ↔ $b：有一张没拍出，交给「没拍出照片」那一条报"； continue ;;
    sizediff) PROBLEMS+=("$a ↔ $b 两张尺寸不同（$maxd）：不是一扇窗口的两种状态，比对无意义"); continue ;;
  esac
  case $kind in
    diff)
      if (( above > 0 )); then print -r -- "  ✓ $a ↔ $b：可辨差异 $above 个像素（最大幅度 $maxd）"
      else PROBLEMS+=("$a ↔ $b：可辨差异 0 个像素（最大幅度 $maxd）——URL 没把选中条挪动"); fi ;;
    same)
      if (( above == 0 )); then print -r -- "  ✓ $a ↔ $b：可辨差异 0 个像素（最大幅度 $maxd，被拒的 URL 没动画面）"
      else PROBLEMS+=("$a ↔ $b：可辨差异 $above 个像素（最大幅度 $maxd）——被拒的那条 URL 改变了画面，它不该动任何东西"); fi ;;
    info)
      print -r -- "  ℹ $a ↔ $b：可辨差异 $above 个像素（最大幅度 $maxd，不作判据，理由见脚本头 ③）" ;;
  esac
done <<< "$pix_report"

for p in "${PROBLEMS[@]}"; do print -u2 -- "⚠ $p"; done

if (( ${#PROBLEMS[@]} > 0 )); then
  print -u2 -- "✗ 核对没过，这一族不算取证完成"
  exit 1
fi

if (( ${#FAILED[@]} > 0 )); then
  print -u2 -- "✗ 这些档位没拍出照片：${FAILED[*]}"
  print -r -- "→ $OUT"
  exit 1
fi

print -r -- "→ $OUT（$APPEARANCE）"
