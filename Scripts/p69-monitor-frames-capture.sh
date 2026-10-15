#!/bin/zsh
# P44 取证：监控页 §4 那张表里 #3–#9 七行——此前实机一张没拍过。
#
# 为什么这七行一直是 0 张（P43a 现读，2026-10-15）：
# - #3/#4/#5 唯一依赖 `MM_MONITOR_HOLD`，而这枚钩子从落地到今天**没有一支脚本调用过**
#   （`grep -rn MM_MONITOR_HOLD Scripts/` 0 命中）；钩子在代码里、档位是好的，缺的只是有人按它。
# - #6 的 `disk-unavailable:<reason>` 与 #7/#8/#9 的 `memoryNil`/`perCoreEmpty`/`perCoreRed`
#   四档只在枚举里存在，`Scripts/` 与 `docs/verification/` 两处 grep 都 0 命中。
# 所以这一族的成因是"有钩子没脚本"，不是"缺钩子"——和卸载页那 8 行（缺钩子语义）不同。
#
# 本轮同时补了 `MM_MONITOR_HOLD` 的**生效留痕**（`MonitorLoadHook.appliedNote`）：
# 这一档不改任何数值，冻结出来的画面和真机首帧本来就同形，没有那行 stderr 就分不开
# "钩子生效"与"钩子被忽略、恰好停在首帧"。夹具档早已有这一行（`MonitorFixtureTier.appliedNote`），
# HOLD 是这一族里最后一枚"只解析不出声"的钩子。判据因此是**留痕行 + 像素差异**两条一起用，
# 单看照片对 HOLD 这一族不成立。
#
# 十七档各拍什么（同号同名出浅/暗两套）：
#   01 HOLD·顶部读数 + 每核        折叠线以上第一屏：CPU 总占用「测量中」、每核单「—」（#4/#5/#8 的对照）
#   02 HOLD·磁盘 + 内存            两卡同时"尚未采样"（#4：磁盘 reason「尚未完成首次采样」+ 内存 nil 文案）
#   03 HOLD·进程                   `MMSkeletonRow` ×4（#3，D5 稿那一格）
#   04 HOLD·温度 + 电池            两张新卡的 `.notSampled` 首帧（§2 那两行也写着"见 §4 #4"）
#   05 HOLD·五卡全开 1600 高       整屏首帧的"折叠线"落点（稿 C 本体那一帧；窗口高度可能被屏幕夹住，见 .log）
#   06 磁盘 IO reason①             `IOServiceMatching("IOBlockStorageDriver") 返回空…`
#   07 磁盘 IO reason②             `枚举 IOBlockStorageDriver 失败：<detail>`（占位段真机给的是 mach 错误码）
#   08 磁盘 IO reason③             `所有磁盘驱动均未暴露 Statistics 字典（可能被沙盒/权限限制）`
#   09 磁盘 IO reason④             `未发现任何 IOBlockStorageDriver 设备`
#   10 内存 nil 分支               `memoryNil`：hasSampled=true 但 memory=nil ⟹「host_statistics64 失败」那一套（#7）
#   11 每核空数组                  `perCoreEmpty`：卡内单个居中「—」，不是 10 行空槽（#8）
#   12 每核红档                   `perCoreRed`：核 1 = 91.4%，条与数值同时 destructive（#9，本机峰值量不到）
#   13 磁盘真读数（基线）          不注夹具，`.ok` 那一帧——06~09 的"必须与它不同"的对照
#   14 每核真读数（基线）          同上，11/12 的对照
#   15 内存真读数（基线）          同上，10 的对照
#   16 HOLD·窄窗 1000x760          首帧那一屏在硬最小宽度下挤不挤（P25/P26 那一族口径）
#   17 HOLD 非法取值               `MM_MONITOR_HOLD=holdTypo` ⟹ 整枚钩子作废、回落真实采样；判据在 stderr
#
# 全程零合成点击；按 pid 抓自己的窗口（主窗口必须正好一扇，否则不产出照片），抓完即杀，只 kill 自己起的 pid。
# 这一族不读盘、不写盘、不请求权限——夹具是纯数值注入（`MonitorFixtureHooks.swift` 头行那条铁律）。
#
#   ./Scripts/p69-monitor-frames-capture.sh <app 路径> <输出目录> [light|dark]
#   ./Scripts/p69-monitor-frames-capture.sh /tmp/mm-app-p69/MacMaster.app docs/verification/p69-monitor-frames
#   ONLY=03 ./Scripts/p69-monitor-frames-capture.sh …     只重拍 03 那一档
#   SETTLE=8 …                                            改基础等待（默认 6）
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SETTLE=${SETTLE:-6}

