#!/bin/zsh
# P37 取证：监控页「电池」卡（AppleSmartBattery 只读）。
#
# 为什么要夹具这一整套：这台开发机是 **Mac mini M4，没有内置电池**。
# `Scripts/p37-battery-probe.swift` 2026-10-13 实测：`AppleSmartBattery` 节点在、29 个键读得到，
# 但 `BatteryInstalled`=No（NSNumber `c` false），`CurrentCapacity/MaxCapacity/CycleCount/…` 全在而全 0，
# `AppleRawCurrentCapacity/DesignCapacity/…` 这些算健康度要用的键**根本不存在**。
# 所以"有电池"的每一档（loaded / 缺健康度 / 充电中）在真机上永远拍不到，
# 只能由 `MM_MONITOR_FIXTURE` 的合成快照出片——判据留在 `BatterySnapshot.assemble(from:)` 里（单测钉规则），
# 照片钉"这句话放得下、也确实是这么写的"。
# **合成值只证明界面会写字，不证明这台机器有电池**——每一档的 .log 里都有一行
# 「MM_MONITOR_FIXTURE=<档> 已生效：这是合成快照」的留痕，就是把这句话写在证据里。
#
# 反过来，01 那一档是这张卡**唯一**的真读数：它证明 `.app` 进程内 IOKit 真能问到 AppleSmartBattery，
# 而问出来的答案是"没有电池"。（独立探针能读不代表沙盒外的 .app 能读，这条区分与 P6.4 的 SMC 同一回事。）
#
# 八档各拍什么：
#   01 真机档（不注夹具）：BatteryInstalled=No ⟹「本机没有内置电池…不是读取故障」+ 图标 powerplug。
#   02 loaded 底座：63% / 82% / 214 / 电源一句。出片里的数与 `BatteryTests` 那组字典同源（4100÷5000=82%）。
#   03 缺健康度：健康度「—」+ 那句"未知不等于 100%"的 caption（这一族最长的一句）。
#   04 充电中 + 系统给了估计：状态行与「预计剩余 1 小时 36 分」一次拍全。
#   05 整卡不可用：值位「—」+ reason 原文（reason 由钩子给，与磁盘 IO / 温度卡同一套降级话术）。
#   06 非法取值 batteryTypo：整批作废 ⟹ 回落 01 那条真路径。判据在 stderr，照片只是佐证。
#   07 相邻与间距：`sensors,battery` 两卡同屏，看卡间距与页底留白（单卡那张证明不了顺序）。
#   08 窄窗 1000x760：03 那一档在最硬的最小宽度下挤不挤得下（P25/P26 那一族的口径）。
#
# 全程零合成点击；按 pid 抓自己的窗口，抓完即杀，只 kill 自己起的进程。这一族不读盘、不写盘、不请求权限。
#
#   ./Scripts/p37-battery-capture.sh <app 路径> <输出目录> [light|dark]
#   ./Scripts/p37-battery-capture.sh /tmp/mm-app-p37/MacMaster.app docs/verification/p37-battery
#   ONLY=02 ./Scripts/p37-battery-capture.sh …        只重拍 02 那一档
#   SETTLE=10 …                                        改基础等待（01 那档另加 4 秒等首次采样）
#
# 监控页一直在用的那批夹具（`MM_MONITOR_FIXTURE`）本次只是加档，没有新增夹具文件。
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
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p37 -s /tmp/mm-scratch-p37 重新构建再取证。"
  exit 4
fi

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

# shot <文件名> <额外等待秒> <窗口宽x高> <MM_MONITOR_CARDS 的值> <MM_MONITOR_FIXTURE 的值，空=不注入>
# 返回非 0 = 这一档没拍到；调用处一律 `|| true` 兜住 `set -e`，最后由 png 存在性统一判失败。
shot() {
  local name=$1 extra=$2 size=$3 cards=$4 fixture=$5
  wants $name || return 0
  local log="$OUT/$name.log"
  rm -f "$OUT/$name.png"
  print -r -- "# p37-battery-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_WINDOW_SIZE=$size MM_OPEN_MODULE=monitor MM_MONITOR_CARDS=$cards${fixture:+ MM_MONITOR_FIXTURE=$fixture}" >>"$log"
  print -r -- "# 卡：$cards   # 夹具：${fixture:-（未注入，读这台机器的 AppleSmartBattery）}" >>"$log"
  # 夹具那一条走数组而不是裸字符串：05 的 reason 里有空格，裸拼会被 env 当成两个参数、
  # 后半句变成"命令"（p64 那一档就是靠整条加引号绕过去的，这里用元素级引号）。
  local -a fxenv
  if [[ -n $fixture ]]; then fxenv=("MM_MONITOR_FIXTURE=$fixture"); fi
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
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid settle=$((SETTLE + extra))s ${fixture:+fixture=$fixture}"
}

