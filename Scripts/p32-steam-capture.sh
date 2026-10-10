#!/bin/zsh
# P32a「Steam 启动器型 bundle 现在显示成什么」取证：这一族拍的是**改动之前**的现状，
# 所以它一张都不需要"实现后的样子"——界面上有没有那一档说法，就是这一族的结论本身。
#
# 为什么全部靠夹具：本机没有 Steam（`/Applications/Steam.app` 与
# `~/Library/Application Support/Steam` 都不在），没有任何一档能像 P31 的 07 那样
# 点名"本机此刻真在跑的应用"来对照。夹具的形态不是我们想的，是参考项目认定的那三种
# （可执行文件同名 / 可执行文件叫 `run.sh` / 整份 plist 没有包标识），配方写在
# `Scripts/p32-steam-fixture.sh` 顶上。
#
# 与 P31 那一族的三条差别：
#   1) 这里**不启动任何 bundle**。它们是 shell 脚本，`open` 一次就会真的去叫 `steam://`，
#      而本机没有 Steam 只会弹一个报错框——那一框不是我们要的证据。所以本脚本没有
#      进程生命周期要管，也就没有 pid 哨兵，取而代之的是**字节数哨兵**（见下）。
#   2) 假 home 走的是同一条钩子（`MM_UNINSTALL_CONFIRM_FIXTURE_HOME`，只认 /tmp），
#      它同时把应用根换成 `$home/Applications`、把残留扫描换成 `$home/Library`
#      （`MMUninstaller.swift:229-236` 那三行 factory），所以照片里"清单三行 + 残留两处"
#      都是这台机器上不存在的东西，用户的应用一个都不会被卷进来。
#   3) 哨兵是字节数，不是 pid：日志里每一档都写两行——
#      `# sentinel: 本体 <目录> = <N> B / <M> 个文件`（照片「本体」那一行必须与 N 一致），
#      `# sentinel: 本体之外的游戏目录 = <G> B`（照片的「残留」「合计」里**不该**出现这个量级）。
#      第二个数是"画面里没有的那个量"，它只能靠独立计算得到，正是要核对的那件事。
#      字节口径也写在明处：这里算的是 `st_size` 之和，与界面「本体」同源
#      （`FileTreeWalker.swift:65`）；残留那一列另走 `st_blocks × 512`
#      （`ResidualScanner.swift:317-342`），所以照片上残留的数会比这里的表观值小——
#      这是两个口径的差，不是漏算，读照片时别把它当矛盾。
#      还有第三条哨兵在**拍完之后**：`# post-shot: 本体仍在磁盘`。它管的是
#      "自动弹出的确认面板一次回车就能按掉"这件事（本族第一次实跑就折在这里，
#      04 那张拍到的是删除之后的状态）——这一族要的是"界面怎么说"，
#      不是"删完之后世界什么样"，所以本体被按掉了的那一张一律不作数。
#
# 全程零点击：选中哪一行 = `MM_UNINSTALL_SELECT=<bundleName>`，面板弹不弹 =
# `MM_UNINSTALL_CONFIRM_MODE`（`none` 只拍列表与详情；`withresiduals` 连残留一起弹，
# 这一档才答得出"确认框会不会把它当真应用删"）。假档位一律不喂合成值——
# 这一族要证明的是"界面拿磁盘上那份文件说了什么真话"。
#
#   ./Scripts/p32-steam-capture.sh <app 路径> <输出目录> [light|dark] [宽x高]
#   ./Scripts/p32-steam-capture.sh /tmp/mm-app-p32/MacMaster.app docs/verification/p32-steam
#   ONLY=03 ./Scripts/p32-steam-capture.sh …                只重拍 03 那一档
#   FIX=/tmp/macmaster-steam-fixture.XXXX ./Scripts/p32-steam-capture.sh … 复用现成夹具
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SIZE=${4:-}
FIX=${FIX:-$(./Scripts/p32-steam-fixture.sh)}
for required in Applications/SteamGame.app Applications/SteamRunSh.app \
                Applications/SteamNoId.app Applications/PlainTool.app Applications/Steam.app \
                "Applications/Steam Shortcuts/DeepShortcut.app"; do
  [[ -e "$FIX/$required" ]] || { print -u2 -- "✗ 夹具不完整：$FIX 缺 $required（先跑 ./Scripts/p32-steam-fixture.sh）"; exit 2; }
done
[[ -f "$FIX/Library/Application Support/Steam/steamapps/common/SteamGame/GameData.bin" ]] || {
  print -u2 -- "✗ 夹具缺游戏本体那份文件，'本体有多大'这件事就没得对照了：$FIX"; exit 2; }

