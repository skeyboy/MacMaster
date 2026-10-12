#!/bin/zsh
# P33b「归属复核」取证：这一族拍的是 B 档落地之后，**同一个绝对路径在两个应用的清单里
# 得到相反结论**这件事在界面上长什么样。复核有两条线索（这一项本身归别人 / 上层目录归别人），
# 照片必须把两条都拍到，而且要拍出它们各自救下哪一行——只做祖先那一层的话，
# `docs/analysis/uninstaller-deep-residual-scope.md` §4 那一幕一个字都不会变。
#
# 五件事，一张都不重复探针已经能打的东西（探针打的是引擎返值，照片打的是界面怎么说）：
#   1) 01 主证：Fork 的清单里那两条只有弱证据的行——行还在、徽章变成「谨慎」、勾选框是空的、
#      行下方那句话点名主人。两条各走一条线索：
#      `Caches/IDEFoo/AssetsFork` 走**第一条**（AssetsFork 对它有更硬的「名称与包名对应」，
#      而它的上层同时归 IDEFoo——两条都成立时提醒只说更近的那条，不绕到祖先），
#      `Caches/IDEFoo/ts-go-fork-embedded` 走**第二条**（谁都对这一项本身给不出硬证据，
#      只有上层目录归 IDEFoo——这一条的形状与 P33a §3 本机实测那三条一致）。
#      同一张表里另外两行仍默认勾选：一条硬证据（`Caches/Fork`），
#      一条是"别的应用对它也只有弱证据"的 `Caches/ForkExtras`（弱对弱不构成主张，不降）。
#      为什么这一帧只有两条降级行：见 `Scripts/p33b-nesting-fixture.sh` 里"能装进画面的行数由屏幕决定"
#      那一段；被砍掉的同层无嵌套形状由 p32b 交叉验证那一档在原图上拍。
#   2) 02 窄窗：1000 pt 硬最小宽度下，行下方那句提醒会不会像 P25/P26 那一族一样被中间省略吃掉。
#      它走的是 `caveat` 这条多行通道（`MMUninstaller.swift:1956-1963`），
#      照片负责证这句话——不成立时一个字都不要说。
#   3) 03 主人那一份：切到 IDEFoo，它自己的行一条都没因为"我们替 Fork 复核"而少勾。
#   4) 04 边界：切到 AssetsFork，`Caches/IDEFoo/AssetsFork` 这条**同路径**的行证据是硬的
#      （「名称与包名对应」），于是不降、仍勾选。
#      01 与 04 合起来才是这条判据的完整形状：降级挂在证据强度上，不挂在路径上。
#   5) 05 反向对照：严格档下 Fork 只有一行（弱证据按构造到不了这一档），
#      06 深度档与 01 逐行相同——复核不跟着敏感度松紧。
#
# 预期行**不在本脚本里**：开拍前先跑一次
#   FIX=$FIX OUT=$OUT ./Scripts/p33b-ownership-review-probe.sh
# 把整张表落成 $OUT/fixture-rows.log，每一档的 `.log` 只指向它那两节。
# 理由：照片的预期行如果由我照代码推导写死，照片拍到什么都能自圆其说；
# 由同一棵树上的真扫描器返值，照片与它不符才是照片（或夹具）错。
#
# 三条底线沿用 P32b 那一族：
#   · **不启动任何 bundle**，也不用合成点击（原生按钮点不进去，勾选状态一律走默认值那条路）；
#   · 假 home 只认 /tmp（`MM_UNINSTALL_CONFIRM_FIXTURE_HOME`），用户的应用一个都不卷进来；
#   · 只 kill 自己启动的 pid；哨兵是字节数，拍完自查本体是否仍在磁盘。
#
#   ./Scripts/p33b-nesting-capture.sh <app 路径> <输出目录> [light|dark]
#   ./Scripts/p33b-nesting-capture.sh /tmp/mm-app-p33b/MacMaster.app docs/verification/p33b-nesting
#   ONLY=02 ./Scripts/p33b-nesting-capture.sh …        只重拍 02 那一档
#   FIX=/tmp/macmaster-p33b-nesting.XXXX ./Scripts/p33b-nesting-capture.sh …  复用现成夹具
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
FIX=${FIX:-$(./Scripts/p33b-nesting-fixture.sh)}
for required in Fork IDEFoo AssetsFork; do
  [[ -e "$FIX/Applications/$required.app" ]] || {
    print -u2 -- "✗ 夹具不完整：$FIX 缺 $required.app（先跑 ./Scripts/p33b-nesting-fixture.sh）"; exit 2; }