# 01 真机档：等久一点——夹具档是 onAppear 同步落值，这一档要等第一次采样真的跑完 IOKit 那一趟。
shot 01-monitor-battery-real 4 1400x900 battery ""
# 02 loaded 底座：判据是四行都在、健康度是 82% 不是 100%（那一格缺分母时必须退成 —，见 03）。
shot 02-monitor-battery-loaded 0 1400x900 battery "battery"
# 03 缺健康度：health=nil ⟹「—」+ 那句 caption。**这一档是这张卡的 nil-not-zero 判据**。
shot 03-monitor-battery-nohealth 0 1400x900 battery "batteryNoHealth"
# 04 充电中 + 预计剩余：96 分钟要写成「1 小时 36 分」，且这一行只在拿得到估计时才出现。
shot 04-monitor-battery-charging 0 1400x900 battery "batteryCharging"
# 05 整卡不可用：reason 由钩子给原文，验证"不静默、不塌成空卡"（话术与磁盘 IO / 温度卡同一族）。
# 整条赋值要加引号——reason 文案里有空格，不加引号 env 会把后半句当命令。
shot 05-monitor-battery-unavailable 0 1400x900 battery \
     "battery-unavailable:IOServiceGetMatchingService 找不到 AppleSmartBattery 节点"
# 06 非法取值：整批作废 → 走的就是 01 那条生产路径。判据在 .log 里（见末尾核对），照片只作佐证。
shot 06-monitor-battery-invalid-voided 4 1400x900 battery "batteryTypo"
# 07 相邻与间距：电池卡排在温度卡之后，单卡渲染看不出卡间距与页底留白。
shot 07-monitor-battery-after-sensors 0 1400x900 "sensors,battery" "sensors,battery"
# 08 窄窗：1000 pt 是硬最小宽度，03 那句 caption 是这张卡最长的文案。
shot 08-monitor-battery-narrow 0 1000x760 battery "batteryNoHealth"

typeset -a FAILED
for f in 01-monitor-battery-real 02-monitor-battery-loaded 03-monitor-battery-nohealth \
         04-monitor-battery-charging 05-monitor-battery-unavailable \
         06-monitor-battery-invalid-voided 07-monitor-battery-after-sensors \
         08-monitor-battery-narrow; do
  wants $f || continue
  [[ -s "$OUT/$f.png" ]] || FAILED+=($f)
done