# 归因头 + 内容指纹门禁（配方见 mm-provenance.sh）：不等就一张都不出。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p32 -s /tmp/mm-scratch-p32 重新构建再取证。"
  exit 4
fi

SETTLE=${SETTLE:-10}
mkdir -p "$OUT"

wants() { [[ -z ${ONLY:-} || $1 == ${ONLY}* ]] }

# bundle_bytes <夹具内相对目录>：表观字节与文件数，口径同界面「本体」那一行。
# 用 find -type f 而不是 du：du 报的是块数（还有目录项自己那一份），
# 与 `FileTreeWalker` 累加 `st_size` 的算法本来就是两个数，拿它对照片等于核错东西。
bundle_bytes() {
  local dir="$FIX/$1"
  local n
  n=$(find "$dir" -type f -exec stat -f %z {} + | awk '{t+=$1} END {print t+0}')
  print -r -- "$n $(find "$dir" -type f | wc -l | tr -d ' ')"
}

GAME_BYTES=$(bundle_bytes "Library/Application Support/Steam/steamapps/common/SteamGame" | awk '{print $1}')

# main_window_id / shot：与 p31-running-capture.sh 同一套（理由也写在那一份里：
# 单次查询会被 swift 脚本模式自己失败一次骗成"那一档没有窗口"，所以要重试；
# 挑窗口要"标题正好是 MacMaster 的普通层窗口且正好一扇"，绝不退回 head -1）。
main_window_id() {
  local pid=$1 log=$2 all wid n
  all=$(swift Scripts/window-ids.swift --pid "$pid" 2>>"$log" || true)
  print -r -- "# windows(pid=$pid): ${all//$'\n'/ | }" >>"$log"
  n=$(printf '%s\n' "$all" | grep -c 'layer=0 title=MacMaster bounds=' || true)
  [[ $n == 1 ]] || return 1
  wid=$(printf '%s\n' "$all" | sed -n 's/^windowid=\([0-9]*\) .*layer=0 title=MacMaster bounds=.*/\1/p')
  [[ -n $wid ]] || return 1
  print -r -- "$wid"
}

typeset -a FAILED_SHOTS
# shot <文件名> <应用目录名> <确认档> [窗口宽x高]：确认档传空 = 用 `none`（只拍页面）。
# 第 4 个参数是**这一档自己的**窗口尺寸，优先于全局 SIZE：详情面板要拍到"将一并移除的残留"
# 那一段（它在 652 高的默认窗口里落在折叠线以下），只能把那一档拉高，
# 而不是把整族都拉高——别的档位拍的就是默认尺寸下的样子。
shot() {
  local name=$1 app=$2 mode=$3 size=${4:-$SIZE}
  if ! wants $name; then return 0; fi
  local log="$OUT/$name.log"
  local bytes
  bytes=$(bundle_bytes "Applications/$app.app")
  print -r -- "# p32-steam-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP  fixture=$FIX" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=uninstaller ${size:+MM_WINDOW_SIZE=$size }MM_UNINSTALL_SELECT=$app ${mode:+MM_UNINSTALL_CONFIRM_MODE=$mode}" >>"$log"
  print -r -- "# sentinel: 本体 Applications/$app.app = ${bytes% *} B / ${bytes#* } 个文件（find -type f 现算，口径同界面「本体」）" >>"$log"
  print -r -- "# sentinel: 本体之外的游戏目录 steamapps/common/SteamGame = ${GAME_BYTES} B —— 照片的「残留」「合计」里不该出现这个量级" >>"$log"
  print -r -- "# 清单应含夹具根 Applications 下的六个 .app（PlainTool/Steam/SteamGame/SteamNoId/SteamRunSh/SteamTwoEntries），不应含 Steam Shortcuts/DeepShortcut：应用根非递归" >>"$log"
  print -r -- "# 注：SteamTwoEntries 是 P32b 才加进夹具的第六份，归档在 docs/verification/p32-steam 的那八张只拍到五行——这一行说的是当前夹具的形状。" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=uninstaller \
      ${size:+MM_WINDOW_SIZE="$size"} \
      MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$FIX" \
      MM_UNINSTALL_CONFIRM_MODE="${mode:-none}" \
      MM_UNINSTALL_SELECT="$app" "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  local pid=$!
  sleep "$SETTLE"
  local wid
  for i in {1..5}; do
    wid=$(main_window_id "$pid" "$log" || true)
    [[ -n $wid ]] && break
    sleep 3
  done
  if [[ -z "$wid" ]]; then
    print -u2 -- "⚠ $name：pid=$pid 反复查了 5 次，标题为 MacMaster 的主窗口不是正好一扇（清单见 $log 的 # windows 行）"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  # 拍完自查：那一档要拍的是"面板打开、还没动手"，而面板里的 prominent 按钮一次回车就能按掉
  # （本族第一次实跑，04 那张拍到的就是删除之后的状态：列表少一行 + 一条「已卸载 2 项 · 532 KB」的
  #  toast，而夹具目录里 `Applications/SteamGame.app` 当场没了）。这一档的哨兵因此不是"画面上有字"，
  # 而是"我们还没有真的删过东西"——本体不在磁盘上了，这张照片说的就是另一件事，不作数。
  # 只查我们自己夹具里的那一个目录，不查用户的东西。
  local post="本体仍在磁盘"
  if [[ ! -e "$FIX/Applications/$app.app" ]]; then
    post="本体已经不在了（这一档拍到的是删除之后的状态，不作数）"
  fi
  print -r -- "# post-shot: $post" >>"$log"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  if [[ ! -e "$FIX/Applications/$app.app" ]]; then
    print -u2 -- "✗ $name：拍完之后 $app 已经不在磁盘上，照片记的是删除之后（重拍这一档前先重建夹具）"
    return 1
  fi
  print -r -- "✅ $name windowid=$wid 本体=${bytes% *} B"
}

