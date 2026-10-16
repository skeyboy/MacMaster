#!/bin/zsh
# P49 取证：一块真挂上的镜像卷，把"外接卷"这一族从合成快照升级成这台机器的读数。
#
# 三档事实 × 挂载/卸载两态 = 六张照片，外加一档时序对照，成对给判据：
#   01/02 卸载页：`/Volumes/MMVolumeP49/Applications/AaaP49VolumeFixture.app` 在不在应用清单里。
#         这一对补的是 `uninstally-adoption.md` §3「两件没做的」第②件——
#         P46c 当时判「本机没有第二块可挂载的非启动卷」，验收那句"实机截图看它出现在列表里"没跑成。
#   03/04 磁盘页：页头那枚「这台机器还有 1 卷可以切换分析」的真读正分支。
#         `Scripts/p35b-volumes-capture.sh` 的 02 那一档拍的是同一句话，但它是
#         `MM_VOLUME_FIXTURE=two` 的合成快照，脚本头自己写着「合成值只证明界面会写字，
#         不证明这台机器有两块盘」——03 这一张不需要那半句免责声明。
#   05/06 概览页：页脚那句「N 个卷」跟着挂载态从 1 变 2。
#   07    空态对照（挂着盘、点一个不存在的名字）：合同里「点名点不到就什么都不选——宁可拍出
#         一张空态」那一档的照片，顺带给 01 做像素对照。见下面「时序」一节。
#
# ── 时序：为什么点名要留成对的两条 ───────────────────────────────────────
# 卸载页的点名解析 `confirmationTarget()`（`Packages/MMUninstaller/Sources/MMUninstaller/MMUninstaller.swift:109`）
# 在 `.task` 里排在 `await model.loadApps()` **之后**，而真扫 `/Applications`（本机 45 个应用）
# 要几十秒。第一版只留"点不到"这一条负向留痕，于是 01 的判据写成"日志里没有『没有对应的应用』⟹ 点到了"。
# 实测这一条会假绿：SETTLE=15 那一跑，01 与 02 两张 .log 里**都没有**负向留痕——
# 不是 01 点到了、02 也点到了，而是两档都还没走到点名（P6.7a 审计过的正是这一族 `.task` 竞态）。
# 落定耗时在本机不是常数：归档这一轮（`docs/verification/p49-external-volume/`，digest b539b844）三档实测
# 135 s / 93 s / 81 s——各档 `.log` 里「# 点名留痕：抓到（初等 30s + 轮询 Ns）」那三行就是现场；
# 写这套判据时同一族代码的另一轮是 96 s / 81 s / 126 s（产物只差注释，日志已被本轮覆盖没归档）。
# 两轮合起来 81 s ~ 135 s，**同一份产物在不同跑里都不重合**，
# 所以"多等一会儿"治不了它，把 settle 抬到 30 s 也照样有一半的档在猜。
# 修法是留痕做成**成对**：`confirmationTarget()` 现在两条路径各写一行，点中还把点到的路径抄进日志
# （`已点名到 <路径>` / `没有对应的应用`）。于是每档的判据都是正向断言，一条"缺席"都不再依赖：
#   01 必须有 `已点名到 /Volumes/MMVolumeP49/Applications/AaaP49VolumeFixture.app`；
#   02、07 必须有 `没有对应的应用`（02 是卸了盘点真名，07 是挂着盘点假名）。
# 抓屏前 `shot` 先轮询**任意一条**（`SELECT_RE`）——它锁的是"点名代码走到了"，轮到哪一条由
# 后面的核对分档断言；轮不到就在日志里留一条"没等到"，核对判红，不拿半成品照片冒充证据。
# 07 是合同那一档「点名点不到就什么都不选——宁可拍出一张空态」唯一的实拍，也给 01 做像素对照：
# 同一份二进制、同一个页面、同一块挂着的卷，只差点名值不同。
# 这条像素对给的是**必要条件**：两档逐字节相同 ⟹ 点名什么都没做，判红；不同**不**自动等于
# "选中了那一行"（清单在逐行补测尺寸，两帧本来就不会相同）。所以"选中"这件事由 01 的正向留痕
# 加人眼读那张的详情面板（「所在文件夹 /Volumes/MMVolumeP49/Applications」）一起钉，
# 顺手排掉"高亮只是因为它排第一"。
#
# 全程不带 `MM_VOLUME_FIXTURE`（03~06 的 .log 里出现它就算这一档没读真机，核对会判红），
# 也不带 `MM_UNINSTALL_CONFIRM_FIXTURE_HOME`：应用清单走的就是生产那一条
# `AppScanner.defaultSearchDirectories(home: NSHomeDirectory())`。
# 零合成点击；按 pid 抓自己的窗口，抓完即杀；卷由 p49-external-volume-fixture.sh 造与卸，
# 退出时（含中途失败）一定 detach，不 -force 弹盘。
#
#   ./Scripts/p49-external-volume-capture.sh <app 路径> <输出目录> [light|dark]
#   ./Scripts/p49-external-volume-capture.sh /tmp/mm-app-p49/MacMaster.app docs/verification/p49-external-volume
#   ONLY=03 ./Scripts/p49-external-volume-capture.sh …   只重拍 03 那一档
#   SETTLE=20 …                                          磁盘/概览页的等待；卸载页另有 30 s 下限
#   KEEP_MOUNT=1 …                                       跑完不卸盘（只有调试时用）
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SETTLE=${SETTLE:-15}
FIXTURE=/tmp/macmaster-disk-fixture
VOL=MMVolumeP49
MOUNT="/Volumes/$VOL"
SEED_APP=AaaP49VolumeFixture
# 07 那一档点的名：本机不存在这个名字，所以它**必然**走"没有对应的应用"那一条。
# 不能拿 `Bogus…` 开头——`MM_WINDOW_SIZE=Bogus…` 这类"把别的钩子的值写成它"的写法
# 会在日志里留下另一行含钩子名的话，判据就脏了。`Zz` 前缀既排最后也不像任何钩子名。
BOGUS_APP=ZzP49NoSuchApp
# 成对留痕里"任意一条"：轮询等的是"点名代码走到了"，具体哪一条由后面的核对分档断言。
SELECT_RE='MM_UNINSTALL_SELECT=.*(已点名到|没有对应的应用)'
FIX=Scripts/p49-external-volume-fixture.sh