# 归因头 + 内容指纹门禁（配方见 mm-provenance.sh）：不等就一张都不出。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p69 -s /tmp/mm-scratch-p69 重新构建再取证。"
  exit 4
fi

mkdir -p "$OUT"
wants() { [[ -z ${ONLY:-} || $1 == ${ONLY}* ]] }

main_window_id() {
  local pid=$1 log=$2 all wid n
  all=$(swift Scripts/window-ids.swift --pid "$pid" 2>>"$log" || true)
  print -r -- "# windows(pid=$pid): ${all//$'\n'/ | }" >>"$log"
  # `window-ids.swift` 给的是 `bounds=["X": …, "Height": …]`，键名不是 `frame=`、值里带空格：
  # 第一版照脑子里的格式写了 `s/.*frame=\([^ ]*\).*/`，于是每一档的 `# frame:` 都是「未取到」。
  LAST_FRAME=$(printf '%s\n' "$all" | sed -n 's/.*layer=0 title=MacMaster \(bounds=.*\)/\1/p' | head -1)
  n=$(printf '%s\n' "$all" | grep -c 'layer=0 title=MacMaster bounds=' || true)
  [[ $n == 1 ]] || return 1
  wid=$(printf '%s\n' "$all" | sed -n 's/^windowid=\([0-9]*\) .*layer=0 title=MacMaster bounds=.*/\1/p')
  [[ -n $wid ]] || return 1
  print -r -- "$wid"
}

# shot <文件名> <额外等待秒> <窗口宽x高> <MM_MONITOR_CARDS 的值> <HOLD 的值，空=不冻结> <夹具的值，空=不注入>
# 返回非 0 = 这一档没拍到；调用处一律兜住 `set -e`，最后由 png 存在性统一判失败。
shot() {
  local name=$1 extra=$2 size=$3 cards=$4 hold=$5 fixture=$6
  wants $name || return 0
  local log="$OUT/$name.log"
  rm -f "$OUT/$name.png"
  print -r -- "# p69-monitor-frames-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_WINDOW_SIZE=$size MM_OPEN_MODULE=monitor MM_MONITOR_CARDS=$cards${hold:+ MM_MONITOR_HOLD=$hold}${fixture:+ MM_MONITOR_FIXTURE=$fixture}" >>"$log"
  print -r -- "# 卡：$cards   # 冻结：${hold:-（未冻结，onAppear 正常启动采样）}   # 夹具：${fixture:-（未注入，读这台机器）}" >>"$log"
  # 含空格/引号的 reason 走元素级引号：裸拼会被 env 当成两个参数、后半句变成"命令"（同 p37 那一档的坑）。
  local -a fxenv
  if [[ -n $hold ]]; then fxenv+=("MM_MONITOR_HOLD=$hold"); fi
  if [[ -n $fixture ]]; then fxenv+=("MM_MONITOR_FIXTURE=$fixture"); fi
  env MM_APPEARANCE="$APPEARANCE" MM_WINDOW_SIZE="$size" MM_OPEN_MODULE=monitor \
      MM_MONITOR_CARDS="$cards" $fxenv \
      "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  local pid=$!
  sleep $((SETTLE + extra))
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
  print -r -- "# frame: ${LAST_FRAME:-未取到}" >>"$log"
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid settle=$((SETTLE + extra))s ${hold:+hold=$hold} ${fixture:+fixture=$fixture}"
}

