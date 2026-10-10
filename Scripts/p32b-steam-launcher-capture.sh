#!/bin/zsh
# P32b「认出启动器」取证：这一族拍的是**实现之后**的四件事，一张都不必重复 P32a 的现状。
#
#   1) 详情面板的「启动器」行：识别成立时说什么、不成立时是不是真的一个字不说（对照组）；
#   2) 反向那一条：卸载 **Steam 本体**时，`Application Support/Steam` 那一行有没有点名 steamapps；
#   3) 敏感度钩子 `MM_UNINSTALL_SENSITIVITY`（P32a §5.5 承认的取证缺口）：
#      增强/深度两档到底到不到得了 `steamapps/common/<游戏>`——以前只有代码推导，现在有照片；
#      （07/08/09 这三档）
#   4) 钩子写错值：回落 strict 且 stderr 留痕，界面上「敏感度」选择器跟着显示"严格"。
#
# 夹具与 P32a 同一份（`Scripts/p32-steam-fixture.sh`），所以两族的照片可以直接对读：
# 那一轮的 01 说"画面上没有一处说它是启动器"，这一轮的 01 必须有。
#
# 与 P32a 一样的三条底线：
#   · **不启动任何 bundle**（它们是 shell 脚本，`open` 一次会真的去叫 `steam://`）；
#   · 假 home 只认 /tmp（`MM_UNINSTALL_CONFIRM_FIXTURE_HOME`），用户的应用一个都不卷进来；
#   · 哨兵是字节数：`# sentinel: 本体 …` 与 `# sentinel: 本体之外的游戏目录 …`。
#     第二个数在 07/08/09 这三档里的读法变了：P32a 要证明"它没出现在画面上"，
#     这一轮要证明的是"放宽到深度档它**还是**没出现在画面上"——所以那三档的日志里
#     额外写一行 `# 应否出现: 游戏目录不作为残留行`，判据来自
#     `ResidualNameMatcher` 的包含方向（文件名包含应用名，不是路径包含），
#     而照片负责证伪：只要游戏目录真成了残留行，这行注释当场就是错的。
#
#   ./Scripts/p32b-steam-launcher-capture.sh <app 路径> <输出目录> [light|dark] [宽x高]
#   ./Scripts/p32b-steam-launcher-capture.sh /tmp/mm-app-p32b/MacMaster.app docs/verification/p32b-steam
#   ONLY=06 ./Scripts/p32b-steam-launcher-capture.sh …        只重拍 06 那一档
#   FIX=/tmp/macmaster-steam-fixture.XXXX ./Scripts/p32b-steam-launcher-capture.sh … 复用现成夹具
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SIZE=${4:-}
FIX=${FIX:-$(./Scripts/p32-steam-fixture.sh)}
for required in Applications/SteamGame.app Applications/SteamRunSh.app \
                Applications/SteamNoId.app Applications/PlainTool.app Applications/Steam.app \
                Applications/SteamTwoEntries.app; do
  [[ -e "$FIX/$required" ]] || { print -u2 -- "✗ 夹具不完整：$FIX 缺 $required（先跑 ./Scripts/p32-steam-fixture.sh）"; exit 2; }
done
[[ -f "$FIX/Library/Application Support/Steam/steamapps/common/SteamGame/GameData.bin" ]] || {
  print -u2 -- "✗ 夹具缺游戏本体那份文件，'增强/深度到不到得了它'就没得对照了：$FIX"; exit 2; }
[[ -d "$FIX/Library/Application Support/Steam/steamapps" ]] || {
  print -u2 -- "✗ 夹具的 Steam 目录里缺 steamapps，行内提醒（05）就没得触发：$FIX"; exit 2; }

# 归因头 + 内容指纹门禁（配方见 mm-provenance.sh）：不等就一张都不出。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p32b -s /tmp/mm-scratch-p32b 重新构建再取证。"
  exit 4
fi

SETTLE=${SETTLE:-10}
mkdir -p "$OUT"

wants() { [[ -z ${ONLY:-} || $1 == ${ONLY}* ]] }

bundle_bytes() {
  local dir="$FIX/$1"
  local n
  n=$(find "$dir" -type f -exec stat -f %z {} + | awk '{t+=$1} END {print t+0}')
  print -r -- "$n $(find "$dir" -type f | wc -l | tr -d ' ')"
}