[[ -d $FIXTURE ]] || { print -u2 -- "夹具不存在：先跑 ./Scripts/disk-fixture.sh"; exit 2; }
[[ -x $FIX ]] || { print -u2 -- "✗ 夹具脚本不存在或不可执行：$FIX"; exit 2; }

# 归因头 + 内容指纹门禁（配方见 mm-provenance.sh）：不等就一张都不出。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p49 -s /tmp/mm-scratch-p49 重新构建再取证。"
  exit 4
fi

# 盘：没有就造，然后挂上。退出时必卸（KEEP_MOUNT=1 除外）。
[[ -d $MOUNT ]] && ./$FIX detach >/dev/null
./$FIX create >/dev/null
./$FIX mount >/dev/null
cleanup() {
  if [[ ${KEEP_MOUNT:-0} == 1 ]]; then
    print -u2 -- "ℹ KEEP_MOUNT=1：$MOUNT 留在挂载态，调试完自己跑 ./$FIX detach"
  else
    ./$FIX detach || print -u2 -- "⚠ 收尾卸载失败，$MOUNT 可能还挂着（占着它的进程关掉再试）"
  fi
}
trap cleanup EXIT

mkdir -p "$OUT"
wants() { [[ -z ${ONLY:-} || $1 == ${ONLY}* ]] }

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

# 挂载态写进日志：这一档到底是"这台机器上多了一块卷"还是"脚本以为挂了其实没挂"，
# 只靠照片看不出来，所以把 /Volumes 的现场与卷内清单一起抄进 .log。
volume_note() {
  local mounted=no
  [[ -d $MOUNT ]] && mounted=yes
  print -r -- "# 卷：$MOUNT $( [[ $mounted == yes ]] && echo 已挂载 || echo 未挂载 )"
  if [[ $mounted == yes ]]; then
    print -r -- "#   df: $(df -k "$MOUNT" | awk 'NR==2 {print $1" 总 "$2"KB 可用 "$4"KB"}')"
    print -r -- "#   卷内 Applications: $(ls -1 "$MOUNT/Applications" 2>/dev/null | tr '\n' ' ')"
  fi
  print -r -- "#   /Volumes: $(ls -1 /Volumes 2>/dev/null | tr '\n' ' ')"
}