# ── 核对：三组断言 + 一组信息 ────────────────────────────────────────
# ① 卡别（echo 级）：每一档的 .log 必须写明它落在哪几张卡的渲染范围里。
#    这一条本身只是复读脚本自己写的那一行，它挡的是"参数没传到"这一类写法事故
#    （P35b 的 `# 页：` 核对抓到的正是这个）；**真正能证明卡过滤被消费的是 ③ 里 02↔07 那一条**。
# ② 留痕：注入夹具的档必须有「MM_MONITOR_FIXTURE=<档> 已生效」；06 必须有「含非法取值」
#    且必须**没有**「已生效」；01 必须两个都没有（有就是环境变量漏进来了，那就不是真机档）。
# ③ md5：夹具档与 01 不同（否则夹具没生效）；02↔07、02↔03、03↔08 必须两两不同，
#    这三条是"卡片过滤被消费""健康度这一格确实会退""窗口宽度确实被读"的像素级证据。
#    06 与 01 同形是**设计如此**（作废后走的就是同一条生产路径），只作信息打印。
print -r -- ""
print -r -- "# 卡别核对"
typeset -a PROBLEMS
for pair in "01-monitor-battery-real:battery" "02-monitor-battery-loaded:battery" \
            "03-monitor-battery-nohealth:battery" "04-monitor-battery-charging:battery" \
            "05-monitor-battery-unavailable:battery" "06-monitor-battery-invalid-voided:battery" \
            "07-monitor-battery-after-sensors:sensors,battery" "08-monitor-battery-narrow:battery"; do
  name=${pair%%:*}; cards=${pair##*:}
  lg="$OUT/$name.log"
  [[ -s $lg ]] || continue
  if grep -q "^# 卡：$cards   # 夹具：" "$lg"; then
    print -r -- "  ✓ $name：渲染范围 = $cards"
  else
    PROBLEMS+=("$name 的 .log 没写「# 卡：$cards」：这一档的 MM_MONITOR_CARDS 没传到")
  fi
done

print -r -- ""
print -r -- "# 留痕核对"
for pair in "02-monitor-battery-loaded:battery" "03-monitor-battery-nohealth:batteryNoHealth" \
            "04-monitor-battery-charging:batteryCharging" "05-monitor-battery-unavailable:batteryUnavailable" \
            "07-monitor-battery-after-sensors:battery" "08-monitor-battery-narrow:batteryNoHealth"; do
  name=${pair%%:*}; tier=${pair##*:}
  lg="$OUT/$name.log"
  [[ -s $lg ]] || continue
  if grep -q "MM_MONITOR_FIXTURE=$tier 已生效" "$lg"; then
    print -r -- "  ✓ $name：留痕行在（合成快照，非这台机器的读数）"
  else
    PROBLEMS+=("$name 的 .log 没有「MM_MONITOR_FIXTURE=$tier 已生效」那一行：夹具没走到这一档")
  fi
done
# 01 是**反向**判据：这一档没注夹具，日志里若出现「已生效」就说明钩子漏进来了，那这张不是真机档。
if [[ -s "$OUT/01-monitor-battery-real.log" ]]; then
  if grep -q '已生效' "$OUT/01-monitor-battery-real.log"; then
    PROBLEMS+=("01（真机档）的 .log 里出现了「已生效」：这一档不该注入夹具")
  else
    print -r -- "  ✓ 01：没有夹具留痕，读的是这台机器的 AppleSmartBattery"
  fi
fi
if [[ -s "$OUT/06-monitor-battery-invalid-voided.log" ]]; then
  if grep -q '含非法取值' "$OUT/06-monitor-battery-invalid-voided.log"; then
    print -r -- "  ✓ 06 的 stderr 有留痕：$(grep -m1 '含非法取值' "$OUT/06-monitor-battery-invalid-voided.log")"
  else
    PROBLEMS+=("06 的 stderr 没有「含非法取值」那一行：守卫没留痕")
  fi
  if grep -q '已生效' "$OUT/06-monitor-battery-invalid-voided.log"; then
    PROBLEMS+=("06 整批作废了却还留了「已生效」：作废与生效同时成立，判据失效")
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
for t in 02-monitor-battery-loaded 03-monitor-battery-nohealth 04-monitor-battery-charging \
         05-monitor-battery-unavailable; do
  [[ -n ${M[$t]} && -n ${M[01-monitor-battery-real]} ]] || continue
  [[ ${M[$t]} != ${M[01-monitor-battery-real]} ]] || PROBLEMS+=("$t 与 01 相同：这一档的夹具没生效")
done
# 02 与 07 的夹具值都是确定的（`baseSensors()` 与 loaded 电池都是定格数），
# 所以"过滤真的被消费"这件事能做成硬断言：**MM_MONITOR_CARDS 若被整批忽略，两档会逐字节相同**。
if [[ -n ${M[02-monitor-battery-loaded]} && -n ${M[07-monitor-battery-after-sensors]} ]]; then
  [[ ${M[02-monitor-battery-loaded]} != ${M[07-monitor-battery-after-sensors]} ]] \
    || PROBLEMS+=("02 ↔ 07 两张完全相同：MM_MONITOR_CARDS 没被消费（07 少画了温度卡）")
fi
# 02 与 03 唯一的差别是健康度那一格加一句 caption；相同只能是 `health: nil` 没落到快照上。
if [[ -n ${M[02-monitor-battery-loaded]} && -n ${M[03-monitor-battery-nohealth]} ]]; then
  [[ ${M[02-monitor-battery-loaded]} != ${M[03-monitor-battery-nohealth]} ]] \
    || PROBLEMS+=("02 ↔ 03 两张完全相同：健康度这一格没退成 —")
fi
# 03 与 08 同夹具、不同窗宽：相同只能是 MM_WINDOW_SIZE 没起作用（P35b 的 02↔05 同一条判据）。
if [[ -n ${M[03-monitor-battery-nohealth]} && -n ${M[08-monitor-battery-narrow]} ]]; then
  [[ ${M[03-monitor-battery-nohealth]} != ${M[08-monitor-battery-narrow]} ]] \
    || PROBLEMS+=("03 ↔ 08 两张完全相同：窗口宽度没起作用")
fi
for name in 06-monitor-battery-invalid-voided; do
  [[ -n ${M[$name]} && -n ${M[01-monitor-battery-real]} ]] || continue
  if [[ ${M[$name]} == ${M[01-monitor-battery-real]} ]]; then
    print -r -- "  ℹ $name 与 01 逐字节相同（设计如此：作废后走的就是 01 那条路径；判据在留痕行）"
  else
    print -r -- "  ℹ $name 与 01 不同（真采样的「上次采样 …」是帧间在走的字段，不作判据）"
  fi
done
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