# ── #3/#4/#5：冻结首帧（HOLD 档此前 0 支脚本用过）────────────────────────
shot 01-monitor-hold-stats-percore 0 1400x900 "stats,perCore" hold ""
shot 02-monitor-hold-disk-memory    0 1400x900 "disk,memory"  hold ""
shot 03-monitor-hold-process-skeleton 0 1400x900 "process"    hold ""
shot 04-monitor-hold-sensors-battery  0 1400x900 "sensors,battery" hold ""
shot 05-monitor-hold-five-cards      0 1400x1600 "stats,perCore,disk,memory,process" hold ""
# ── #6：磁盘 IO 四种 reason（原文逐字来自 MetricReaders.swift 的失败分支）──
shot 06-monitor-disk-reason-matching 0 1400x900 disk "" \
     'disk-unavailable:IOServiceMatching("IOBlockStorageDriver") 返回空，无法枚举磁盘统计'
shot 07-monitor-disk-reason-enum 0 1400x900 disk "" \
     'disk-unavailable:枚举 IOBlockStorageDriver 失败：0xe00002c7'
shot 08-monitor-disk-reason-nostats 0 1400x900 disk "" \
     'disk-unavailable:所有磁盘驱动均未暴露 Statistics 字典（可能被沙盒/权限限制）'
shot 09-monitor-disk-reason-nodriver 0 1400x900 disk "" \
     'disk-unavailable:未发现任何 IOBlockStorageDriver 设备'
# ── #7/#8/#9：nil 分支、空数组、红档 ─────────────────────────────────────
shot 10-monitor-memory-nil     0 1400x900 memory "" memoryNil
shot 11-monitor-percore-empty  0 1400x900 perCore "" perCoreEmpty
shot 12-monitor-percore-red    0 1400x900 perCore "" perCoreRed
# ── 三张基线（不注夹具）：上面那些"必须与真读数不同"的判据要靠它们 ─────────
shot 13-monitor-disk-real      4 1400x900 disk "" ""
shot 14-monitor-percore-real   4 1400x900 perCore "" ""
shot 15-monitor-memory-real    4 1400x900 memory "" ""
# ── 窄窗与拒值 ───────────────────────────────────────────────────────────
shot 16-monitor-hold-narrow 0 1000x760 "stats,perCore,disk,memory,process" hold ""
# 17：非法 HOLD 取值 ⟹ 整枚钩子作废，走的是 13/14/15 那条真实采样路径；判据在 stderr。
shot 17-monitor-hold-invalid 4 1400x900 "stats,perCore" holdTypo ""

typeset -a NAMES=(
  01-monitor-hold-stats-percore 02-monitor-hold-disk-memory 03-monitor-hold-process-skeleton
  04-monitor-hold-sensors-battery 05-monitor-hold-five-cards
  06-monitor-disk-reason-matching 07-monitor-disk-reason-enum
  08-monitor-disk-reason-nostats 09-monitor-disk-reason-nodriver
  10-monitor-memory-nil 11-monitor-percore-empty 12-monitor-percore-red
  13-monitor-disk-real 14-monitor-percore-real 15-monitor-memory-real
  16-monitor-hold-narrow 17-monitor-hold-invalid)
typeset -a FAILED
for f in $NAMES; do
  wants $f || continue
  [[ -s "$OUT/$f.png" ]] || FAILED+=($f)
done