# shot <文件名> <挂载态：on|off> <页：uninst|disk|overview> [窗口宽x高] [点名值，默认 $SEED_APP] [等待的 stderr 正则]
# 卸载页那一族多两个参数，理由见文件头「时序」一节：`confirmationTarget()` 在 `.task` 里
# 排在 `await model.loadApps()` 之后，而真扫 /Applications 的耗时在本机从十几秒到两分钟以上都有
# （归档这一轮三档实测 135 s / 93 s / 81 s 才落定，见文件头「时序」一节），
# 所以"等固定秒数再看日志"这条根本站不住。改成抓屏前轮询成对留痕里的**任意一条**：
# 轮到才抓（再等 5 s 让选中态画出来），40 轮轮不到就在日志里留一条"没等到"，核对判红。
shot() {
  local name=$1 want=$2 page=$3 size=${4:-1400x900} select=${5:-$SEED_APP} wait_re=${6:-}
  wants $name || return 0
  if [[ $want == on ]]; then ./$FIX mount >/dev/null; else ./$FIX detach >/dev/null; fi
  local log="$OUT/$name.log"
  rm -f "$OUT/$name.png"
  local settle=$SETTLE
  [[ $page == uninst && $settle -lt 30 ]] && settle=30
  local -a hooks=()
  local hookNote=""
  case $page in
    uninst) hooks=(MM_OPEN_MODULE=uninstaller MM_UNINSTALL_SELECT="$select")
            hookNote=" MM_OPEN_MODULE=uninstaller MM_UNINSTALL_SELECT=$select" ;;
    disk)   hooks=(MM_OPEN_MODULE=disk MM_OPEN_TAB=tree MM_DISK_SCAN="$FIXTURE")
            hookNote=" MM_OPEN_MODULE=disk MM_OPEN_TAB=tree MM_DISK_SCAN=$FIXTURE" ;;
    overview) hookNote="（不带模块钩子：概览页是正常启动那一屏）" ;;
  esac
  print -r -- "# p49-external-volume-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_WINDOW_SIZE=$size$hookNote" >>"$log"
  print -r -- "# 卷这一档读的是这台机器的挂载表，不注合成快照（钩子名见 p35b 那一族）" >>"$log"
  volume_note >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_WINDOW_SIZE="$size" \
      $hooks \
      "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  local pid=$!
  sleep "$settle"
  # 轮询等的是**成对留痕里的任意一条**（`已点名到 <路径>` / `没有对应的应用`），
  # 不是"某一档的那一条"：等到任意一条 = 点名代码确实走到了，抓屏也就拍到了它落定的那一态。
  # 走到之后是哪一条，交给下面的核对逐档断言。
  if [[ -n $wait_re ]]; then
    local k=0 found=no
    while (( k <= 40 )); do
      if grep -qE "$wait_re" "$log"; then found=yes; break; fi
      sleep 3; k=$((k + 1))
    done
    if [[ $found == yes ]]; then
      print -r -- "# 点名留痕：抓到（初等 ${settle}s + 轮询 $((k * 3))s）：$(grep -E "$wait_re" "$log" | head -1)" >>"$log"
      # 留痕写的是模型选中了哪一条，界面把它画成高亮 + 详情面板还要一拍；不等一下就是
      # "日志说选中了、照片还是空态"那种自相矛盾的图。
      sleep 5
    else
      print -r -- "# 点名留痕：轮询 40 轮（${settle}s + 120s）没等到任何一条" >>"$log"
    fi
  fi
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
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid settle=${settle}s 挂载态=$want"
}

# 挂载态三档：清单里有它 / 徽标出现 / 页脚 2 个卷。
shot 01-uninst-mounted-lists-it on uninst 1400x900 "$SEED_APP" "$SELECT_RE" || true
shot 03-disk-mounted-badge on disk || true
shot 05-overview-mounted-count on overview || true
# 卸盘之后同参数再来一遍：这三张是前两组的对照，不是"再跑一次看看稳不稳"。
./$FIX info
shot 02-uninst-detached-absent off uninst 1400x900 "$SEED_APP" "$SELECT_RE" || true
shot 04-disk-detached-no-badge off disk || true
shot 06-overview-detached-count off overview || true
# 07 空态对照档：盘还挂着，点名一个不存在的名字。
# 它是 `MMUninstaller.swift` 里那句合同「点名点不到就什么都不选——宁可拍出一张空态，也不要
# 悄悄换成别的应用」唯一的实拍（其余各档都点得到），也是 01 的像素对照：同一份二进制、
# 同一个页面、同一块挂着的卷，只差点名值不同，两档逐字节相同就说明点名什么都没做。
# 它同样等成对留痕里的任意一条，然后由核对断言必须是「没有对应的应用」那一条。
shot 07-uninst-mounted-bogus-name on uninst 1400x900 "$BOGUS_APP" "$SELECT_RE" || true

typeset -a FAILED
for f in 01-uninst-mounted-lists-it 02-uninst-detached-absent 03-disk-mounted-badge \
         04-disk-detached-no-badge 05-overview-mounted-count 06-overview-detached-count \
         07-uninst-mounted-bogus-name; do
  wants $f || continue
  [[ -s "$OUT/$f.png" ]] || FAILED+=($f)
done