done
for required in "Caches/IDEFoo/AssetsFork" "Caches/ForkExtras" "Caches/IDEFoo/ts-go-fork-embedded"; do
  [[ -d "$FIX/Library/$required" ]] || {
    print -u2 -- "✗ 夹具缺 Library/$required——01 的主证行与 04 的边界行都没了：$FIX"; exit 2; }
done

# 归因头 + 内容指纹门禁（配方见 mm-provenance.sh）：不等就一张都不出。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p33b -s /tmp/mm-scratch-p33b 重新构建再取证。"
  exit 4
fi

SETTLE=${SETTLE:-10}
mkdir -p "$OUT"
wants() { [[ -z ${ONLY:-} || $1 == ${ONLY}* ]] }

# 预期行来源：真扫描器在同一棵夹具树上的返值（三档 × 三份应用逐行）。
# 已经现成就复用（`ONLY=02` 单独重拍时不必重编探针），但只认同一棵夹具树跑出来的那份：
# 头部里换过 FIX 之后旧表就不作数，所以这里比对表头那一行。
if [[ -s "$OUT/fixture-rows.log" ]] && ! grep -q "^# 夹具模式：home=$FIX\$" "$OUT/fixture-rows.log"; then
  print -u2 -- "⚠ $OUT/fixture-rows.log 是另一棵夹具树跑出来的（表头的 home 不等于本轮 FIX），重跑探针覆盖它"
  rm -f "$OUT/fixture-rows.log"
fi
if [[ ! -s "$OUT/fixture-rows.log" ]]; then
  FIX="$FIX" OUT="$OUT" ./Scripts/p33b-ownership-review-probe.sh >/dev/null
fi
[[ -s "$OUT/fixture-rows.log" ]] || { print -u2 -- "✗ 探针没写出 $OUT/fixture-rows.log"; exit 3; }

dir_bytes() {
  local n
  n=$(find "$1" -type f -exec stat -f %z {} + 2>/dev/null | awk '{t+=$1} END {print t+0}')
  print -r -- "${n:-0}"
}

# 界面那一列的数走 st_blocks×512（`ResidualScanner.swift:317-342`），夹具一律真实字节写入，
# 所以这里 st_size 合计与那一列应当相等；不等就是夹具被写成了稀疏文件。
ASSETS_IN_IDEOFO=$(dir_bytes "$FIX/Library/Caches/IDEFoo/AssetsFork")
TS_GO_FORK=$(dir_bytes "$FIX/Library/Caches/IDEFoo/ts-go-fork-embedded")
FORK_EXTRAS=$(dir_bytes "$FIX/Library/Caches/ForkExtras")
FORK_OWN=$(dir_bytes "$FIX/Library/Caches/Fork")
IDEFO_OWN=$(dir_bytes "$FIX/Library/Caches/IDEFoo")

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
# shot <文件名> <选中的应用> <敏感度档位> [窗口宽x高]
# 档位传空 = 不喂 `MM_UNINSTALL_SENSITIVITY`（生产路径，默认严格）。确认面板一律不弹（none）：
# 这一族要的是列表与详情里的残留行，面板会盖住它们。
shot() {
  local name=$1 app=$2 sens=$3 size=${4:-1400x1000}
  if ! wants $name; then return 0; fi
  local log="$OUT/$name.log"
  local tier=${sens:-strict}
  print -r -- "# p33b-nesting-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP  fixture=$FIX" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=uninstaller MM_WINDOW_SIZE=$size MM_UNINSTALL_SELECT=$app MM_UNINSTALL_CONFIRM_MODE=none ${sens:+MM_UNINSTALL_SENSITIVITY=$sens}" >>"$log"
  print -r -- "# 敏感度：${sens:-（未设钩子，走生产默认严格档）}" >>"$log"
  print -r -- "# 预期行：见 $OUT/fixture-rows.log 的「## $tier 档 / ### $app」一节（开拍前由探针在同一棵夹具树上现跑生成）" >>"$log"
  print -r -- "# sentinel: Caches/IDEFoo/AssetsFork = ${ASSETS_IN_IDEOFO} B" >>"$log"
  print -r -- "# sentinel: Caches/IDEFoo/ts-go-fork-embedded = ${TS_GO_FORK} B" >>"$log"
  print -r -- "# sentinel: Caches/ForkExtras = ${FORK_EXTRAS} B" >>"$log"
  print -r -- "# sentinel: Caches/Fork = ${FORK_OWN} B" >>"$log"
  print -r -- "# sentinel: Caches/IDEFoo（含上面两条嵌套的）= ${IDEFO_OWN} B" >>"$log"
  print -r -- "# 清单应恰为夹具根 Applications 下三份（AssetsFork/Fork/IDEFoo）；应用根由钩子改成 \$home/Applications" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=uninstaller \
      MM_WINDOW_SIZE="$size" \
      ${sens:+MM_UNINSTALL_SENSITIVITY="$sens"} \
      MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$FIX" \
      MM_UNINSTALL_CONFIRM_MODE=none \
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
  local post="三份本体仍在磁盘"
  for a in Fork IDEFoo AssetsFork; do
    [[ -e "$FIX/Applications/$a.app" ]] || post="$post；$a 已经不在了（这一档拍到的是删除之后的状态，不作数）"
  done
  print -r -- "# post-shot: $post" >>"$log"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  for a in Fork IDEFoo AssetsFork; do
    [[ -e "$FIX/Applications/$a.app" ]] || {
      print -u2 -- "✗ $name：拍完之后 $a.app 已不在磁盘上，照片记的是删除之后（重拍这一档前先重建夹具）"; return 1; }
  done
  print -r -- "✅ $name windowid=$wid"
}