# ── 核对：三组断言 ──────────────────────────────────────────────────────
# ① 卡别（echo 级）：每档 .log 必须写明它落在哪几张卡的渲染范围里，挡"参数没传到"。
# ② 留痕：HOLD 档必须有「MM_MONITOR_HOLD=hold 已生效」；夹具档必须有对应档名的「已生效」；
#    13/14/15 两张基线必须**没有**任何「已生效」；17 必须有「含非法取值」且没有 HOLD 的「已生效」。
# ③ md5：夹具/冻结帧与同卡基线两两不同（否则钩子没被消费）；11↔12 不同（空数组与红档是两句话）；
#    06~09 四张互不相同（四种 reason 各占一格）；05↔16 不同（窗口尺寸确实被读）；
#    01↔05 不同（卡片过滤确实被消费，见下面那条的注释）。
print -r -- ""
print -r -- "# 卡别核对"
typeset -a PROBLEMS
typeset -A CARDS_OF
CARDS_OF[01-monitor-hold-stats-percore]="stats,perCore"
CARDS_OF[02-monitor-hold-disk-memory]="disk,memory"
CARDS_OF[03-monitor-hold-process-skeleton]="process"
CARDS_OF[04-monitor-hold-sensors-battery]="sensors,battery"
CARDS_OF[05-monitor-hold-five-cards]="stats,perCore,disk,memory,process"
CARDS_OF[06-monitor-disk-reason-matching]="disk"
CARDS_OF[07-monitor-disk-reason-enum]="disk"
CARDS_OF[08-monitor-disk-reason-nostats]="disk"
CARDS_OF[09-monitor-disk-reason-nodriver]="disk"
CARDS_OF[10-monitor-memory-nil]="memory"
CARDS_OF[11-monitor-percore-empty]="perCore"
CARDS_OF[12-monitor-percore-red]="perCore"
CARDS_OF[13-monitor-disk-real]="disk"
CARDS_OF[14-monitor-percore-real]="perCore"
CARDS_OF[15-monitor-memory-real]="memory"
CARDS_OF[16-monitor-hold-narrow]="stats,perCore,disk,memory,process"
CARDS_OF[17-monitor-hold-invalid]="stats,perCore"
for name in $NAMES; do
  lg="$OUT/$name.log"
  [[ -s $lg ]] || continue
  cards=${CARDS_OF[$name]}
  if grep -q "^# 卡：$cards " "$lg"; then
    print -r -- "  ✓ $name：渲染范围 = $cards"
  else
    PROBLEMS+=("$name 的 .log 没写「# 卡：$cards」：这一档的 MM_MONITOR_CARDS 没传到")
  fi
  # 上面那一行只是复读脚本自己传的参数，它挡不住"传到了却被解析端整批作废"——
  # 本轮实拍撞上的正是这一格（`perCore` 驼峰 rawValue 被小写比对判成非法值）。
  # 所以这里补一条硬断言：任何一档都不许出现卡表被拒的那行留痕。
  if grep -q 'MM_MONITOR_CARDS 含非法取值' "$lg"; then
    PROBLEMS+=("$name 的 .log 里有「MM_MONITOR_CARDS 含非法取值」：卡表被整批作废，这张画的是全部卡，$(grep -m1 'MM_MONITOR_CARDS 含非法取值' "$lg")")
  fi
done

print -r -- ""
print -r -- "# 留痕核对"
# HOLD 生效的档位（01–05、16）
for name in 01-monitor-hold-stats-percore 02-monitor-hold-disk-memory \
            03-monitor-hold-process-skeleton 04-monitor-hold-sensors-battery \
            05-monitor-hold-five-cards 16-monitor-hold-narrow; do
  lg="$OUT/$name.log"; [[ -s $lg ]] || continue
  if grep -q 'MM_MONITOR_HOLD=hold 已生效' "$lg"; then
    print -r -- "  ✓ $name：HOLD 留痕行在（冻结首帧，未启动采样）"
  else
    PROBLEMS+=("$name 没有「MM_MONITOR_HOLD=hold 已生效」：这一档的钩子没被消费，照片拍的是真实采样帧")
  fi