print -r -- ""
print -r -- "# 挂载态核对"
typeset -a PROBLEMS
# ① 每一档 .log 里的「# 卷：」那一行必须和它声明的挂载态一致——脚本以为挂了、
#    实际没挂，拍出来的就是"外接卷那一行不存在"的画面，而 01 那一档恰恰要靠画面说话。
for pair in "01-uninst-mounted-lists-it:已挂载" "03-disk-mounted-badge:已挂载" "05-overview-mounted-count:已挂载" \
            "07-uninst-mounted-bogus-name:已挂载" \
            "02-uninst-detached-absent:未挂载" "04-disk-detached-no-badge:未挂载" "06-overview-detached-count:未挂载"; do
  name=${pair%%:*}; want=${pair##*:}
  lg="$OUT/$name.log"
  [[ -s $lg ]] || continue
  if grep -q "^# 卷：$MOUNT $want" "$lg"; then
    print -r -- "  ✓ $name：挂载态留痕 = $want"
  else
    PROBLEMS+=("$name 的 .log 里「# 卷：」不是「$want」：这一档的挂载现场与声明不符")
  fi
done
# ② 点名留痕：成对的两条**各自正向断言**，一条"缺席"都不看（理由见文件头「时序」一节）。
#    判据不写 `.app` 后缀：写长了万一 `hit.path` 的形式与预期差一点，整条判据会以"没留痕"
#    的面目失败，读起来像竞态复发，实际是断言太脆。路径 + 应用名已经足够唯一。
for check in "01-uninst-mounted-lists-it|已点名到 $MOUNT/Applications/$SEED_APP|外接卷那一行进了清单，而且被点名选中" \
             "02-uninst-detached-absent|MM_UNINSTALL_SELECT=$SEED_APP 没有对应的应用|卸盘后这条候选不存在——外接卷那一行不是常驻清单" \
             "07-uninst-mounted-bogus-name|MM_UNINSTALL_SELECT=$BOGUS_APP 没有对应的应用|点不到就什么都不选（合同里的空态那一档）"; do
  name=${check%%|*}; rest=${check#*|}; pat=${rest%%|*}; why=${rest#*|}
  lg="$OUT/$name.log"
  [[ -s $lg ]] || continue
  hit_line=$(grep -m1 -F "$pat" "$lg" || true)
  if [[ -n $hit_line ]]; then
    print -r -- "  ✓ $name：${hit_line#MM_UNINSTALL_SELECT=} ⟹ $why"
  else
    PROBLEMS+=("$name 的日志里没有留痕「$pat」（这一档实际走到的是：$(grep -m1 -E 'MM_UNINSTALL_SELECT=.*(已点名到|没有对应的应用)' "$lg" || echo '一条都没有，即点名前抓的屏')）")
  fi
done
# 画面判据在下面「画面交叉核对」那一段，另有 01 那张照片本身：详情面板写着所在文件夹。
# ③ 真读守卫：03~06 这四档的价值全在"没注夹具"上，日志里出现 MM_VOLUME_FIXTURE 就作废。
for name in 03-disk-mounted-badge 04-disk-detached-no-badge 05-overview-mounted-count 06-overview-detached-count; do
  lg="$OUT/$name.log"
  [[ -s $lg ]] || continue
  if grep -q 'MM_VOLUME_FIXTURE' "$lg"; then
    PROBLEMS+=("$name 的日志里出现 MM_VOLUME_FIXTURE：这一档注入了合成快照，不是这台机器的读数")
  else
    print -r -- "  ✓ $name：没有卷夹具留痕"
  fi
done

print -r -- ""
print -r -- "# 画面交叉核对"
for png in "$OUT"/*.png(N); do
  print -r -- "  md5 $(md5 -q "$png")  $(basename $png)"
done
# 每对都写清该不该有可辨差异。量法沿用 P46e 立的那一条：单通道差 >8/255 的像素个数，
# 门槛 8 留一个数量级余量；md5 只列给人对账，不当判据（半透明横幅材质带 ±1/255 抖动）。
typeset -a PIX_PAIRS=(
  "01-uninst-mounted-lists-it|02-uninst-detached-absent|diff"
  "01-uninst-mounted-lists-it|07-uninst-mounted-bogus-name|diff"
  "03-disk-mounted-badge|04-disk-detached-no-badge|diff"
  "05-overview-mounted-count|06-overview-detached-count|info"
)
# 05↔06 不作硬判据，理由与 p35b 对 07/08 那两档同源：概览页页脚带着"数据更新于 …"与
# "上次采样 …"两个时刻在走的字段，**同一次运行的两张连拍都不会逐字节相同**，
# 所以"不同"不证明任何事。这一档的机械判据是上面 ① 的挂载态留痕加 ③ 的真读守卫，
# 页脚那个数字（1 → 2）由人对照片读；`docs/verification/p49-external-volume/volumes.log`
# 里那行「默认档条数=15 候选根=2」是它旁边的独立读数。
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
      else PROBLEMS+=("$a ↔ $b：可辨差异 0 个像素（最大幅度 $maxd）——挂载态变了而画面没变，这一档等于没拍到"); fi ;;
    info)
      print -r -- "  ℹ $a ↔ $b：可辨差异 $above 个像素（最大幅度 $maxd，不作判据，理由见上）" ;;
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