GAME_BYTES=$(bundle_bytes "Library/Application Support/Steam/steamapps/common/SteamGame" | awk '{print $1}')

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
# shot <文件名> <应用目录名> <确认档> [窗口宽x高] <敏感度档位>
# 确认档传空 = `none`（只拍列表与详情）。敏感度传空 = 不喂钩子（生产路径，默认严格）。
shot() {
  local name=$1 app=$2 mode=$3 size=${4:-$SIZE} sens=$5
  if ! wants $name; then return 0; fi
  local log="$OUT/$name.log"
  local bytes
  bytes=$(bundle_bytes "Applications/$app.app")
  print -r -- "# p32b-steam-launcher-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP  fixture=$FIX" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=uninstaller ${size:+MM_WINDOW_SIZE=$size }MM_UNINSTALL_SELECT=$app ${mode:+MM_UNINSTALL_CONFIRM_MODE=$mode} ${sens:+MM_UNINSTALL_SENSITIVITY=$sens}" >>"$log"
  print -r -- "# sentinel: 本体 Applications/$app.app = ${bytes% *} B / ${bytes#* } 个文件（find -type f 现算，口径同界面「本体」）" >>"$log"
  print -r -- "# sentinel: 本体之外的游戏目录 steamapps/common/SteamGame = ${GAME_BYTES} B" >>"$log"
  print -r -- "# 应否出现: 游戏目录不作为残留行（判据=包含方向是「文件名包含应用名」，不是路径包含）" >>"$log"
  print -r -- "# 清单应含夹具根 Applications 下的六个 .app（PlainTool/Steam/SteamGame/SteamNoId/SteamRunSh/SteamTwoEntries），不应含 Steam Shortcuts/DeepShortcut：应用根非递归" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=uninstaller \
      ${size:+MM_WINDOW_SIZE="$size"} \
      ${sens:+MM_UNINSTALL_SENSITIVITY="$sens"} \
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
  # 拍完自查（与 P32a 同一条理由）：这一族要的是"界面怎么说"，不是"删完之后世界什么样"。
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

# 01 主证：可执行文件与 bundle 同名那一份。要看「启动器」这一行、列表行那枚 chip、
#    标题旁的徽章**同时**成立，且判定依据里能认出脚本名与 appid。
shot 01-steamgame-launcher-row SteamGame "" || FAILED_SHOTS+=(01-steamgame-launcher-row)
# 02 脚本名字就叫 `run.sh` 的那一份（Pearcleaner 写死的那个名字，夹具里 plist 也这么写）：
#    它仍然走第一条入口，判据是"名字不影响识别"。第二条入口由 05 那一份专门负责。
shot 02-runsh-launcher-row SteamRunSh "" || FAILED_SHOTS+=(02-runsh-launcher-row)
# 03 对照组：本体真有 8 MiB 的普通应用。这一张的判据是**画面上没有**「启动器」行、
#    没有那枚 chip、没有那枚徽章——不成立时一个字都不说。
shot 03-plain-tool-control PlainTool "" || FAILED_SHOTS+=(03-plain-tool-control)
# 04 无包标识那一份：识别只看脚本，不看包名——它仍然该有「启动器」行。
shot 04-noid-launcher-row SteamNoId "" || FAILED_SHOTS+=(04-noid-launcher-row)
# 05 两条入口同时存在、只有第二条成立的那一份：`CFBundleExecutable` 指的 `Launcher`
#    是两段命令（按合同不成立），同一目录里的 `run.sh` 才是"恰好一行"那一个。
#    「启动器」行的脚本名必须是 `run.sh`——它证的正是"两条入口都试"这句取舍。
shot 05-two-entries-fallback SteamTwoEntries "" || FAILED_SHOTS+=(05-two-entries-fallback)
# 06 反向那一条（P32b 优先级最高的一条）：卸载 **Steam 本体**，看残留清单里
#    `Application Support/Steam` 那一行的说明有没有点名 steamapps。窗口拉高才看得见那一段。
shot 06-steam-self-caveat Steam "" 1400x1000 || FAILED_SHOTS+=(06-steam-self-caveat)
# 07/08/09 敏感度两档 + 本体（P32a §5.5 的取证缺口）：
#    增强、深度各自把 `steamapps/common/SteamGame` 收到哪儿了——按代码推导三档都收不到，
#    照片要么证实这条推导，要么当场推翻它。
shot 07-enhanced-steamgame-residuals SteamGame "" 1400x1000 enhanced || FAILED_SHOTS+=(07-enhanced-steamgame-residuals)
shot 08-deep-steamgame-residuals SteamGame "" 1400x1000 deep || FAILED_SHOTS+=(08-deep-steamgame-residuals)
shot 09-deep-steam-self-residuals Steam "" 1400x1000 deep || FAILED_SHOTS+=(09-deep-steam-self-residuals)
# 10 钩子写错值：应当回落严格档，且 stderr 留一行"含非法取值…已回落 strict 档"。
#    照片负责证"选择器上真的是严格"，日志负责证"留痕写了"。
shot 10-bad-hook-value-fallback SteamGame "" "" enhance || FAILED_SHOTS+=(10-bad-hook-value-fallback)
# 11 窄窗：窗口硬最小宽度 1000 时，残留行那句行内提醒会不会被中间省略吃掉。
#    P25/P26 那一族的教训就是"截断把要紧的话藏起来"，所以这一档专门拍。
#    高度必须是 1000 而不是 800：800 那一版实跑过，"将一并移除的残留"整段落在折叠线以下
#    （画面最后一行是「所在文件夹」＋那段依据），于是它只证到了依据会换行、没证到提醒会不会被截。
shot 11-steam-self-narrow-window Steam "" 1000x1000 || FAILED_SHOTS+=(11-steam-self-narrow-window)

if (( ${#FAILED_SHOTS[@]} > 0 )); then
  print -u2 -- "✗ 这些档位没拍出照片：${FAILED_SHOTS[*]}"
  print -r -- "→ $OUT"
  exit 1
fi

print -r -- "→ $OUT"
print -r -- "夹具留在 $FIX（本族不启动任何 bundle，也没有进程要收尾；核对完照片就可以删）"