done
# 夹具生效的档位（06–12），留痕行必须点名到具体档位
typeset -A TIER_OF
TIER_OF[06-monitor-disk-reason-matching]=diskUnavailable
TIER_OF[07-monitor-disk-reason-enum]=diskUnavailable
TIER_OF[08-monitor-disk-reason-nostats]=diskUnavailable
TIER_OF[09-monitor-disk-reason-nodriver]=diskUnavailable
TIER_OF[10-monitor-memory-nil]=memoryNil
TIER_OF[11-monitor-percore-empty]=perCoreEmpty
TIER_OF[12-monitor-percore-red]=perCoreRed
for name in 06-monitor-disk-reason-matching 07-monitor-disk-reason-enum \
            08-monitor-disk-reason-nostats 09-monitor-disk-reason-nodriver \
            10-monitor-memory-nil 11-monitor-percore-empty 12-monitor-percore-red; do
  lg="$OUT/$name.log"; [[ -s $lg ]] || continue
  if grep -q "MM_MONITOR_FIXTURE=${TIER_OF[$name]} 已生效" "$lg"; then
    print -r -- "  ✓ $name：留痕行在（${TIER_OF[$name]}，合成快照不是这台机器的读数）"
  else
    PROBLEMS+=("$name 没有「MM_MONITOR_FIXTURE=${TIER_OF[$name]} 已生效」：夹具没走到这一档")
  fi
done
# 基线三张：出现任何「已生效」就说明钩子漏进来了，那三张不是真读数
for name in 13-monitor-disk-real 14-monitor-percore-real 15-monitor-memory-real; do
  lg="$OUT/$name.log"; [[ -s $lg ]] || continue
  if grep -q '已生效' "$lg"; then
    PROBLEMS+=("$name（基线）的 .log 里出现了「已生效」：这一档不该注入夹具或冻结")
  else
    print -r -- "  ✓ $name：没有钩子留痕，读的是这台机器"
  fi
done
# 17：拒值留痕必须在，HOLD 生效留痕必须不在
if [[ -s "$OUT/17-monitor-hold-invalid.log" ]]; then
  if grep -q 'MM_MONITOR_HOLD 含非法取值' "$OUT/17-monitor-hold-invalid.log"; then
    print -r -- "  ✓ 17 的 stderr 有拒值留痕：$(grep -m1 'MM_MONITOR_HOLD 含非法取值' "$OUT/17-monitor-hold-invalid.log")"
  else
    PROBLEMS+=("17 的 stderr 没有「MM_MONITOR_HOLD 含非法取值」那一行：守卫没留痕")
  fi
  if grep -q 'MM_MONITOR_HOLD=hold 已生效' "$OUT/17-monitor-hold-invalid.log"; then
    PROBLEMS+=("17 整枚钩子作废了却还留了 HOLD 的「已生效」：作废与生效同时成立，判据失效")
  fi
fi