# 01 现状主证：列表四行 + 详情。要看的是「本体 593 B」「来源 无法判定」「运行状态 未检测到」
#    这三件事同时成立，而画面上没有任何一处说它是个启动器。
shot 01-steamgame-list-detail SteamGame "" || FAILED_SHOTS+=(01-steamgame-list-detail)
# 02 出货就没有包标识的那一份（Mole 在两处注释过这个形态）：看「包名」那一行空着、
#    残留少了包名这条证据之后还剩什么。
shot 02-steam-noid-detail SteamNoId "" || FAILED_SHOTS+=(02-steam-noid-detail)
# 03 可执行文件叫 run.sh 的那一份（Pearcleaner `AppPathsFetch.swift:447-463` 写死的那个名字）：
#    「可执行文件」那一行现在只是把 plist 里的字符串抄出来，没人拿它当识别依据。
shot 03-steam-runsh-detail SteamRunSh "" || FAILED_SHOTS+=(03-steam-runsh-detail)
# 04 确认面板（连残留一起）：这一档答的是"会不会把它当真应用删"——
#    面板里的「合计」= 本体 + 勾选的残留，而游戏本体那 24 MiB（真机是几十 GB）
#    既不在清单里、也不在任何一句提醒里。
shot 04-steamgame-confirm-with-residuals SteamGame withresiduals || FAILED_SHOTS+=(04-steamgame-confirm-with-residuals)
# 05 无包标识那一份的确认面板：证据面更窄时，面板给出的东西差多少。
shot 05-steam-noid-confirm-with-residuals SteamNoId withresiduals || FAILED_SHOTS+=(05-steam-noid-confirm-with-residuals)
# 06 对照组：普通 bundle 的详情。它和 01 是同一屏版式，唯一差别是本体真有 8 MiB——
#    两张放在一起才说得出"同一列数字，一个是全部、一个是启动器的那点零头"。
shot 06-plain-tool-control-detail PlainTool "" || FAILED_SHOTS+=(06-plain-tool-control-detail)
# 07 详情面板下半段：「将一并移除的残留」那一段在默认 652 高的窗口里落在折叠线以下，
#    而这一族的结论恰好要回答"残留清单里有哪几条、各按什么证据收的"。
#    所以这一档把窗口拉到 1400×1000 再拍一次同一个选中项——不是换一档说法，是换一屏高度。
shot 07-steamgame-residual-list SteamGame "" 1400x1000 || FAILED_SHOTS+=(07-steamgame-residual-list)
# 08 启动器**自己**（`Steam.app`，包名 `com.valvesoftware.Steam`）：同样拉高窗口看残留清单。
#    这一档要拍的不是"大小说错了"，而是相反方向的那件事——
#    `~/Library/Application Support/Steam` 正好是它的同名直接子项，严格档就该收它，
#    而真机上那一个目录里装着 `steamapps/common/` 下**所有已装游戏**。
#    照片里那一条的大小（夹具 24 MiB 多一点）就是"我们端出来的到底有多大"。
shot 08-steam-launcher-residual-list Steam "" 1400x1000 || FAILED_SHOTS+=(08-steam-launcher-residual-list)

if (( ${#FAILED_SHOTS[@]} > 0 )); then
  print -u2 -- "✗ 这些档位没拍出照片：${FAILED_SHOTS[*]}"
  print -r -- "→ $OUT"
  exit 1
fi

print -r -- "→ $OUT"
print -r -- "夹具留在 $FIX（本脚本不启动任何 bundle，也没有进程要收尾；核对完照片就可以删）"