# 01 主证。高度按实测上限喂（这台机 1920×1080：喂 1250 被系统夹到 1050，`sips` 量的，
# 所以这里写实际能拿到的那个数，日志里的 `# env:` 与照片像素才对得上；
# 想复现那条夹取，把尺寸改成 1250 重跑 `ONLY=01` 再看像素）：
# 两条降级行连同各自行下方那句提醒都要在画面里，其中「上层目录归 IDEFoo」那一条排在最后。
shot 01-fork-nested-downgraded Fork enhanced 1400x1050 || FAILED_SHOTS+=(01-fork-nested-downgraded)
# 02 窄窗：宽度 1000 pt 是硬最小值（判据只看宽度），高度顶到实测上限 1050，
# 好让提醒换行之后的第二行也落在画面里。判据是那两句都**不带省略号**——
# P25/P26 那一族的教训就是截断把要紧的话藏起来。副标题那一行按设计是中间省略的
# （两条通道：副标题串在 `MMUninstaller.swift:1938`、省略由 `MMDesign.swift:807` 的
# `MMItemRow` 施加；提醒串在 `MMUninstaller.swift:1956`，走 `fixedSize` 换行），
# 02 要分清的就是这两条通道的差别。
shot 02-fork-narrow-window Fork enhanced 1000x1050 || FAILED_SHOTS+=(02-fork-narrow-window)
# 03 主人的清单：IDEFoo 自己的行不因"我们替 Fork 复核"而少勾。
shot 03-owner-app-unchanged IDEFoo enhanced || FAILED_SHOTS+=(03-owner-app-unchanged)
# 04 边界：同一条路径在 AssetsFork 名下是硬证据，于是仍勾选。
shot 04-assetsfork-hard-evidence AssetsFork enhanced || FAILED_SHOTS+=(04-assetsfork-hard-evidence)
# 05 严格档对照：不喂敏感度钩子（生产默认档），Fork 只有一行硬证据。
shot 05-fork-strict-control Fork "" || FAILED_SHOTS+=(05-fork-strict-control)
# 06 深度档：与 01 逐行相同——复核不跟着敏感度松紧（`reviewed` 里没有档位判断）。
# 窗口与 01 同尺寸，两帧才能逐行对。
shot 06-fork-deep-tier Fork deep 1400x1050 || FAILED_SHOTS+=(06-fork-deep-tier)

if (( ${#FAILED_SHOTS[@]} > 0 )); then
  print -u2 -- "✗ 这些档位没拍出照片：${FAILED_SHOTS[*]}"
  print -r -- "→ $OUT"
  exit 1
fi

print -r -- "→ $OUT"
print -r -- "夹具留在 $FIX（本族不启动任何 bundle，也没有进程要收尾；核对完照片就可以删）"