print -r -- ""
print -r -- "# md5 交叉核对"
typeset -A M
for png in "$OUT"/*.png(N); do
  m=$(md5 -q "$png")
  M[$(basename "$png" .png)]=$m
  print -r -- "  $m  $(basename $png)"
done
# 夹具 ↔ 同卡基线：卡集相同、夹具值相同而照片逐字节相同，只能是钩子没被消费。
# **HOLD 那五档（01–05、16）不进"夹具↔基线"这一组**：它们没有同卡集的"真实采样"对照帧，
# 而且真读数逐帧在走，"与真帧不同"这条永远成立——那是假绿。HOLD 的凭据主要是留痕行，
# 这正是本轮给 `MonitorLoadHook` 补 `appliedNote` 的原因。
# 但 01↔05 是**另一条判据**（下面单列）：两档都是"HOLD + 无夹具"，唯一差别就是卡集，
# 所以"卡片过滤整批被忽略"会让两张逐字节相同——这一条恰好抓到了本轮实拍出的那个缺陷
# （`perCore` 是驼峰 rawValue，解析却先把输入小写，于是带它的任何卡集都必然整批作废）。
for pair in "06-monitor-disk-reason-matching:13-monitor-disk-real" \
            "07-monitor-disk-reason-enum:13-monitor-disk-real" \
            "08-monitor-disk-reason-nostats:13-monitor-disk-real" \
            "09-monitor-disk-reason-nodriver:13-monitor-disk-real" \
            "10-monitor-memory-nil:15-monitor-memory-real" \
            "11-monitor-percore-empty:14-monitor-percore-real" \
            "12-monitor-percore-red:14-monitor-percore-real"; do
  a=${pair%%:*}; b=${pair##*:}
  [[ -n ${M[$a]} && -n ${M[$b]} ]] || continue
  [[ ${M[$a]} != ${M[$b]} ]] || PROBLEMS+=("$a 与 $b 逐字节相同：这一档的钩子没被消费")
done
# 四种 reason 互不相同
for a in 06-monitor-disk-reason-matching 07-monitor-disk-reason-enum \
         08-monitor-disk-reason-nostats 09-monitor-disk-reason-nodriver; do
  for b in 06-monitor-disk-reason-matching 07-monitor-disk-reason-enum \
           08-monitor-disk-reason-nostats 09-monitor-disk-reason-nodriver; do
    [[ $a < $b ]] || continue
    [[ -n ${M[$a]} && -n ${M[$b]} ]] || continue
    [[ ${M[$a]} != ${M[$b]} ]] || PROBLEMS+=("$a ↔ $b 两张完全相同：两种 reason 拍成了同一句")
  done
done
# 空数组 ↔ 红档：两档唯一的共同点是同一张卡、同一个过滤，相同只能是夹具值没落到快照上
if [[ -n ${M[11-monitor-percore-empty]} && -n ${M[12-monitor-percore-red]} ]]; then
  [[ ${M[11-monitor-percore-empty]} != ${M[12-monitor-percore-red]} ]] \
    || PROBLEMS+=("11 ↔ 12 两张完全相同：perCoreEmpty 与 perCoreRed 分不开")
fi
# 01 ↔ 05：两档都是「HOLD + 不注夹具」，冻结帧本身是确定的，唯一变量就是卡集。
# 卡片过滤若被整批忽略，两张都画成"七块卡全在"，就会逐字节相同。
# （侧栏那两格真实体积若在两档之间跳了，只会让两张更不同——这条判的是"不许相同"，方向上安全。）
if [[ -n ${M[01-monitor-hold-stats-percore]} && -n ${M[05-monitor-hold-five-cards]} ]]; then
  [[ ${M[01-monitor-hold-stats-percore]} != ${M[05-monitor-hold-five-cards]} ]] \
    || PROBLEMS+=("01 ↔ 05 两张完全相同：MM_MONITOR_CARDS 没被消费，两张都画了全部卡")
fi
# 冻结首帧 ↔ 窄窗同钩子不同尺寸：相同只能是 MM_WINDOW_SIZE 没起作用
if [[ -n ${M[05-monitor-hold-five-cards]} && -n ${M[16-monitor-hold-narrow]} ]]; then
  [[ ${M[05-monitor-hold-five-cards]} != ${M[16-monitor-hold-narrow]} ]] \
    || PROBLEMS+=("05 ↔ 16 两张完全相同：窗口尺寸没起作用")
fi
# 17 与 01 是同一个卡集（stats,perCore）：01 冻结、17 作废后走真实采样。
# 两帧必然不同（真读数逐帧在走），所以这一条**不作判据**，只把两档并排放着好看形状：
# 17 的凭据是上面那条拒值留痕行，不在照片。
if [[ -n ${M[17-monitor-hold-invalid]} && -n ${M[01-monitor-hold-stats-percore]} ]]; then
  print -r -- "  ℹ 01（冻结）与 17（作废后真实采样）同卡集，判据在各自的留痕行、不比照片"
fi
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
